extends SceneTree

## Wade step-up: swim into a submerged ledge and check that the body climbs it and hands over to
## walking, rather than treading against it forever.
##
## The report was that a swimmer approaching land stops at a step below the surface and swims on
## the spot. It is not the wade threshold being wrong: the float parks the feet a fixed depth
## under the waterline, so on any step shallower than that the feet are below its top edge, the
## body cannot climb it, and -- because treading keeps the feet submerged past WadeHandoverDepth --
## the state never reaches wading either. The body has to be lifted over the step.
##
## Both step heights are measured off the body rather than authored, so re-tuning
## WadeStepUpHeight cannot stale the test: the climbable ledge is built a fixed fraction of the
## allowed height and the unclimbable wall just past it, and the treading height each is measured
## from is the float's own equilibrium on that frame.
##
## Input is injected with Input.parse_input_event, which feeds the physical key state the way
## test_wade.gd does. Driving the body kinematically instead would be wrong here: it shoves the
## capsule into the box and the depenetration lifts it onto the top, which fakes a pass.

const SCAN := 100
const DEEP_DEPTH := 4.0
const LEDGE_SIZE := 8.0
const APPROACH := 14.0
const LEDGE_RISE := 0.6   # above the treading feet, and well inside WadeStepUpHeight
const WALL_MARGIN := 0.25 # past it, which is what makes it a wall
const SETTLE_TICKS := 60
const HOLD_TICKS := 420
const FREE_TICKS := 120
const FOOT_OFFSET := 0.889  # capsule bottom below the player origin, see PlayerController._restHeight

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var camera: Camera3D
var ledge: StaticBody3D
var ticks := 0
var phase := 0
var phase_start := 0
var scenario := 0
var deep := Vector3.ZERO
var has_deep := false
var move_key := 0
var dir := Vector3.ZERO
var held := 0
var treading_feet := 0.0
var wall_top := 0.0
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

	# Let the float reach its own equilibrium before anything is measured against it: the step
	# heights are built off the treading height, so they have to be the real one.
	if phase == 1:
		if ticks - phase_start < SETTLE_TICKS:
			return false
		if scenario == 0:
			treading_feet = player.global_position.y - FOOT_OFFSET
			wall_top = treading_feet + player.WadeStepUpHeight + WALL_MARGIN
		rows.clear()
		_build(treading_feet + LEDGE_RISE if scenario == 0 else wall_top)
		phase = 2
		phase_start = ticks
		return false

	if phase == 2:
		var step: int = ticks - phase_start
		if step == 1:
			hold(move_key)
		rows.append(_row(step))
		if step > HOLD_TICKS:
			hold(0)
			phase = 3
			phase_start = ticks
		return false

	if phase == 3:
		var step: int = ticks - phase_start
		rows.append(_row(step))
		if step > FREE_TICKS:
			scenario += 1
			if scenario == 1:
				_ledge_report()
				rows.clear()
				phase = 1
				phase_start = ticks
				return false
			_wall_report()
			print("TEST LEDGE WADE ", "FAILED" if failed else "OK")
			quit(1 if failed else 0)
			return true
		return false

	return false


## A box whose top sits at the given height, APPROACH metres ahead of the start, with open deep
## water in between so the approach is the swim and not a scramble over rocks.
func _build(top: float) -> void:
	if ledge:
		ledge.queue_free()
		ledge = null
	ledge = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LEDGE_SIZE, 6.0, LEDGE_SIZE)
	shape.shape = box
	ledge.add_child(shape)
	world.add_child(ledge)
	ledge.global_position = Vector3(deep.x + dir.x * APPROACH, top - 3.0, deep.z + dir.z * APPROACH)
	print("scenario ", scenario, " top=", snappedf(top, 0.01), " depth=",
		snappedf(zone.WaterSurfaceY - top, 0.01), " above_treading=", snappedf(top - treading_feet, 0.01),
		" step_up=", snappedf(player.WadeStepUpHeight, 0.01))


func _row(step: int) -> Dictionary:
	var p := player.global_position
	return {
		"step": step,
		"y": p.y,
		"feet": p.y - FOOT_OFFSET,
		"dist": Vector2(p.x - ledge.global_position.x, p.z - ledge.global_position.z).length(),
		"sub": player.WadeSubmersion,
		"mode": int(player.Mode),
		"wade": player.IsWading,
		"floor": player.is_on_floor(),
		"under": player.IsUnderwater,
		"vh": Vector2(player.velocity.x, player.velocity.z).length(),
		"clip": String(player.AnimationState).strip_edges(),
	}


func ground_at(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, zone.WaterSurfaceY + 60, z), Vector3(x, zone.WaterSurfaceY - 60, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


## Deep water, with more of it APPROACH metres along one of the four swim axes so the box has a
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
				print("deep=", vsnap(deep), " (", snappedf(surface - hy, 0.01), "m) key=", move_key,
					" ahead=", snappedf(surface - ahead, 0.01), "m")
				return true
	return false


func vsnap(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01))


## The climbable step: the body has to get up on it and walk it. Judged on the run rather than on
## the last frame, because the box is a finite shelf in open water and the honest outcome of
## walking off the far side is swimming again. The handover is allowed to take the frame after
## standing up -- the state samples the floor contact before the body moves, so the first frame
## on the ledge is still resolved from the floor the body was over on the way in.
func _ledge_report() -> void:
	var top: float = treading_feet + LEDGE_RISE
	var best: Dictionary = {}
	var on_it := 0
	for r in rows:
		if bool(r["floor"]) and float(r["feet"]) > top - 0.25 and float(r["dist"]) < LEDGE_SIZE * 0.5:
			on_it += 1
			if int(r["mode"]) == 2 and bool(r["wade"]) and float(r["sub"]) < player.WadeHandoverDepth:
				best = r
	if best.is_empty():
		var last: Dictionary = rows[rows.size() - 1]
		printerr("FAIL: never waded on the ledge (", on_it, " frames standing on it); last clip=\"",
			last["clip"], "\" mode=", last["mode"], " feet=", snappedf(last["feet"], 0.01),
			" wanted=", snappedf(top, 0.01))
		for r in rows:
			if float(r["dist"]) < 6.0:
				print("   step ", r["step"], " dist=", snappedf(r["dist"], 0.01),
					" feet=", snappedf(r["feet"], 0.01), " mode=", r["mode"], " wade=", r["wade"],
					" floor=", r["floor"], " sub=", snappedf(r["sub"], 0.003), " clip=\"", r["clip"], "\"")
		failed = true
		return
	print("climbed at step ", best["step"], " feet=", snappedf(best["feet"], 0.01),
		" mode=", best["mode"], " clip=\"", best["clip"], "\" wade=", best["wade"],
		" floor=", best["floor"], " sub=", snappedf(best["sub"], 0.003),
		" ", on_it, " frames on it")


## The unclimbable step: a wall taller than WadeStepUpHeight must be refused, which is what keeps
## the lift from turning into climbing out of a cliff face.
func _wall_report() -> void:
	var last: Dictionary = rows[rows.size() - 1]
	var on_wall := false
	for r in rows:
		if float(r["feet"]) > wall_top - 0.2:
			on_wall = true
			break
	print("wall run last feet=", snappedf(last["feet"], 0.01), " mode=", last["mode"],
		" clip=\"", last["clip"], "\" wade=", last["wade"])
	if on_wall:
		printerr("FAIL: climbed a wall ", snappedf(wall_top - treading_feet, 0.01),
			" m tall, which is past WadeStepUpHeight ", snappedf(player.WadeStepUpHeight, 0.01))
		failed = true
