extends SceneTree

## Restyle check: samples the leap clips' key poses so the launch vs descent leg heights, the
## arm drive, and the plant foot's push can be read off the generated clips directly.
## Diagnostics only, nothing to assert.

var phase := 0
var anim: AnimationPlayer
var skel: Skeleton3D


func _initialize() -> void:
	var stick = (load("res://Scenes/Stickman.tscn") as PackedScene).instantiate()
	stick.name = "Check"
	root.call_deferred("add_child", stick)
	var astep = (load("res://Scenes/AirStep.tscn") as PackedScene).instantiate()
	astep.name = "AstepCheck"
	root.add_child(astep)
	# The astep scene is a data carrier; point its player at the stickman for sampling.
	(astep as AnimationPlayer).root_node = NodePath("../Check")


func _process(_delta: float) -> bool:
	match phase:
		0:
			if not root.get_node_or_null("Check"):
				return false
			anim = root.get_node("Check/Anim")
			skel = root.get_node("Check/Skeleton3D")
			walk_hands()
			leap_arc("Jump Forward L")
			astep_thrust()
			chain_continuity()
			quit(0)
			return true
	return false


# The recast read hangs on this: each step clip's END pose must be the next step clip's
# START pose, so a recast continues the motion instead of snapping to standing. Compares the
# R-lead clip's end against the L-lead clip's start (the chain alternates the two).
func chain_continuity() -> void:
	var astep: AnimationPlayer = root.get_node("AstepCheck") as AnimationPlayer
	var end_poses := _capture(astep, "Air Step Forward R", 1.0)
	var start_poses := _capture(astep, "Air Step Forward L", 0.0)
	var worst := 0.0
	var worst_bone := ""
	for i in range(skel.get_bone_count()):
		var d: float = (end_poses[i].origin - start_poses[i].origin).length()
		if d > worst:
			worst = d
			worst_bone = skel.get_bone_name(i)
	print("CHAIN: R-lead end vs L-lead start, worst joint gap = %.5f m (%s)" % [worst, worst_bone])


func _capture(player: AnimationPlayer, cname: String, u: float) -> Array:
	var a := player.get_animation(cname)
	reset()
	player.play(cname)
	player.seek(a.length * minf(u, 0.999), true)
	var poses: Array = []
	for i in range(skel.get_bone_count()):
		poses.append(skel.get_bone_global_pose(i))
	player.stop()
	return poses


func reset() -> void:
	for i in range(skel.get_bone_count()):
		var r := skel.get_bone_rest(i)
		skel.set_bone_pose_position(i, r.origin)
		skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(i, r.basis.get_scale())


func leap_arc(cname: String) -> void:
	var a := anim.get_animation(cname)
	var lf := skel.find_bone("LeftFoot")
	var rf := skel.find_bone("RightFoot")
	var lh := skel.find_bone("LeftHand")
	var rh := skel.find_bone("RightHand")
	var pelvis_bone := skel.find_bone("Root")
	reset()
	anim.play(cname)
	print("== ", cname, " len=", snappedf(a.length, 0.01), "  (phase 0 = launch, 1 = descent end)")
	print("phase   pelvisY    leadFootY  plantFootY  leadHandY  trailHandY")
	for s in range(0, 33, 4):
		var u := float(s) / 32.0
		anim.seek(a.length * minf(u, 0.999), true)
		var pelvis: Vector3 = skel.get_bone_global_pose(pelvis_bone).origin
		var lead: Vector3 = skel.get_bone_global_pose(lf).origin
		var plant: Vector3 = skel.get_bone_global_pose(rf).origin
		var lhand: Vector3 = skel.get_bone_global_pose(lh).origin
		var rhand: Vector3 = skel.get_bone_global_pose(rh).origin
		print("%.3f   %8.4f   %8.4f   %8.4f   %8.4f   %8.4f" % [u, pelvis.y, lead.y, plant.y, lhand.y, rhand.y])
	anim.stop()


func walk_hands() -> void:
	var a := anim.get_animation("Walk Forward")
	var lh := skel.find_bone("LeftHand")
	var rh := skel.find_bone("RightHand")
	reset()
	anim.play("Walk Forward")
	print("== Walk Forward (the arm source) hands over the cycle")
	for s in range(0, 33, 4):
		var u := float(s) / 32.0
		anim.seek(a.length * u, true)
		print("phase %.3f   leadHandY %8.4f   trailHandY %8.4f" % [u,
			skel.get_bone_global_pose(lh).origin.y, skel.get_bone_global_pose(rh).origin.y])
	anim.stop()


func astep_thrust() -> void:
	var astep: AnimationPlayer = root.get_node("AstepCheck") as AnimationPlayer
	var a := astep.get_animation("Air Step Forward L")
	var lf := skel.find_bone("LeftFoot")
	var rf := skel.find_bone("RightFoot")
	var lh := skel.find_bone("LeftHand")
	var rh := skel.find_bone("RightHand")
	var pelvis_bone := skel.find_bone("Root")
	reset()
	astep.play("Air Step Forward L")
	print("== Air Step Forward L len=", snappedf(a.length, 0.01), "  (lead = left foot, plant = right)")
	print("phase   pelvisY    leadFootY  plantFootY  leadHandY  trailHandY")
	for s in range(0, 25, 2):
		var u := float(s) / 24.0
		astep.seek(a.length * minf(u, 0.999), true)
		var pelvis: Vector3 = skel.get_bone_global_pose(pelvis_bone).origin
		var lead: Vector3 = skel.get_bone_global_pose(lf).origin
		var plant: Vector3 = skel.get_bone_global_pose(rf).origin
		var lhand: Vector3 = skel.get_bone_global_pose(lh).origin
		var rhand: Vector3 = skel.get_bone_global_pose(rh).origin
		print("%.3f   %8.4f   %8.4f   %8.4f   %8.4f   %8.4f" % [u, pelvis.y, lead.y, plant.y, lhand.y, rhand.y])
	astep.stop()
