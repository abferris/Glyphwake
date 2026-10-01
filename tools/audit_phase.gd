extends SceneTree
var _pb
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _hand := 0
func _init() -> void: _run.call_deferred()
func _hp() -> Vector3: return _skel.get_bone_global_pose(_hand).origin

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
	machine.add_node("Plain", _mk(CLIP, 0.0, false, L), Vector2.ZERO)
	machine.add_node("OffA", _mk(CLIP, OFF, true, L), Vector2.ZERO)
	machine.add_node("OffC", _mk(CLIP, OFF, false, 0.0), Vector2.ZERO)
	for n in ["Plain", "OffA", "OffC"]:
		var t := AnimationNodeStateMachineTransition.new()
		t.xfade_time = 0.0; t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE; t.reset = true
		machine.add_transition("Start", n, t)
	tree.tree_root = machine
	tree.active = true
	await process_frame
	_pb = tree.get("parameters/playback")

	# sample one full clip cycle of hand position for each state
	var seqs := {}
	for n in ["Plain", "OffA", "OffC"]:
		_pb.travel(n); await process_frame
		_pb.travel(n); await process_frame
		var pts: Array[Vector3] = []
		var t0: float = _pb.get_current_play_position()
		while _pb.get_current_play_position() - t0 < L and pts.size() < 40:
			await process_frame
			pts.append(_hp())
		seqs[n] = pts
	var plain: Array = seqs["Plain"]
	print("clip len=%.4f, offset=%.4f, %d samples per cycle" % [L, OFF, plain.size()])
	# where does each offset state START, in plain's timeline?
	for n in ["OffA", "OffC"]:
		var s: Array = seqs[n]
		var start: Vector3 = s[0]
		var best := 0
		var bestd := 1e9
		for i in plain.size():
			var d: float = start.distance_to(plain[i])
			if d < bestd: bestd = d; best = i
		var frac := float(best) / float(plain.size())
		print("  %-6s starts at plain's %.2f of the cycle (want ~0.50)  nearest-dist=%.3f" % [n, frac, bestd])
	quit(0)

func _mk(clip: String, off: float, custom: bool, tlen: float) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	a.loop_mode = 1
	if off > 0.0:
		a.start_offset = off
		a.use_custom_timeline = custom
		if custom: a.timeline_length = tlen
	bt.add_node("clip", a, Vector2.ZERO)
	bt.add_node("Speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("Speed", 0, "clip")
	bt.connect_node("output", 0, "Speed")
	return bt
