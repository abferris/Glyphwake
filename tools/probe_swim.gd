extends SceneTree

func _initialize() -> void:
	var ps := load("res://Scenes/Stickman.tscn") as PackedScene
	var st := ps.instantiate()
	root.add_child(st)
	await process_frame
	var skel := st.get_node("Skeleton3D") as Skeleton3D
	var anim := st.get_node("Anim") as AnimationPlayer
	var hand := skel.find_bone("LeftHand")
	var ref := skel.find_bone("LeftForeArm")
	var clips := ["Swimming Loop", "Swimming", "Swim Forward", "Idle", "Walk Forward"]
	var scales := [1.0, 1.6, 2.4]
	for c in clips:
		if not anim.has_animation(c):
			print(c, "  MISSING")
			continue
		var base_len: float = anim.get_animation(c).length
		var line: String = c + " len=" + str(snappedf(base_len, 2))
		for s in scales:
			anim.play(c)
			anim.seek(0.0, true)
			anim.speed_scale = s
			var first: Vector3
			var last: Vector3
			var path := 0.0
			var span := 0.0
			var prev: Vector3
			var miny := 1e9
			var maxy := -1e9
			var n := 0
			var t := 0.0
			while t < 1.2:
				await process_frame
				anim.advance(0.016)
				var pose: Transform3D = skel.get_bone_global_pose(hand)
				var p: Vector3 = pose.origin
				var q: Transform3D = skel.get_bone_global_pose(ref)
				if n == 0:
					first = p
					prev = p
				last = p
				path += (p - prev).length()
				prev = p
				miny = minf(miny, q.origin.y)
				maxy = maxf(maxy, q.origin.y)
				n += 1
				t += 0.016
			span = maxy - miny
			line += " | x"+str(s)+": path=" + str(snappedf(path, 2)) + " forearm_span_y=" + str(snappedf(span, 3))
		print(line)
	quit(0)