extends SceneTree

## Swimming into a bank too steep to walk up must leave the body treading at the surface, not
## sinking under it.
##
## The shallow-floor settle added for the submerged ledge (see test_ledge_wade.gd) disengages the
## surface float wherever the floor under the body is inside WadeDepth of the surface, on the
## assumption that the body can get onto that floor. Against a slope it cannot climb that
## assumption is false: the foot of the bank is shallow, the bank itself is not walkable, so the
## float gets out of the way and the body slides down the slope into water it should be treading
## on top of.
##
## Two scenarios straddle the slope limits: one steeper than the body can stand on, which has to
## refuse and keep floating, and one inside the step-up budget, which has to still climb, or the
## ledge fix has quietly been broken. Both limits are read off the player rather than written here.

const SCAN := 100
const DEEP_DEPTH := 4.0
const APPROACH := 14.0
const RAMP_RUN := 14.0      # horizontal metres of slope
const RAMP_WIDTH := 24.0
const RAMP_THICK := 1.5
## How far below the body's own treading feet the foot of the ramp starts, so the slope runs out
## from under the swimmer rather than materialising inside the capsule. Measured off the body
## instead of authored as a depth, which keeps the water at the foot of it inside WadeDepth --
## shallow enough for the settle to want to engage -- at whatever float depth the tuning settles
## on, rather than only at the depth it happens to have today.
const RAMP_CLEARANCE := 0.3
const SETTLE_TICKS := 60
const HOLD_TICKS := 420
const FREE_TICKS := 120
const FOOT_OFFSET := 0.889  # capsule bottom below the player origin, see PlayerController._restHeight

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var camera: Camera3D
var ramp: StaticBody3D
var ticks := 0
var phase := 0
var phase_start := 0
var scenario := 0
var deep := Vector3.ZERO
var move_key := 0
var dir := Vector3.ZERO
var held := 0
var treading_feet := 0.0
var ramp_base := Vector3.ZERO
var rows := []
var failed := false


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	ev.echo = false
	Input.parse_input_event(ev)


func hold(code: int) -> void:
	if held == code:
		return
	if held != 0:
		_key(held, false)
	held = code
	if code != 0:
		_key(code, true)


## Which movement key swims toward a world direction. Swim steers off the camera, and the
## camera's yaw is private and rewritten from the body every idle frame, so a tool cannot aim the
## view; the key that reads as "that way" from the spawn yaw can.
func key_for(want: Vector3) -> int:
	var local := camera.global_transform.basis.inverse() * want
	if absf(local.z) >= absf(local.x):
		return KEY_W if local.z < 0.0 else KEY_S
	return KEY_D if local.x > 0.0 else KEY_A


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
		if not _scan():
			printerr("FAIL: no deep water to swim in")
			quit(1)
			return true
		player.global_position = Vector3(deep.x, zone.WaterSurfaceY + 0.2, deep.z)
		phase = 1
		phase_start = ticks
		return false

	# Let the float reach its own equilibrium first: the climbable test is judged against the
	# treading height, so it has to be the real one.
	if phase == 1:
		if ticks - phase_start < SETTLE_TICKS:
			return false
		treading_feet = player.global_position.y - FOOT_OFFSET
		rows.clear()
		_build(_scenario_degrees(scenario))
		phase = 2
		phase_start = ticks
		return false

	if phase == 2:
		var step: int = ticks - phase_start
		if step == 1:
			_profile()
			hold(move_key)
		rows.append(_row(step))
		if step > HOLD_TICKS:
			hold(0)
			phase = 3
			phase_start = ticks
		return false

	# The tail after the key is released is run but not recorded: the question is what the body
	# does while it is being swum at the bank, and where it drifts to once it is let go says
	# nothing about that. Recording it also renumbers the steps, which collides with the hold.
	if phase == 3:
		var step: int = ticks - phase_start
		if step > FREE_TICKS:
			if scenario == 0:
				_report(0)
				scenario = 1
				rows.clear()
				phase = 1
				phase_start = ticks
				return false
			_report(1)
			print("TEST SWIM SLOPE ", "FAILED" if failed else "OK")
			quit(1 if failed else 0)
			return true
		return false

	return false


## Two slopes that are too steep to be stood on, derived rather than authored, because both limits
## move with tuning: the steep one past SlopeMaxAngleDeg, which is where the ground stops being a
## floor at all, and the climbable one inside the step-up budget -- the rise over WadeStepUpProbe,
## which is what the lift actually samples. Stated in degrees only because that is how a slope is
## talked about.
func _scenario_degrees(which: int) -> float:
	if which == 0:
		return player.SlopeMaxAngleDeg + 2.0
	return rad_to_deg(atan(player.WadeStepUpHeight / player.WadeStepUpProbe)) - 4.0


## A bank rising out of the water. The top face passes through the foot of the ramp at
## RAMP_BASE_DEPTH under the surface and climbs from there, so the water at the foot is shallow
## enough for the settle to engage while the face itself is out of reach.
func _build(deg: float) -> void:
	if ramp:
		ramp.queue_free()
		ramp = null
	var a := deg_to_rad(deg)
	var axis := Vector3.UP.cross(dir).normalized()
	var normal := Vector3.UP.rotated(axis, -a)
	var slope_len := RAMP_RUN / cos(a)

	# The top face is centred on the body's start point, RAMP_CLEARANCE under the tread feet, so
	# the body is standing on the slope from the first tick. Starting it short of the near edge
	# instead leaves it balanced on the edge itself, hanging over the open seabed with nothing
	# shallow underneath it -- which reads as a pass here without ever engaging the settle.
	var base := Vector3(deep.x, treading_feet - RAMP_CLEARANCE, deep.z)
	var top_mid := base

	ramp = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RAMP_WIDTH, RAMP_THICK, slope_len)
	shape.shape = box
	ramp.add_child(shape)
	world.add_child(ramp)
	ramp.global_transform = Transform3D(Basis(axis, -a), top_mid - normal * (RAMP_THICK * 0.5))

	print("scenario ", scenario, " slope=", snappedf(deg, 0.01), "deg rise over 1m=",
		snappedf(tan(a), 0.01), " step_up=", snappedf(player.WadeStepUpHeight, 0.01))
	ramp_base = base


## The profile is measured, not assumed: the rise the lift samples over WadeStepUpProbe is the
## whole point of the test, so it is read back off the collision that was actually built. A tick
## later, because a collision shape added this frame is not in the space yet and the ray would
## read the seabed straight through it.
func _profile() -> void:
	var ss := player.get_world_3d().direct_space_state
	for t in [0, 2, 4, 6, 8, 10, 12, 14]:
		var at := ramp_base + dir * float(t)
		var hy := ground_at(ss, at.x, at.z)
		if not is_nan(hy):
			print("   ", t, "m along: ground=", snappedf(hy, 0.01),
				" depth=", snappedf(zone.WaterSurfaceY - hy, 0.01))


func _row(step: int) -> Dictionary:
	var p := player.global_position
	return {
		"step": step,
		"y": p.y,
		"x": p.x,
		"z": p.z,
		"feet": p.y - FOOT_OFFSET,
		"sub": player.WadeSubmersion,
		"mode": int(player.Mode),
		"wade": player.IsWading,
		"floor": player.is_on_floor(),
		"under": player.IsUnderwater,
		"shallow": player.IsOverShallowFloor,
		"gy": player.GroundY,
		"clip": String(player.AnimationState).strip_edges(),
	}


func ground_at(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, zone.WaterSurfaceY + 60, z), Vector3(x, zone.WaterSurfaceY - 60, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


## Deep water, with more of it APPROACH metres along one of the four swim axes so the ramp has a
## clear run at it.
func _scan() -> bool:
	var ss := player.get_world_3d().direct_space_state
	var surface: float = zone.WaterSurfaceY
	player.global_position = Vector3(500, 300, 0)
	for z in range(-2000, 2000, SCAN):
		for x in range(-2000, 2000, SCAN):
			var hy := ground_at(ss, x, z)
			if is_nan(hy) or surface - hy <= DEEP_DEPTH:
				continue
			for d in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				var at := Vector3(x + d.x * APPROACH, hy, z + d.z * APPROACH)
				var ahead := ground_at(ss, at.x, at.z)
				if is_nan(ahead) or surface - ahead <= DEEP_DEPTH:
					continue
				deep = Vector3(x, hy, z)
				dir = d
				move_key = key_for(d)
				print("deep=", deep, " (", snappedf(surface - hy, 0.01), "m) key=", move_key,
					" ahead=", snappedf(surface - ahead, 0.01), "m")
				return true
	return false

## Too steep: the body must stay on the float. The float's whole job is to hold a swimmer at the
## surface, so what matters is not whether the body got out -- it must not -- but how low it sat.
## Before the settle was gated on reachable floor this sank a half metre, out of the treading pose
## and into the swimming loop, held down by a handover to shallow floor it had no way to take.
## Sagging past a quarter metre is a fail, and so is a single frame of IsUnderwater.
func _report(which: int) -> void:
	var lowest := INF
	var lowest_at := -1
	var highest := -INF
	var under := 0
	var waded := 0
	var clips := {}
	for r in rows:
		var feet := float(r["feet"])
		if feet < lowest:
			lowest = feet
			lowest_at = int(r["step"])
		highest = maxf(highest, feet)
		if bool(r["under"]):
			under += 1
		if bool(r["wade"]) and bool(r["floor"]):
			waded += 1
		clips[r["clip"]] = int(clips.get(r["clip"], 0)) + 1

	if which == 1:
		print("climbable: highest feet=", snappedf(highest, 0.01),
			" tread=", snappedf(treading_feet, 0.01), " waded=", waded, " clips=", clips)
		if waded == 0:
			printerr("FAIL: never stood on a slope of ", snappedf(_scenario_degrees(1), 0.01),
				" deg, which is inside the step-up budget")
			failed = true
		return

	print("steep: lowest feet=", snappedf(lowest, 0.01), " at step ", lowest_at,
		" tread=", snappedf(treading_feet, 0.01), " underwater=", under,
		" waded=", waded, " clips=", clips)
	if under > 0:
		printerr("FAIL: submerged for ", under, " frames against a bank too steep to climb")
		failed = true
	if lowest < treading_feet - 0.25:
		printerr("FAIL: sank to ", snappedf(lowest, 0.01), " against a tread height of ",
			snappedf(treading_feet, 0.01), " -- ", snappedf(treading_feet - lowest, 0.01),
			" m under the surface float, on a bank it cannot climb")
		failed = true
	if waded > 0:
		printerr("FAIL: waded on a slope of ", snappedf(_scenario_degrees(0), 0.01),
			" deg, which is past the step-up budget")
		failed = true
	if failed:
		for r in rows:
			var step := int(r["step"])
			if step >= maxi(0, lowest_at - 5) and step <= lowest_at + 5:
				print("   step ", step, " feet=", snappedf(r["feet"], 0.01),
					" gy=", snappedf(r["gy"], 0.01), " shallow=", r["shallow"],
					" floor=", r["floor"], " under=", r["under"], " clip=\"", r["clip"], "\"")
