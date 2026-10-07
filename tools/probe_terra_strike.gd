extends SceneTree

## Terra Strike punch probe: samples the synthesized clip's right-hand travel so the strike
## window and the damage dummy's placement can be read off the clip directly.
## Diagnostics only, nothing to assert.

var phase := 0
var anim: AnimationPlayer
var skel: Skeleton3D


func _initialize() -> void:
	var stick = (load("res://Scenes/Stickman.tscn") as PackedScene).instantiate()
	stick.name = "Check"
	root.call_deferred("add_child", stick)
	var strike = (load("res://Scenes/TerraStrike.tscn") as PackedScene).instantiate()
	strike.name = "StrikeCheck"
	root.add_child(strike)
	(strike as AnimationPlayer).root_node = NodePath("../Check")


func _process(_delta: float) -> bool:
	match phase:
		0:
			if not root.get_node_or_null("Check"):
				return false
			anim = root.get_node("StrikeCheck")
			skel = root.get_node("Check/Skeleton3D")
			reach()
			quit(0)
			return true
	return false


func reach() -> void:
	var a := anim.get_animation("Terra Strike")
	var rh := skel.find_bone("RightHand")
	var rs := skel.find_bone("RightShoulder")
	var root_bone := skel.find_bone("Root")
	reset()
	anim.play("Terra Strike")
	print("== Terra Strike len=", snappedf(a.length, 0.01), " tracks=", a.get_track_count())
	print("phase   rHandX    rHandY    rHandZ    |rHand|   rShoulderY  rootY   (skeleton space)")
	for s in range(0, 26, 2):
		var u := float(s) / 24.0
		anim.seek(a.length * minf(u, 0.999), true)
		var hand: Vector3 = skel.get_bone_global_pose(rh).origin
		var sh: Vector3 = skel.get_bone_global_pose(rs).origin
		var rt: Vector3 = skel.get_bone_global_pose(root_bone).origin
		print("%.3f   %8.4f   %8.4f   %8.4f   %8.4f   %8.4f   %8.4f" % [u, hand.x, hand.y, hand.z,
			hand.length(), sh.y, rt.y])
	anim.stop()


func reset() -> void:
	for i in range(skel.get_bone_count()):
		var r := skel.get_bone_rest(i)
		skel.set_bone_pose_position(i, r.origin)
		skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(i, r.basis.get_scale())
