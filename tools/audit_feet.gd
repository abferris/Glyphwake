extends SceneTree
var _skel: Skeleton3D
var _pb
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var sm: Node = load("res://Scenes/Stickman.tscn").instantiate()
	root.add_child(sm)
	await process_frame
	_skel = sm.get_node("Skeleton3D")
	_pb = sm.get_node("Anim")
	# drive the raw AnimationPlayer, no tree, so nothing fights us
	for cn in ["Walk Forward", "Walk Strafe Left", "Walk Strafe Right", "Run Strafe Left", "Run Strafe Right"]:
		_pb.play(cn)
		await process_frame
		var lf := _skel.find_bone("LeftFoot")
		var rf := _skel.find_bone("RightFoot")
		var l0: Vector3
		var r0: Vector3
		var minSep := 1e9
		var maxSep := -1e9
		var lz := 0.0
		var rz := 0.0
		var n := 0
		for i in 40:
			await process_frame
			var l: Vector3 = _skel.get_bone_global_pose(lf).origin
			var r: Vector3 = _skel.get_bone_global_pose(rf).origin
			if i == 0: l0 = l; r0 = r
			lz += absf(l.z - l0.z); rz += absf(r.z - r0.z)
			var sep: float = l.x - r.x
			minSep = minf(minSep, sep); maxSep = maxf(maxSep, sep)
			n += 1
		lz /= float(n); rz /= float(n)
		print("  %-20s L.x-R.x in [%6.3f .. %6.3f] %-9s |dZ| L=%.3f R=%.3f" % [cn, minSep, maxSep,
			"CROSSED" if minSep < 0.0 else "no cross", lz, rz])
	quit(0)
