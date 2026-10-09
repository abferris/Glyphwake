extends SceneTree

## Falling through open air over land must fall at full speed, even with input held.
##
## The water zone is a box covering the whole map, so "inside the zone" is true 40 m above the
## island and cannot be read as "in water". Two latches have to agree on that: the mode ternary
## must not fall through to EnteringWater when nothing else matches, and IsPlunging must check
## for water below rather than arming on VerticalVelocity < -PlungeSpeed alone. Either one puts
## the body in SimulateSwim mid-air, where the dive charge -- which only asks whether a key is
## down and the camera is pointing down, never whether there is water nearby -- clamps the descent
## to SwimSpeed after DiveDelay seconds.
##
## Measured on a 45 m drop off the island, holding W with the camera 45 degrees down:
## free fall reached -27.30 m/s, but the same drop was pinned at -3.00 m/s for the entire 13 s,
## never reached the ground, and drifted out over the sea instead of landing on the rock.
##
## Three invariants, all measured off the fall rather than authored, so re-tuning MaxFallSpeed,
## SwimSpeed or PlungeSpeed cannot stale it:
##
##   1. no swim mode is ever entered while over dry land above the waterline
##   2. the descent gets well past both swim-related caps, which are -3 and -4 m/s here
##   3. the body ends up on the island rather than in the water it was supposed to clear

const MODE_NAMES := ["Grounded", "Airborne", "Wading", "EnteringWater", "SurfaceSwimming", "UnderwaterSwimming"]
const SWIM_MODE := 3  # first of EnteringWater / SurfaceSwimming / UnderwaterSwimming

const DROP_HEIGHT := 45.0
const MAX_TICKS := 400
const WARM_TICKS := 8    # is_on_floor() survives the teleport otherwise; see start_drop
const CAMERA_PITCH := -PI * 0.25  # past DiveLookDownDeg, but keeps a horizontal move component

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var camera: Camera3D
var ticks := 0
var phase := 0     # 0 setup, 1 falling, 2 done
var warm := 0
var cliff := Vector3.ZERO
var rows := []
var failed := false
var holding := false


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func press(want: bool) -> void:
	if holding == want:
		return
	holding = want
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = want
	ev.echo = false
	Input.parse_input_event(ev)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 6:
		return false

	if phase == 0:
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		player = world.get_node_or_null("Player")
		zone = world.get_node_or_null("WaterZone")
		camera = player.get_node_or_null("Head/Camera3D")
		if player == null or zone == null:
			printerr("FAIL: player or WaterZone missing")
			quit(1)
			return true
		find_cliff()
		start_drop()
		press(true)
		phase = 1
		ticks = 0
		return false

	if phase == 2:
		press(false)
		report()
		print("TEST OPENAIR FALL ", "FAILED" if failed else "OK")
		quit(1 if failed else 0)
		return true

	if warm > 0:
		warm -= 1
	elif player.is_on_floor() or ticks > MAX_TICKS:
		phase = 2
		return false

	if camera:
		camera.rotation.x = CAMERA_PITCH

	rows.append({
		"tick": ticks,
		"y": player.global_position.y,
		"vy": player.velocity.y,
		"mode": int(player.Mode),
	})
	return false


func start_drop() -> void:
	player.global_position = Vector3(cliff.x, zone.WaterSurfaceY + DROP_HEIGHT, cliff.z)
	player.velocity = Vector3.ZERO
	# Clearing `velocity` does not clear the controller's own _verticalVelocity, so the drop
	# would start at whatever the body was carrying. Jump(0) is the public way to zero it.
	player.Jump(0.0)
	rows.clear()
	warm = WARM_TICKS


func report() -> void:
	if rows.is_empty():
		printerr("FAIL: the body never fell")
		failed = true
		return

	var swim_modes := {}
	var fastest := 0.0
	var braked := 0
	var last_vy := 0.0
	for r in rows:
		fastest = minf(fastest, r["vy"])
		var mode: int = r["mode"]
		if mode >= SWIM_MODE:
			swim_modes[MODE_NAMES[mode]] = int(swim_modes.get(MODE_NAMES[mode], 0)) + 1
		if last_vy < 0.0 and r["vy"] > last_vy + 0.01:
			braked += 1
		last_vy = r["vy"]

	var last: Dictionary = rows[rows.size() - 1]
	var landed: bool = player.is_on_floor()

	print("ticks=", rows.size(), " fastest=", snappedf(fastest, 0.01),
		" braked=", braked, " landed_on_island=", landed,
		" final_y=", snappedf(last["y"], 0.01), " cliff_top=", snappedf(cliff.y, 0.01))

	if not swim_modes.is_empty():
		printerr("FAIL: entered ", swim_modes, " while falling through open air over dry land,",
			" but there is no water below the island")
		failed = true

	# SwimSpeed is 3 and MaxSwimVerticalSpeed is 4 here, so anything past -12 is unambiguously
	# clear of every cap the swim path could impose without pinning the test to MaxFallSpeed.
	if fastest > -12.0:
		printerr("FAIL: descent capped at ", snappedf(fastest, 0.01),
			" m/s; a swim-path fall limit is clamping it in open air")
		failed = true

	if braked > 0:
		printerr("FAIL: the fall was braked on ", braked,
			" ticks in open air, which means something is still decelerating the body")
		failed = true

	# No air control, so the body should come down on the rock it left rather than out at sea.
	if not landed:
		printerr("FAIL: never landed within ", MAX_TICKS, " ticks")
		failed = true
	elif last["y"] < zone.WaterSurfaceY:
		printerr("FAIL: came down at y=", snappedf(last["y"], 0.01),
			" which is below the waterline ", snappedf(zone.WaterSurfaceY, 0.01),
			" -- the island cliff drop ended in the sea")
		failed = true


func ground_at(x: float, z: float) -> float:
	var ss := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, zone.WaterSurfaceY + 60, z), Vector3(x, zone.WaterSurfaceY - 60, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


func find_cliff() -> void:
	var surface: float = zone.WaterSurfaceY
	var z := -2000
	while z <= 2000 and cliff == Vector3.ZERO:
		var x := -2000
		while x <= 2000:
			var hy := ground_at(x, z)
			if not is_nan(hy) and hy > surface + 3.0 and hy < surface + 40.0:
				cliff = Vector3(x, hy, z)
				break
			x += 50
		z += 50
	if cliff == Vector3.ZERO:
		printerr("FAIL: no island ground found above the waterline")
		quit(1)
