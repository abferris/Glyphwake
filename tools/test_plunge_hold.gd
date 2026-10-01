extends SceneTree

## Plunge-hold test: jumping into the water must stay an ordinary upright fall until the water
## has actually caught the body.
##
## The WaterZone box spans y 55..105 around a water surface at y 80, so it reaches 25 m *above*
## the water, and submersion alone runs out long before speed does: a body dropping in from 20 m
## is still doing 19 m/s as its feet cross the waterline and is 0.6 submerged within two ticks.
## Resolving Mode on depth alone therefore swapped the fall clip for the swimming clip on a body
## that was still falling at 6.8 m/s, which is the tuck the player reported. LocomotionState now
## latches a plunge (IsPlunging) on downward speed and holds Mode at EnteringWater until the
## float has slowed the body, and the swim pose modifier waits on IsSurfaceSwimming for the same
## reason.
##
## This drives a low ledge with the camera pitched down, because a player watching where they are
## going is what exposed the second half of the report: UpdateBodyPitch keys off
## UnderwaterSwimming, and a look-down camera asks for more than 90 degrees of pitch, so the body
## used to somersault the instant the eye dipped under. Both have to be gone by the time the
## water has the body.
##
## Timing runs off _physics_process: headless idle frames run ~6x faster than the 60 Hz physics
## tick, so sampling from _process would miss most of the plunge.

const DEEP_MIN := 2.5
const SCAN := 50
const DROP_HEIGHT := 2.0
const LOOK_DOWN_DEG := 35.0
const LOOK_AFTER_M := 3.0
const PITCH_TOLERANCE_DEG := 1.0
# A 2 m drop peaks at about 6.9 m/s, so a plunge that held for fewer ticks than this would not be
# covering the window the player reported.
const MIN_HOLD_TICKS := 3

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var camera: Camera3D
var ticks := 0
var phase := 0
var phase_start := 0
var deep := Vector3.ZERO
var has_deep := false
var looked := false
var saw_plunge := false
var hold_ticks := 0
var plunge_ticks := 0
var swimming_look := false
var swim_while_plunging := false
var swim_clip := ""
var swim_tick := -1
var swim_vy := 0.0
var worst_pitch := 0.0
var pitched_while_plunging := 0.0
var sub_at_squash := 0.0
var failed := false


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 4:
		return false

	if phase == 0:
		if ticks < 20:
			return false
		player = world.get_node_or_null("Player")
		zone = world.get_node_or_null("WaterZone")
		camera = world.get_node_or_null("Player/Head/Camera3D")
		if not player or not zone or not camera:
			_fail("player, WaterZone or Player/Head/Camera3 is missing from the world")
			_finish()
			return true
		_scan()
		if not has_deep:
			_finish()
			return true
		# a low ledge, as if the player walked off one
		player.global_position = Vector3(deep.x, zone.WaterSurfaceY + DROP_HEIGHT, deep.z)
		phase = 1
		phase_start = ticks
		return false

	if phase == 1:
		# look down on the way in, the way a player watching the water would
		if not looked and player.global_position.y < zone.WaterSurfaceY + LOOK_AFTER_M:
			camera.LookPitch = deg_to_rad(-LOOK_DOWN_DEG)
			looked = true
		_sample()
		# stop well after the swim look is due, so the whole splashdown is covered
		if swim_tick >= 0 and ticks > swim_tick + 60:
			_finish()
			return true
		if ticks - phase_start > 500:
			_fail("the plunge never finished")
			_finish()
			return true
		return false

	return false


func _sample() -> void:
	var clip := String(player.AnimationState).strip_edges()
	var looks_like_swim := clip == "Swim Tread" or clip == "Swimming Loop"
	# BodyPitch is a world angle off vertical, so the fall wants it near zero; the swim pose
	# authors a forward pitch, so any large value means the body has left the fall.
	var pitch := absf(rad_to_deg(player.BodyPitch))

	if looks_like_swim:
		swimming_look = true
		if swim_tick < 0:
			swim_tick = ticks
			swim_vy = player.velocity.y
	if player.IsPlunging:
		saw_plunge = true
		plunge_ticks += 1
		if looks_like_swim:
			swim_while_plunging = true
			swim_clip = clip
		pitched_while_plunging = maxf(pitched_while_plunging, pitch)
	else:
		worst_pitch = maxf(worst_pitch, pitch)

	if looks_like_swim and swim_tick == ticks:
		sub_at_squash = player.WadeSubmersion


func _scan() -> void:
	var ss := player.get_world_3d().direct_space_state
	var surface: float = zone.WaterSurfaceY
	player.global_position = Vector3(500, 300, 0)
	var z := -3000
	while z <= 3000 and not has_deep:
		var x := -2000
		while x <= 3000:
			var hy := ground_at(ss, x, z)
			if not is_nan(hy) and surface - hy > DEEP_MIN and variation(ss, x, z, hy) < 0.6:
				deep = Vector3(x, hy, z)
				has_deep = true
				break
			x += SCAN
		z += SCAN
	print("scan deep=", deep, " (", snappedf(zone.WaterSurfaceY - deep.y, 0.01), "m) plunge_speed=",
		snappedf(player.PlungeSpeed, 0.01), " max_swim_vertical=", snappedf(player.MaxSwimVerticalSpeed, 0.01))


func ground_at(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, zone.WaterSurfaceY + 40, z), Vector3(x, zone.WaterSurfaceY - 40, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


func variation(ss: PhysicsDirectSpaceState3D, x: float, z: float, hy: float) -> float:
	var lo := hy
	var hi := hy
	for o in [Vector2(1.5, 0.0), Vector2(-1.5, 0.0), Vector2(0.0, 1.5), Vector2(0.0, -1.5)]:
		var h := ground_at(ss, x + o.x, z + o.y)
		if is_nan(h):
			return INF
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo


func _finish() -> void:
	print("plunge held for ", plunge_ticks, " ticks, swim look from tick ", swim_tick,
		" at vy=", snappedf(swim_vy, 0.01), " m/s, submersion=", snappedf(sub_at_squash, 0.001))
	print("worst pitch while plunging=", snappedf(pitched_while_plunging, 0.01),
		" deg, worst pitch once swimming=", snappedf(worst_pitch, 0.01), " deg")

	if not saw_plunge:
		_fail("the drop never counted as a plunge, so the case is not covered")
	if plunge_ticks < MIN_HOLD_TICKS:
		_fail("the plunge only held for " + str(plunge_ticks) + " ticks -- too short to be a real splashdown")
	if swim_while_plunging:
		_fail("the swim look '" + swim_clip + "' appeared while the body was still falling")
	if not swimming_look:
		_fail("the swim look never appeared, so the handover is not covered")
	elif swim_vy < 0.0 and -swim_vy > player.PlungeSpeed:
		_fail("the swim look took over at " + str(snappedf(-swim_vy, 0.01))
			+ " m/s, faster than PlungeSpeed " + str(snappedf(player.PlungeSpeed, 0.01)))
	if pitched_while_plunging > PITCH_TOLERANCE_DEG:
		_fail("the body pitched to " + str(snappedf(pitched_while_plunging, 0.01))
			+ " deg while it was still falling -- that is the somersault")
	# A deliberate dive tops out at MaxSwimVerticalSpeed, so a plunge threshold at or below it
	# would deny a diving player its own swimming look.
	if player.PlungeSpeed <= player.MaxSwimVerticalSpeed:
		_fail("PlungeSpeed " + str(snappedf(player.PlungeSpeed, 0.01))
			+ " is not above MaxSwimVerticalSpeed " + str(snappedf(player.MaxSwimVerticalSpeed, 0.01))
			+ ", so a deliberate dive would read as a plunge")

	print("TEST PLUNGE HOLD ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)


func _fail(msg: String) -> void:
	failed = true
	printerr("FAIL: ", msg)
