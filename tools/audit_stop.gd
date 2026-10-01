extends SceneTree
const FLOOR_Y := 0.0
var _pm
var _skel: Skeleton3D
var _last := ""

func _init() -> void: _run.call_deferred()

func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _run() -> void:
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor.add_child(cs)
	floor.position = Vector3(0, FLOOR_Y - 0.5, 0)
	root.add_child(floor)
	_pm = load("res://Scenes/Player.tscn").instantiate()
	_pm.position = Vector3(0, FLOOR_Y + 0.9, 0)
	root.add_child(_pm)
	await process_frame
	_skel = _pm.get_node("Visual/Skeleton3D")
	for i in 30: await process_frame
	_last = _pm.AnimationState
	print("settled state = ", _last)
	print("--- hold W 1.5s")
	_key(KEY_W, true)
	for i in 90: await _poll("holdW"); await process_frame
	print("--- release W, log every state change for 2s")
	_key(KEY_W, false)
	var changes := 0
	for i in 120:
		if await _poll("after"): changes += 1
		await process_frame
	print("--- state changes after release: ", changes)

	# strafe foot analysis on the authored clips
	print()
	print("foot motion per walk clip (does the stance foot cross the other side?):")
	var clipNames := ["Walk Forward", "Walk Strafe Left", "Walk Strafe Right",
		"Walk Diagonal Forward Left", "Walk Diagonal Forward Right"]
	for cn in clipNames:
		_measure_feet(cn)
	quit(0)

func _poll(tag: String) -> bool:
	var s: String = _pm.AnimationState
	if s != _last:
		print("   %-6s f%-4d speed=%.3f  %s -> %s" % [tag, Engine.get_physics_frames(), _pm.velocity.length(), _last, s])
		_last = s
		return true
	return false

func _measure_feet(cn: String) -> void:
	var pb = _pm.get_node("AnimTree").get("parameters/playback")
	pb.travel(cn)
	for i in 6: await process_frame
	pb.travel(cn)
	for i in 6: await process_frame
	var lf := _skel.find_bone("LeftFoot")
	var rf := _skel.find_bone("RightFoot")
	var minSep := 1e9
	var maxSep := -1e9
	var lz := 0.0
	var rz := 0.0
	var l0: Vector3
	var r0: Vector3
	for i in 3:
		l0 = _skel.get_bone_global_pose(lf).origin
		r0 = _skel.get_bone_global_pose(rf).origin
		break
	var n := 0
	for i in 45:
		await process_frame
		var l: Vector3 = _skel.get_bone_global_pose(lf).origin
		var r: Vector3 = _skel.get_bone_global_pose(rf).origin
		if i == 0:
			l0 = l; r0 = r
		lz += absf(l.z - l0.z); rz += absf(r.z - r0.z)
		var sep: float = l.x - r.x
		minSep = minf(minSep, sep)
		maxSep = maxf(maxSep, sep)
		n += 1
	lz /= float(n); rz /= float(n)
	print("  %-30s L.x-R.x range [%6.3f .. %6.3f]  %s   |dZ| L=%.3f R=%.3f" % [cn, minSep, maxSep,
		"CROSSES" if minSep < 0.0 or maxSep < 0.0 else "no cross", lz, rz])
