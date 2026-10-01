extends SceneTree

var _pb
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _hand := 0

func _init() -> void:
	_run.call_deferred()

func _hand_p() -> Vector3:
	return _skel.get_bone_global_pose(_hand).origin

func _run() -> void:
	var sm: Node = load("res://Scenes/Stickman.tscn").instantiate()
	root.add_child(sm)
	await process_frame
	_anim = sm.get_node("Anim") as AnimationPlayer
	_skel = sm.get_node("Skeleton3D") as Skeleton3D
	_hand = _skel.find_bone("LeftHand")

	var CLIP := "Walk Diagonal Forward Right"
	var L: float = _anim.get_animation(CLIP).length
	var OFF := L * 0.5

	var tree := AnimationTree.new()
	sm.add_child(tree)
	tree.anim_player = tree.get_path_to(_anim)
	var machine := AnimationNodeStateMachine.new()

	# states: plain (no offset, looping) and the variants under test
	machine.add_node("Plain", _mk(CLIP, false, 0.0, true, L), Vector2.ZERO)
	var variants := {
		"A_customLen_off_loop": [true, L, true],
		"B_customLenOff_off_loop": [true, L - OFF, true],
		"C_nocustom_off_loop": [false, 0.0, true],
		"D_customLen_off_noloop": [true, L, false],
	}
	var names: Array = variants.keys()
	for n in names:
		var v: Array = variants[n]
		machine.add_node(n, _mk(CLIP, v[0], OFF, v[2], v[1]), Vector2.ZERO)
	for n in names:
		var t := AnimationNodeStateMachineTransition.new()
		t.xfade_time = 0.0
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.reset = true
		machine.add_transition("Start", n, t)
	var tp := AnimationNodeStateMachineTransition.new()
	tp.xfade_time = 0.0
	tp.reset = true
	machine.add_transition("Start", "Plain", tp)
	tree.tree_root = machine
	tree.active = true
	await process_frame
	_pb = tree.get("parameters/playback")

	# where does the plain clip sit at t=0 and at t=OFF?
	_pb.travel("Plain")
	await process_frame
	_pb.travel("Plain")
	for i in 4: await process_frame
	var poseAt0 := _hand_p()

	print("clip=%s len=%.4f  intended offset=%.4f" % [CLIP, L, OFF])
	print("state                          start_dist_from_clip_t0   still_moving")
	for n in names:
		_pb.travel(n)
		for i in 4: await process_frame
		_pb.travel(n)
		for i in 4: await process_frame
		var start := _hand_p()
		var marks: Array[float] = []
		for seg in 6:
			var lo := _hand_p()
			for i in 30: await process_frame
			marks.append(lo.distance_to(_hand_p()))
		var frozen := marks[marks.size() - 1] < 0.002
		print("  %-28s %6.3f                 %s" % [n, start.distance_to(poseAt0), "NO  *** FROZEN ***" if frozen else "yes"])
		var line := "        travel: "
		for m in marks: line += "%6.3f " % m
		print(line)
	quit(0)

func _mk(clip: String, custom: bool, off: float, loop: bool, tlen: float) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	a.loop_mode = 1 if loop else 0
	if off > 0.0:
		a.start_offset = off
		a.use_custom_timeline = custom
		if custom:
			a.timeline_length = tlen
	bt.add_node("clip", a, Vector2.ZERO)
	bt.add_node("Speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("Speed", 0, "clip")
	bt.connect_node("output", 0, "Speed")
	return bt
