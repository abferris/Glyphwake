extends SceneTree

## Plunge test: a jump into the water must stay a fall until the player is mostly submerged.
##
## A: dropped over deep water from height -- the fall speed must keep building all the way
##    through the waterline, and only the float (at FloatEngageDepth of submersion, i.e. the
##    treading depth) may arrest it. The old code clamped the fall speed in EnterWater and ran
##    the float spring from the instant the capsule touched the zone, which stopped the drop at
##    the waterline.
## B: dropped onto a shallow bottom -- the feet must land and hand over to wading, with no
##    sinking through the floor and no bobbing up to the surface.
##
## Timing runs off the _physics_process virtual: headless idle frames run ~6x faster than the
## 60 Hz physics tick, so sampling from _process would miss most of the plunge.

const DEEP_MIN := 2.5
const WADE_DEPTH := 1.1
const DROP_HEIGHT := 20.0
const SETTLE_TICKS := 30
const FOOT_OFFSET := 0.889  # capsule bottom below the player origin, see PlayerController._restHeight

var world: Node3D
var player: CharacterBody3D
var terrain: Terrain3D
var camera: Camera3D
var zone: Area3D
var skeleton: Skeleton3D
var head_bone := -1
var ticks := 0
var scenario := 0
var phase_start := 0
var deep := Vector3.ZERO
var wade_spot := Vector3.ZERO
var has_deep := false
var has_wade := false
var samples := []
var settled := {}
var failed := false


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 4:
		return false

	if scenario == 0:
		if ticks < 20:
			return false
		terrain = world.get_node_or_null("Terrain3D")
		player = world.get_node_or_null("Player")
		camera = world.get_node_or_null("Player/Head/Camera3D")
		zone = world.get_node_or_null("WaterZone")
		skeleton = player.get_node_or_null("Visual/Skeleton3D")
		if skeleton:
			head_bone = skeleton.find_bone("Head")
		terrain.set_camera(camera)
		terrain.collision_mode = 3
		scan()
		# settle on the bottom first so the controller starts the drop from a clean state
		player.global_position = wade_spot + Vector3.UP * 0.889
		scenario = 1
		phase_start = ticks
		return false

	var elapsed := ticks - phase_start

	if scenario == 1:
		if elapsed < SETTLE_TICKS:
			return false
		samples.clear()
		player.global_position = Vector3(deep.x, zone.WaterSurfaceY + DROP_HEIGHT, deep.z)
		scenario = 2
		phase_start = ticks
		return false

	if scenario == 2:
		# the deep spot has no floor within reach, so this only ends when the float settles
		samples.append({
			"sub": player.WadeSubmersion,
			"vy": player.velocity.y,
			"y": player.global_position.y,
			"wade": player.IsWading,
			"under": player.IsUnderwater,
		})
		if elapsed > 400:
			# snapshot before moving on: the next scenario teleports the player to the shallows
			settled = {
				"y": player.global_position.y,
				"head": head_y(),
				"eye": camera.global_position.y,
				"wade": player.IsWading,
				"under": player.IsUnderwater,
				"floor": player.is_on_floor(),
			}
			scenario = 3
			phase_start = ticks
			player.global_position = wade_spot + Vector3.UP * (0.889 + 1.5)
		return false

	if scenario == 3:
		if elapsed > 240:
			report_plunge()
			report_shallow()
			print("TEST PLUNGE ", "FAILED" if failed else "OK")
			quit(1 if failed else 0)
			return true
	return false


func ground_at(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, zone.WaterSurfaceY + 40, z), Vector3(x, zone.WaterSurfaceY - 40, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


func variation(ss: PhysicsDirectSpaceState3D, x: float, z: float, hy: float) -> float:
	var worst := 0.0
	for o in [Vector2(1.5, 0.0), Vector2(-1.5, 0.0), Vector2(0.0, 1.5), Vector2(0.0, -1.5)]:
		var h := ground_at(ss, x + o.x, z + o.y)
		if is_nan(h):
			return INF
		worst = maxf(worst, absf(h - hy))
	return worst


func scan() -> void:
	var ss := player.get_world_3d().direct_space_state
	var surface: float = zone.WaterSurfaceY
	player.global_position = Vector3(500, 300, 0)
	var z := -3000
	while z <= 3000:
		var x := -2000
		while x <= 3000:
			var hy := ground_at(ss, x, z)
			if not is_nan(hy) and variation(ss, x, z, hy) < 0.6:
				if not has_deep and surface - hy > DEEP_MIN:
					deep = Vector3(x, hy, z)
					has_deep = true
				elif not has_wade and absf(surface - hy - WADE_DEPTH) < 0.1:
					wade_spot = Vector3(x, hy, z)
					has_wade = true
			x += 50
		z += 50
	print("scan deep=", deep, " (", snappedf(zone.WaterSurfaceY - deep.y, 0.01), "m) wade=",
		wade_spot, " (", snappedf(zone.WaterSurfaceY - wade_spot.y, 0.01), "m)")
	if not has_deep or not has_wade:
		printerr("FAIL: scan found no deep/wade spots")
		failed = true


func head_y() -> float:
	if skeleton and head_bone >= 0:
		return (skeleton.global_transform * skeleton.get_bone_global_pose(head_bone)).origin.y
	return camera.global_position.y


## The fall has to survive the waterline intact and only give way once the body is mostly under.
func report_plunge() -> void:
	var engage: float = player.FloatEngageDepth
	# the free-fall speed carried into the water: the fastest the drop ever got while the feet
	# were still above the surface
	var entry := 0.0
	var worst_ratio := 99.0
	var cut_sub := -1.0
	var cut_feet := 0.0

	for s in samples:
		var vy: float = s["vy"]
		var sub: float = s["sub"]
		var feet: float = zone.WaterSurfaceY - s["y"] + FOOT_OFFSET
		if feet <= 0.0 and vy < 0.0:
			entry = maxf(entry, -vy)
		if entry > 0.0 and sub > 0.0 and sub < engage and vy < 0.0:
			worst_ratio = minf(worst_ratio, (-vy) / entry)
		if cut_sub < 0.0 and feet > 0.0 and vy < 0.0 and -vy < 0.85 * entry:
			cut_sub = sub
			cut_feet = feet

	print("plunge entry_speed=", snappedf(entry, 0.01), " engage=", snappedf(engage, 0.001),
		" min_ratio_while_disengaged=", snappedf(worst_ratio, 0.001),
		" cut at submersion=", snappedf(cut_sub, 0.001), " feet_depth=", snappedf(cut_feet, 0.01),
		" | settled y=", snappedf(settled["y"], 0.001), " head=", snappedf(settled["head"], 0.001),
		" eye=", snappedf(settled["eye"], 0.001), " water=", snappedf(zone.WaterSurfaceY, 0.001),
		" floor=", settled["floor"], " wade=", settled["wade"], " under=", settled["under"])
	if entry < 10.0:
		printerr("FAIL: the drop only reached ", snappedf(entry, 0.01), " m/s before the waterline -- test setup is wrong")
		failed = true
	if worst_ratio < 0.85:
		printerr("FAIL: the plunge lost ", snappedf((1.0 - worst_ratio) * 100.0, 0.1),
			"% of its speed while only partly submerged -- the float is engaging too early")
		failed = true
	if cut_sub < 0.0:
		printerr("FAIL: the fall was never slowed in the water at all")
		failed = true
	elif cut_sub < engage - 0.02:
		printerr("FAIL: the fall was cut at submersion ", snappedf(cut_sub, 0.001),
			", before FloatEngageDepth ", snappedf(engage, 0.001),
			" -- it should keep falling until mostly submerged")
		failed = true
	# the float targets SurfaceHeadHeight (0) and the stroke bobs the head a few mm either side
	# of the waterline, so allow that much before calling it submerged
	if settled["head"] < zone.WaterSurfaceY - 0.02:
		printerr("FAIL: settled with the head under the water (", settled["head"], " < ", zone.WaterSurfaceY - 0.02, ")")
		failed = true
	if settled["eye"] < zone.WaterSurfaceY:
		printerr("FAIL: settled with the eye under the water")
		failed = true
	if settled["wade"] or settled["under"]:
		printerr("FAIL: expected to float at the surface, wade=", settled["wade"], " under=", settled["under"])
		failed = true


## Landing on a shallow bottom has to hand over to wading, not sink or bob.
func report_shallow() -> void:
	var depth: float = zone.WaterSurfaceY - wade_spot.y
	var stand: float = wade_spot.y + 0.889
	print("shallow depth=", snappedf(depth, 0.01), " body_y=", snappedf(player.global_position.y, 0.001),
		" expected=", snappedf(stand, 0.001), " floor=", player.is_on_floor(), " wade=", player.IsWading,
		" under=", player.IsUnderwater, " sub=", snappedf(player.WadeSubmersion, 0.001))
	if not player.is_on_floor():
		printerr("FAIL: did not land on the shallow bottom")
		failed = true
	if not player.IsWading or player.IsUnderwater:
		printerr("FAIL: landing on the bottom should wade, wade=", player.IsWading, " under=", player.IsUnderwater)
		failed = true
	if absf(player.global_position.y - stand) > 0.2:
		printerr("FAIL: settled ", snappedf(player.global_position.y - stand, 0.001),
			"m off the bottom -- sank through or floated up")
		failed = true
