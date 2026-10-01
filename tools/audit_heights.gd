extends SceneTree
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var sm: Node = load("res://Scenes/Stickman.tscn").instantiate()
	root.add_child(sm)
	await process_frame
	var skel := sm.get_node("Skeleton3D") as Skeleton3D
	var anim := sm.get_node("Anim") as AnimationPlayer
	var b := {}
	for n in ["Head", "Neck", "Spine2", "LeftShoulder", "LeftHand"]:
		b[n] = skel.find_bone(n)
	print("%-16s %10s %10s %10s   (offsets relative to Head)" % ["clip", "shoulder", "hand", "neck"])
	for cn in ["Idle", "Walk Forward", "Swim Tread", "Swimming Loop", "Swim Forward"]:
		anim.play(cn)
		var sums := {}
		var n := 0
		for i in 20:
			await process_frame
			if i < 2: continue
			for k in b:
				sums[k] = sums.get(k, 0.0) + (skel.global_transform * skel.get_bone_global_pose(b[k])).origin.y
			n += 1
		var head: float = sums["Head"] / float(n)
		print("%-16s %10.3f %10.3f %10.3f" % [cn,
			sums["LeftShoulder"] / float(n) - head,
			sums["LeftHand"] / float(n) - head,
			sums["Neck"] / float(n) - head])
	quit(0)
