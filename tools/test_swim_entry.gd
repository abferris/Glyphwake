extends SceneTree

## Swim entry test: a jump into the water must stay a fall, in look as well as in motion, until
## the body is submerged to the neck.
##
## The WaterZone box spans y 55..105 around a water surface at y 80, so it reaches 25 m *above*
## the water. Being inside the zone therefore only means the body is over the water, not in it:
## EnterWater fired on the way off the ledge and the swim clip used to start while the player was
## still in mid-air, tens of metres above the surface. The swim look now waits on
## PlayerController.AtSwimDepth, which latches at the same FloatEngageDepth that starts the float
## that slows the fall, so the animation and the buoyancy cannot disagree about when the
## character counts as being in the water.
##
## Timing runs off _physics_process: headless idle frames run ~6x faster than the 60 Hz physics
## tick, so sampling from _process would miss most of the fall.

const DEEP_MIN := 2.5
const DROP_HEIGHT := 20.0
const SCAN := 50
const TOLERANCE := 0.02

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var anim: AnimationPlayer
var ticks := 0
var phase := 0
var deep := Vector3.ZERO
var has_deep := false
var engage := 0.0
var first_swim_sub := NAN
var first_swim_tick := -1
var saw_zone_above_water := false
var saw_early := false
var worst_early := 0.0
var early_clip := ""
var clip_after := ""
var sub_after := NAN
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
		anim = player.get_node_or_null("Visual/Anim")
		if not player or not zone or not anim:
			_fail("player, WaterZone or Visual/Anim is missing from the world")
			_finish()
			return true
		engage = player.FloatEngageDepth
		_scan()
		if not has_deep:
			_finish()
			return true
		# drop in from above the top of the zone box, so the whole fall passes through the
		# stretch where the zone says "swimming" but the body is still in open air
		player.global_position = Vector3(deep.x, deep.y + DROP_HEIGHT, deep.z)
		phase = 1
		return false

	if phase == 1:
		if ticks > 600:
			_fail("the drop never finished")
			_finish()
			return true
		_sample()
		# stop once the body has settled into the float well after the clip should have appeared
		if first_swim_tick >= 0 and ticks > first_swim_tick + 90:
			_finish()
			return true
		return false

	return false


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
	print("scan deep=", deep, " (", snappedf(zone.WaterSurfaceY - deep.y, 0.01), "m deep), float engages at sub=",
		snappedf(engage, 0.001))


func _sample() -> void:
	var sub: float = player.WadeSubmersion
	var under: bool = player.IsUnderwater
	var clip := anim.current_animation.strip_edges()
	var swimming_look := clip == "Swim Tread" or clip == "Swimming Loop"

	# the zone overlapping while the feet are still out of the water is the whole bug
	if player.IsSwimming and sub <= 0.0:
		saw_zone_above_water = true

	if swimming_look:
		if first_swim_tick < 0:
			first_swim_tick = ticks
			first_swim_sub = sub
			clip_after = clip
			sub_after = sub
		# the swim look must never appear while the body is above swimming depth
		if not under and sub < engage - TOLERANCE and (not saw_early or sub > worst_early):
			saw_early = true
			worst_early = sub
			early_clip = clip


func ground_at(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -400, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


func variation(ss: PhysicsDirectSpaceState3D, x: float, z: float, hy: float) -> float:
	var lo := hy
	var hi := hy
	for o in [2.0, 4.0, 6.0]:
		lo = minf(lo, ground_at(ss, x + o, z))
		hi = maxf(hi, ground_at(ss, x, z + o))
	return hi - lo


func _finish() -> void:
	print("zone overlapped while out of the water: ", saw_zone_above_water)
	if not saw_zone_above_water:
		_fail("the drop never put the body in the zone above the water, so the case is not covered")
	if first_swim_tick < 0:
		_fail("the swim clip never appeared during the drop")
		print("TEST SWIM ENTRY FAILED")
		quit(1)
		return
	print("first swim clip '", clip_after, "' at submersion ", snappedf(sub_after, 0.001),
		" (float engages at ", snappedf(engage, 0.001), ")")
	if not saw_early:
		print("no swim clip above the swimming depth")
	else:
		_fail("the swim clip '" + early_clip + "' appeared early, at submersion "
			+ str(snappedf(worst_early, 0.001)) + " which is above the float's " + str(snappedf(engage, 0.001)))
	if sub_after < engage - TOLERANCE:
		_fail("the swim clip only appeared at submersion " + str(snappedf(sub_after, 0.001))
			+ ", later than the float engages at " + str(snappedf(engage, 0.001)))
	print("TEST SWIM ENTRY ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)


func _fail(msg: String) -> void:
	failed = true
	printerr("FAIL: ", msg)
