extends SceneTree

## Walk-stop test: releasing the move keys while walking must not drop to the bare gait clip.
##
## When the keys let go mid-stride the input resolves to no direction while the body is still
## moving, which used to select the base Walk/Diagonal clip -- a different pose -- for the rest
## of the deceleration before Idle took over. That read as a twitch twice: once onto the bare
## clip and once onto Idle, instead of finishing the step. The character must keep the gait it
## is already playing until it is slow enough for Idle.
##
## Input is injected with Input.parse_input_event, which feeds the physical key state the same
## way a real key does, so the same ReadMoveInput path the game uses is exercised. The floor is
## a flat box, so the walk is deterministic and no terrain is needed.

const SETTLE_TICKS := 30
const WALK_BOUND := 150
const COAST_TICKS := 120
const IDLE_SPEED := 0.2

var player: CharacterBody3D
var ticks := 0
var scenario := 0
var phase := 0
var phase_start := 0
var pressed_keys := {}
var failed := false


func _initialize() -> void:
	var ps := load("res://Scenes/Player.tscn") as PackedScene
	if ps == null:
		push_error("Player.tscn missing")
		quit(1)
		return

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)

	player = ps.instantiate()
	root.call_deferred("add_child", player)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 4:
		return false

	if scenario == 0:
		if ticks < SETTLE_TICKS:
			return false
		if not player.is_on_floor():
			printerr("FAIL: the player never settled on the floor")
			quit(1)
			return true
		scenario = 1
		_key(KEY_W, true)
		return false

	var elapsed := ticks - phase_start

	if scenario == 1:
		if phase == 0:
			# press and hold until the walk state is on
			if elapsed > WALK_BOUND:
				_fail("walk never started, state=%s" % player.AnimationState)
				_finish()
				return true
			if _state() == "Walk Forward":
				phase = 1
				phase_start = ticks
			return false
		if phase == 1:
			# a few ticks into the stride, let go
			if elapsed >= 10:
				_release_all()
				phase = 2
				phase_start = ticks
				_coast = []
			return false
		if phase == 2:
			_coast.append(_state())
			if elapsed >= COAST_TICKS:
				_check_coast("Walk Forward", "Walk")
				scenario = 2
				phase = 0
				phase_start = ticks
			return false

	if scenario == 2:
		if phase == 0:
			if elapsed > WALK_BOUND:
				_fail("walk never started, state=%s" % player.AnimationState)
				_finish()
				return true
			if _state() == "Walk Diagonal Forward Right":
				phase = 1
				phase_start = ticks
			else:
				_key(KEY_W, true)
				_key(KEY_D, true)
			return false
		if phase == 1:
			if elapsed >= 10:
				_release_all()
				phase = 2
				phase_start = ticks
				_coast = []
			return false
		if phase == 2:
			_coast.append(_state())
			if elapsed >= COAST_TICKS:
				_check_coast("Walk Diagonal Forward Right", "Walk")
				_finish()
				return true

	return false


var _coast := []


func _state() -> String:
	return String(player.AnimationState).strip_edges()


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	pressed_keys[code] = down
	Input.parse_input_event(ev)


func _release_all() -> void:
	for code in pressed_keys.keys():
		if pressed_keys[code]:
			_key(code, false)
	pressed_keys.clear()


func _check_coast(walked: String, bare: String) -> void:
	var first: String = _coast[0]
	var last: String = _coast[_coast.size() - 1]
	var transitions := []
	var prev := ""
	for s in _coast:
		if s != prev:
			transitions.append(s)
			prev = s
	print(walked, " coast: ", " -> ".join(transitions), " (", _coast.size(), " samples)")
	if bare in transitions:
		printerr("FAIL: stopping dropped to the bare ", bare, " clip -- twitch")
		failed = true
	if first != walked:
		printerr("FAIL: coast did not start on ", walked, ", got ", first)
		failed = true
	if last != "Idle":
		printerr("FAIL: coast did not settle on Idle, got ", last)
		failed = true


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	failed = true


func _finish() -> void:
	print("TEST WALKSTOP ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
