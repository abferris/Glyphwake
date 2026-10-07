extends SceneTree

## Gait-phase probe: samples the walk and run cycles' foot positions in engine space, so the
## lead-foot mapping (which phase has which foot forward) is read off the retargeted rig
## rather than hand-rolled math.

const PLAYER := "res://Scenes/Stickman.tscn"

var phase := 0
var skel: Skeleton3D
var anim: AnimationPlayer


func _initialize() -> void:
	var stick = (load(PLAYER) as PackedScene).instantiate()
	stick.name = "Probe"
	root.call_deferred("add_child", stick)


func _process(_delta: float) -> bool:
	match phase:
		0:
			if not root.get_node_or_null("Probe"):
				return false
			skel = root.get_node("Probe").find_child("Skeleton3D", true, false)
			anim = root.get_node("Probe").find_child("Anim", true, false)
			if skel == null or anim == null:
				printerr("probe: no skeleton or anim player")
				quit(1)
				return true
			probe("Walk Forward")
			probe("Run Forward")
			quit(0)
			return true
	return false


func probe(cname: String) -> void:
	if not anim.has_animation(cname):
		printerr("probe: no clip ", cname)
		return
	var a := anim.get_animation(cname)
	var lf := skel.find_bone("LeftFoot")
	var rf := skel.find_bone("RightFoot")
	# reset to rest, then step through the clip sampling the ankle origins
	for i in range(skel.get_bone_count()):
		var r := skel.get_bone_rest(i)
		skel.set_bone_pose_position(i, r.origin)
		skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(i, r.basis.get_scale())
	anim.play(cname)
	print("== ", cname, " len=", snappedf(a.length, 0.0001))
	var lines: Array = []
	var steps := 32
	for s in range(steps):
		var t := a.length * float(s) / float(steps)
		anim.seek(t, true)
		var L := skel.get_bone_global_pose(lf).origin
		var R := skel.get_bone_global_pose(rf).origin
		lines.append("phase=%.3f  Lz=%8.4f Rz=%8.4f  L-R=%+.4f" % [float(s) / steps, L.z, R.z, L.z - R.z])
	for l in lines:
		print(l)
	anim.stop()
