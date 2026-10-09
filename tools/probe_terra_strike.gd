extends SceneTree

## Terra Strike punch probe: samples the synthesized clips' hand travel so the strike window
## and the damage dummy's placement can be read off the clip directly. Prints the punching
## (right) hand and shoulder plus the guard (left) hand in world space (the root's diag(-1,
## 1, -1) maps skeleton to world: negate x and z, drop y by 0.9), marks the payload's hit
## window (0.4-0.75 of duration), and spot-checks that the mirrored "Terra Strike L" is the
## x-reflection of the right clip. Diagnostics only, nothing to assert.

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
			reach("Terra Strike")
			check_mirror()
			quit(0)
			return true
	return false


func reach(clip_name: String) -> void:
	var a := anim.get_animation(clip_name)
	var lh := skel.find_bone("LeftHand")
	var rh := skel.find_bone("RightHand")
	var rs := skel.find_bone("RightShoulder")
	var rf := skel.find_bone("RightForeArm")
	var lf := skel.find_bone("LeftForeArm")
	reset()
	anim.play(clip_name)
	print("== ", clip_name, " len=", snappedf(a.length, 0.01), " tracks=", a.get_track_count())
	print("  p    |      R hand world     |   R shoulder world    |   L hand world     | ahead     R elbow   L elbow")
	print("      x      y      z       |      x      y      z       |      x      y      z   | z")
	for i in range(21):
		var u := float(i) / 20.0
		anim.seek(a.length * minf(u, 0.999), true)
		var rw := _world(rh)
		var rsw := _world(rs)
		var lw := _world(lh)
		var rew := _world(rf)
		var lew := _world(lf)
		var mark := " <-" if u >= 0.4 and u <= 0.75 else ""
		print("%.2f  %6.3f %6.3f %6.3f  | %6.3f %6.3f %6.3f  | %6.3f %6.3f %6.3f | %+0.3f%s  %6.3f   %6.3f" %
			[u, rw.x, rw.y, rw.z, rsw.x, rsw.y, rsw.z, lw.x, lw.y, lw.z, rsw.z - rw.z, mark,
			rew.y, lew.y])
	anim.stop()


# The left clip is built by reflecting every composed world pose across the x-plane, so at
# matching phases its guard/punching-side hands must sit at the right clip's x negated.
func check_mirror() -> void:
	var a_r := anim.get_animation("Terra Strike")
	var a_l := anim.get_animation("Terra Strike L")
	var lh := skel.find_bone("LeftHand")
	var rh := skel.find_bone("RightHand")
	reset()
	print("== mirror spot-check (L hand at p -> should equal negated R hand)")
	for u in [0.0, 0.4, 0.72]:
		var t: float = a_r.length * u
		anim.play("Terra Strike")
		anim.seek(minf(t, 0.999), true)
		var r := _world(rh)
		anim.stop()
		anim.play("Terra Strike L")
		anim.seek(minf(t, 0.999), true)
		var l := _world(lh)
		anim.stop()
		print("  p=%.2f  L=(%+.3f %+.3f %+.3f)  -R=(%+.3f %+.3f %+.3f)  d=%.4f" %
			[u, l.x, l.y, l.z, -r.x, r.y, r.z, l.distance_to(Vector3(-r.x, r.y, r.z))])
	reset()


func _world(bone: int) -> Vector3:
	var s := skel.get_bone_global_pose(bone).origin
	return Vector3(-s.x, s.y - 0.9, -s.z)


func reset() -> void:
	for i in range(skel.get_bone_count()):
		var r := skel.get_bone_rest(i)
		skel.set_bone_pose_position(i, r.origin)
		skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(i, r.basis.get_scale())
