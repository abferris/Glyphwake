extends SceneTree

const FBX := "res://Assets/PolyOne/Free Stickman/Model/Free Pack - Stick Man.fbx"
const CLIPS := "res://Assets/PolyOne/Free Stickman/Animation/stickman_clips.json"
const TEX := "res://Assets/PolyOne/Free Stickman/Texture/T_Stickmans_Color.png"
const OUT := "res://Scenes/Stickman.tscn"
const TARGET_HEIGHT := 1.8
const FLOOR_Y := -0.9
const MODEL_YAW := PI
const RUN_BOB_GAIN := 1.5
const POS_EPS := 0.0002
const ROT_EPS_DEG := 0.5
const SCALE_EPS := 0.0005

# Synthesized upright treading-water clip: eggbeater legs + level arms held low by
# SurfaceSwimPose.ArmSubmersion, which is the authority for arm height at the surface.
const TREAD_NAME := "Swim Tread"
const TREAD_LENGTH := 2.0
const TREAD_KEYS := 40
const TREAD_LEAN_DEG := 5.0
const TREAD_SPLAY_DEG := 10.0
const TREAD_HIP_SWING_DEG := 16.0
const TREAD_KNEE_MIN_DEG := 12.0
const TREAD_KNEE_MAX_DEG := 76.0
const TREAD_ROOT_PITCH_DEG := 2.0
# The tread arms are not synthesized: they are copied from "Swimming Loop" so the
# character keeps the exact same arm stroke, and SurfaceSwimPose lowers the hands.
# Matched by exact name, not by suffix. The rig calls the upper arm "LeftArm", so an
# "UpArm" suffix never matched it and both upper arms were left in bind pose -- which on
# this rig points them straight out to the sides, giving the level-armed T-pose at the
# surface that SurfaceSwimPose then had nothing to correct.
const TREAD_ARM_SOURCE := "Swimming Loop"
const TREAD_ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
# The clavicle is what swings the upper arm: LeftShoulder's world orientation aims the segment to
# the elbow, so LeftArm only carries elbow flexion. "Swimming Loop" drives the clavicle almost
# level, so copied straight over it leaves the upper arm lying along the waterline and the
# character reads as a T-pose at the surface. These are layered on top of the source stroke to
# drop the arm and give it a scull.
const TREAD_TILT_BONES := ["LeftShoulder", "RightShoulder"]
const TREAD_ARM_DROP_DEG := 45.0
const TREAD_SCULL_SWING_DEG := 14.0

var ubones: Array
var urest: Array
var uclips: Array
var g_of_u := {}
var u_root := -1
var u_root_u := -1
var g_rest_w := {}
var u_rest_w := {}
var bind_fix := {}
var bone_child := {}
var skel: Skeleton3D
var mesh_inst: MeshInstance3D
var C := Transform3D.IDENTITY
var stage := 0
var stickman: Node3D
var check: Node3D
var anims := {}
var g_order: Array = []
# Tread arm bone indices, and the resampled source rotations per tread phase.
var tread_arms: Dictionary = {}
var tread_arm_src: Array = []


func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CLIPS))
	if parsed == null:
		printerr("failed to parse ", CLIPS)
		quit(1)
		return
	ubones = parsed["bones"]
	urest = parsed["rest"]
	uclips = parsed["clips"]
	print("clips=", uclips.size(), " unity_bones=", ubones.size())


func _process(_delta: float) -> bool:
	match stage:
		0:
			stickman = (load(FBX) as PackedScene).instantiate()
			stickman.name = "Stickman"
			stickman.transform = Transform3D.IDENTITY
			root.call_deferred("add_child", stickman)
		1:
			if not stickman.is_inside_tree():
				return false
			_prepare()
			_build_animations()
			_attach_animation_player()
			_apply_material()
			_fit_transform()
			_set_owners(stickman, stickman)
			var packed := PackedScene.new()
			var perr := packed.pack(stickman)
			var serr := ResourceSaver.save(packed, OUT)
			print("pack err=", perr, " save err=", serr, " ", error_string(serr))
		2:
			check = (load(OUT) as PackedScene).instantiate()
			check.name = "StickmanCheck"
			root.call_deferred("add_child", check)
		3:
			if not check.is_inside_tree():
				return false
			_verify()
			quit(0)
			return true
		_:
			quit(1)
			return true
	stage += 1
	return false


func _prepare() -> void:
	skel = _find(stickman, "Skeleton3D")
	mesh_inst = _find(stickman, "SM_StickMan")
	if skel == null or mesh_inst == null:
		printerr("skeleton or mesh not found")
		quit(1)
		return
	var bone_idx := {}
	for i in range(skel.get_bone_count()):
		bone_idx[skel.get_bone_name(i)] = i
	# parent -> first child, so a bone's rest offset to its own child can be looked up
	for i in range(skel.get_bone_count()):
		var p := skel.get_bone_parent(i)
		if p >= 0 and not bone_child.has(p):
			bone_child[p] = i
	for i in range(ubones.size()):
		var nm: String = ubones[i][0]
		if bone_idx.has(nm):
			g_of_u[i] = bone_idx[nm]
	print("godot_bones=", skel.get_bone_count(), " mapped=", g_of_u.size())
	if g_of_u.size() != skel.get_bone_count():
		printerr("bone map incomplete")

	var uroot := -1
	for i in range(ubones.size()):
		if ubones[i][0] == "Root":
			uroot = i
	u_root = g_of_u[uroot]
	u_root_u = uroot
	for ui in g_of_u.keys():
		u_rest_w[ui] = _uworld_rest(ui)
		g_rest_w[g_of_u[ui]] = _grest_world(g_of_u[ui])
	for ui in g_of_u.keys():
		bind_fix[g_of_u[ui]] = g_rest_w[g_of_u[ui]] * u_rest_w[ui].affine_inverse()
	C = skel.get_bone_rest(g_of_u[uroot]) * u_rest_w[uroot].affine_inverse()
	var worst_fix_pos := 0.0
	var worst_fix_ang := 0.0
	var worst_fix_bone := ""
	for ui in g_of_u.keys():
		var f: Transform3D = bind_fix[g_of_u[ui]]
		var ang := _ang_deg(f.basis.orthonormalized().get_rotation_quaternion(), Quaternion.IDENTITY)
		if f.origin.length() > worst_fix_pos or ang > worst_fix_ang:
			worst_fix_bone = ubones[ui][0]
		worst_fix_pos = maxf(worst_fix_pos, f.origin.length())
		worst_fix_ang = maxf(worst_fix_ang, ang)
	print("retarget: unity rig mirrored into godot space; max per-bone fix pos=", snappedf(worst_fix_pos, 0.0001),
		" ang=", snappedf(worst_fix_ang, 0.01), " (", worst_fix_bone, ")")


func _uworld_rest(ui: int) -> Transform3D:
	if ui < 0:
		return Transform3D.IDENTITY
	return _uworld_rest(ubones[ui][1]) * _trs(urest[ui])


func _grest_world(gi: int) -> Transform3D:
	var p: int = skel.get_bone_parent(gi)
	if p < 0:
		return skel.get_bone_rest(gi)
	return _grest_world(p) * skel.get_bone_rest(gi)


func _unity_worlds(uf: Array) -> Dictionary:
	var uw := {}
	for i in range(ubones.size()):
		var p: int = ubones[i][1]
		var local := _trs(uf[i])
		uw[i] = local if p < 0 else uw[p] * local
	return uw


func _build_order() -> void:
	g_order = []
	var done := {}
	for start in range(skel.get_bone_count()):
		if skel.get_bone_parent(start) < 0:
			_walk_order(start, done)


func _walk_order(gi: int, done: Dictionary) -> void:
	if done.has(gi):
		return
	done[gi] = true
	g_order.append(gi)
	for c in range(skel.get_bone_count()):
		if skel.get_bone_parent(c) == gi:
			_walk_order(c, done)


func _side_sign(bn: String) -> float:
	return -1.0 if bn.begins_with("Left") else 1.0


# World-space rotation applied to a joint at a given tread phase. Rotations only, so
# bone lengths are preserved exactly and sin(TAU*phase) makes the loop close perfectly.
func _tread_offset(bn: String, phase: float) -> Basis:
	var ph := TAU * phase
	var s := _side_sign(bn)
	# eggbeater: legs mirror with a half-cycle offset
	var lp: float = ph + (PI if bn.begins_with("Right") else 0.0)
	if bn.ends_with("UpLeg"):
		return Basis(Vector3.BACK, deg_to_rad(-s * TREAD_SPLAY_DEG)) \
			* Basis(Vector3.RIGHT, deg_to_rad(TREAD_HIP_SWING_DEG) * s * sin(lp))
	if bn.ends_with("Leg") and not bn.ends_with("UpLeg"):
		var flex: float = lerpf(TREAD_KNEE_MIN_DEG, TREAD_KNEE_MAX_DEG, 0.5 + 0.5 * sin(lp))
		return Basis(Vector3.RIGHT, deg_to_rad(flex))
	if bn.ends_with("Foot"):
		var f2: float = lerpf(TREAD_KNEE_MIN_DEG, TREAD_KNEE_MAX_DEG, 0.5 + 0.5 * sin(lp))
		return Basis(Vector3.RIGHT, deg_to_rad(-f2 * 0.8))
	match bn:
		"Root":
			return Basis(Vector3.RIGHT, deg_to_rad(TREAD_ROOT_PITCH_DEG) * sin(ph))
		"Spine":
			return Basis(Vector3.RIGHT, deg_to_rad(TREAD_LEAN_DEG))
		"Spine1":
			return Basis(Vector3.RIGHT, deg_to_rad(TREAD_LEAN_DEG) * 0.6)
		"Spine2":
			return Basis(Vector3.RIGHT, deg_to_rad(TREAD_LEAN_DEG) * 0.4)
	return Basis.IDENTITY


# Resamples the source swim clip's arm rotations onto the tread phases. The arm bones keep
# their exact source world rotation, so the stroke is identical to the swim animation; the
# upright torso/eggbeater legs come from the tread offsets, and SurfaceSwimPose lowers the
# hands below the waterline at runtime.
func _prep_tread_arms() -> void:
	tread_arms = {}
	tread_arm_src = []
	var clip: Dictionary = {}
	for c in uclips:
		if c["name"] == TREAD_ARM_SOURCE:
			clip = c
			break
	if clip.is_empty():
		printerr("TREAD FAIL: source arm clip '", TREAD_ARM_SOURCE, "' not found")
		return
	var inv := {}
	for ui in g_of_u.keys():
		inv[g_of_u[ui]] = ui
	for gi in skel.get_bone_count():
		var bn: String = skel.get_bone_name(gi)
		if bn in TREAD_ARM_BONES and inv.has(gi):
			tread_arms[gi] = inv[gi]
	var times: Array = clip["times"]
	var frames: Array = clip["frames"]
	var length: float = clip["length"]
	for f in range(TREAD_KEYS):
		# map the final key onto the source cycle end so the loop wraps seamlessly
		var t: float = (float(f) / float(maxi(TREAD_KEYS - 1, 1))) * length
		var a := 0
		while a < times.size() - 1 and times[a + 1] <= t:
			a += 1
		var b: int = mini(a + 1, times.size() - 1)
		var t0: float = times[a]
		var t1: float = times[b]
		var wgt: float = 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
		var wa := _unity_worlds(frames[a])
		var wb: Dictionary = wa if b == a else _unity_worlds(frames[b])
		var rots := {}
		for gi in tread_arms.keys():
			var ra: Basis = (bind_fix[gi] * wa[tread_arms[gi]]).basis.orthonormalized()
			var rb: Basis = (bind_fix[gi] * wb[tread_arms[gi]]).basis.orthonormalized()
			rots[gi] = ra.slerp(rb, wgt)
		tread_arm_src.append(rots)
	print("  tread arm source='", TREAD_ARM_SOURCE, "' bones=", tread_arms.size(),
		" phases=", tread_arm_src.size(), " src_len=", snappedf(length, 0.01))


# Drops the upper arm to a fixed angle below horizontal and sweeps it fore and aft in
# counter-phase with the eggbeater leg on the same side.
#
# The elevation correction rotates about the axis that changes elevation while leaving azimuth
# alone, so the arm drops straight down rather than swinging sideways. Applied to the clavicle's
# world basis, which pivots the whole arm chain about the shoulder joint.
func _tread_arm_tilt(gi: int, basis: Basis, phase: float) -> Basis:
	var bn: String = skel.get_bone_name(gi)
	if not bone_child.has(gi):
		return basis
	var limb: Vector3 = basis * skel.get_bone_rest(bone_child[gi]).origin
	if limb.length_squared() < 1.0e-8:
		return basis
	var cur := limb.normalized()
	var flat := Vector3(cur.x, 0.0, cur.z)
	if flat.length_squared() < 1.0e-8:
		return basis
	flat = flat.normalized()
	var cur_elev: float = asin(clampf(-cur.y, -1.0, 1.0))
	# UP x flat tilts the arm downward for a positive angle; the limb sits -Y of a rest bone.
	var tilt := Basis(Vector3.UP.cross(flat).normalized(),
		deg_to_rad(TREAD_ARM_DROP_DEG) - cur_elev)
	var s := _side_sign(bn)
	var lp: float = TAU * phase + (PI if bn.begins_with("Right") else 0.0)
	var swing := Basis(Vector3.UP, deg_to_rad(TREAD_SCULL_SWING_DEG) * s * sin(lp))
	return swing * tilt * basis


# Composes rest world transforms top-down, applying each joint's world-space offset so
# children inherit their parent's rotation. Starts upright (the rest pose), which is what
# separates treading from the prone swim clips.
func _tread_world(f: int) -> Dictionary:
	var phase: float = float(f) / float(TREAD_KEYS)
	var w := {}
	for gi in g_order:
		var rest: Transform3D = skel.get_bone_rest(gi)
		var p: int = skel.get_bone_parent(gi)
		var world: Transform3D = rest if p < 0 else w[p] * rest
		if tread_arms.has(gi):
			var src: Basis = tread_arm_src[f][gi]
			var cur: Basis = world.basis.orthonormalized()
			world.basis = (src * cur.inverse()) * world.basis
			if skel.get_bone_name(gi) in TREAD_TILT_BONES:
				world.basis = _tread_arm_tilt(gi, world.basis.orthonormalized(), phase)
		else:
			var off: Basis = _tread_offset(skel.get_bone_name(gi), phase)
			if off != Basis.IDENTITY:
				world.basis = off * world.basis
		w[gi] = world
	return w


func _build_tread() -> void:
	_prep_tread_arms()
	var times: Array = []
	for f in range(TREAD_KEYS):
		times.append(TREAD_LENGTH * float(f) / float(TREAD_KEYS))
	var pos_keys := {}
	var rot_keys := {}
	var scl_keys := {}
	for gi in g_of_u.values():
		pos_keys[gi] = []
		rot_keys[gi] = []
		scl_keys[gi] = []
	for f in range(TREAD_KEYS):
		var w := _tread_world(f)
		for gi in g_of_u.values():
			var p: int = skel.get_bone_parent(gi)
			var local: Transform3D = w[gi] if p < 0 else w[p].affine_inverse() * w[gi]
			pos_keys[gi].append(local.origin)
			rot_keys[gi].append(local.basis.orthonormalized().get_rotation_quaternion())
			scl_keys[gi].append(local.basis.get_scale())
	var anim := Animation.new()
	anim.length = TREAD_LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	_emit_tracks(anim, times, pos_keys, rot_keys, scl_keys)
	anims[TREAD_NAME] = anim
	print("  anim ", TREAD_NAME, " len=", snappedf(anim.length, 0.01), " tracks=", anim.get_track_count(),
		" keys=", TREAD_KEYS, " (synthesized treading)")


func _bob_track(anim: Animation, keys: Array, times: Array, gain: float) -> void:
	var n: int = keys.size()
	var lo: float = keys[0].y
	var hi: float = keys[0].y
	for v in keys:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var rest: Vector3 = skel.get_bone_rest(u_root).origin
	var t := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(t, NodePath("Skeleton3D:" + skel.get_bone_name(u_root)))
	anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	var drift: float = keys[n - 1].y - keys[0].y
	for f in range(times.size()):
		var u: float = float(f) / float(maxi(n - 1, 1))
		var y: float = lo + (keys[f].y - lo - drift * u) * gain
		anim.position_track_insert_key(t, times[f], Vector3(rest.x, y, rest.z))


func _build_animations() -> void:
	_build_order()
	for clip in uclips:
		var cname: String = clip["name"]
		var times: Array = clip["times"]
		var frames: Array = clip["frames"]
		var pos_keys := {}
		var rot_keys := {}
		var scl_keys := {}
		for gi in g_of_u.values():
			pos_keys[gi] = []
			rot_keys[gi] = []
			scl_keys[gi] = []
		for f in range(frames.size()):
			var gw := {}
			var uw := _unity_worlds(frames[f])
			for ui in g_of_u.keys():
				gw[g_of_u[ui]] = bind_fix[g_of_u[ui]] * uw[ui]
			for gi in g_of_u.values():
				var p: int = skel.get_bone_parent(gi)
				var local: Transform3D = gw[gi] if p < 0 else gw[p].affine_inverse() * gw[gi]
				pos_keys[gi].append(local.origin)
				rot_keys[gi].append(local.basis.orthonormalized().get_rotation_quaternion())
				scl_keys[gi].append(local.basis.get_scale())

		var anim := Animation.new()
		anim.length = clip["length"]
		anim.loop_mode = Animation.LOOP_NONE if cname == "Jumping Up" else Animation.LOOP_LINEAR
		if cname.begins_with("Run") and frames.size() > 1:
			_bob_track(anim, pos_keys[u_root], times, RUN_BOB_GAIN)
		var root_delta: Vector3 = pos_keys[u_root][frames.size() - 1] - pos_keys[u_root][0]
		var root_turn: float = _ang_deg(rot_keys[u_root][frames.size() - 1], rot_keys[u_root][0])
		var tracks := _emit_tracks(anim, times, pos_keys, rot_keys, scl_keys)
		anims[cname] = anim
		print("  anim ", cname, " len=", snappedf(anim.length, 0.01), " tracks=", tracks, " keys=", times.size(),
			" root delta=", root_delta.snapped(Vector3.ONE * 0.001), " turn=", snappedf(root_turn, 0.1), " deg (discarded)")
	_build_tread()


func _emit_tracks(anim: Animation, times: Array, pos_keys: Dictionary, rot_keys: Dictionary, scl_keys: Dictionary) -> int:
	var tracks := 0
	for gi in g_of_u.values():
		if gi == u_root:
			continue
		var rest := skel.get_bone_rest(gi)
		if _varies_vec3(pos_keys[gi], rest.origin):
			var t := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(t, NodePath("Skeleton3D:" + skel.get_bone_name(gi)))
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			for f in range(times.size()):
				anim.position_track_insert_key(t, times[f], pos_keys[gi][f])
			tracks += 1
		if _varies_quat(rot_keys[gi], rest.basis.orthonormalized().get_rotation_quaternion()):
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, NodePath("Skeleton3D:" + skel.get_bone_name(gi)))
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			for f in range(times.size()):
				anim.rotation_track_insert_key(t, times[f], rot_keys[gi][f])
			tracks += 1
		if _varies_vec3(scl_keys[gi], rest.basis.get_scale(), SCALE_EPS):
			var t := anim.add_track(Animation.TYPE_SCALE_3D)
			anim.track_set_path(t, NodePath("Skeleton3D:" + skel.get_bone_name(gi)))
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			for f in range(times.size()):
				anim.scale_track_insert_key(t, times[f], scl_keys[gi][f])
			tracks += 1
	return tracks


func _attach_animation_player() -> void:
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	ap.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for name in anims.keys():
		lib.add_animation(name, anims[name])
	ap.add_animation_library("", lib)
	stickman.add_child(ap)


func _apply_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mesh_inst.material_override = mat


func _fit_transform() -> void:
	var rel := _rel_to(mesh_inst, stickman)
	var aabb := mesh_inst.mesh.get_aabb()
	var minv := Vector3(INF, INF, INF)
	var maxv := Vector3(-INF, -INF, -INF)
	for i in range(8):
		var corner := aabb.get_endpoint(i)
		var p := rel * corner
		minv = minv.min(p)
		maxv = maxv.max(p)
	var height := maxv.y - minv.y
	var s := TARGET_HEIGHT / height
	stickman.scale = Vector3(s, s, s)
	stickman.position = Vector3(0, FLOOR_Y - minv.y * s, 0)
	print("mesh aabb local min=", minv, " max=", maxv, " height=", snappedf(height, 0.001), " scale=", snappedf(s, 0.0001))
	print("root transform=", stickman.transform)
	stickman.rotate_y(MODEL_YAW)
	print("model yaw=", snappedf(rad_to_deg(MODEL_YAW), 1.0), " deg (the FBX faces +Z, Godot forward is -Z)")
	_print_facing_evidence()


func _print_facing_evidence() -> void:
	var best := 0.0
	var best_dir := Vector3.ZERO
	var best_name := ""
	for clip in uclips:
		var frames: Array = clip["frames"]
		var a: Transform3D = _unity_worlds(frames[0])[u_root]
		var b: Transform3D = _unity_worlds(frames[frames.size() - 1])[u_root]
		var d: Vector3 = C.basis * (b.origin - a.origin)
		var h := Vector2(d.x, d.z).length()
		if h > best:
			best = h
			best_dir = d
			best_name = str(clip["name"])
	print("facing evidence: clips that travel, strongest is ", best_name, " root motion=", best_dir,
		" -> in model space forward is ", "+Z" if best_dir.z > 0.0 else "-Z")


func _expect_world(uw: Dictionary, ui: int) -> Transform3D:

	return bind_fix[g_of_u[ui]] * uw[ui]


func _expect_pinned(uw: Dictionary, ui: int) -> Transform3D:
	var root_full := _expect_world(uw, u_root_u)
	return g_rest_w[u_root] * root_full.affine_inverse() * _expect_world(uw, ui)


func _verify() -> void:
	var sk := _find(check, "Skeleton3D") as Skeleton3D
	var ap := _find(check, "Anim") as AnimationPlayer
	print("verify: animations=", ap.get_animation_list().size(), " skeleton=", sk)
	if sk == null or ap == null:
		return
	var worst := 0.0
	var worst_ang := 0.0
	var worst_offender := ""
	var samples := 0
	var worst_len := 0.0
	var worst_len_clip := ""
	var worst_loop := 0.0
	var worst_loop_clip := ""
	for ci in range(uclips.size()):
		var clip = uclips[ci]
		var cname: String = clip["name"]
		if not ap.has_animation(cname):
			print("  MISSING animation ", cname)
			continue
		var times: Array = clip["times"]
		var frames: Array = clip["frames"]
		var last: int = frames.size() - 1
		_reset_to_rest(sk)
		ap.play(cname)
		for f in [0, frames.size() / 2, last]:
			var seek_t: float = times[f]
			if f == last:
				seek_t = minf(seek_t, maxf(0.0, ap.current_animation_length - 0.0002))
			ap.seek(seek_t, true)
			var uw := _unity_worlds(frames[f])
			for ui in g_of_u.keys():
				if ui == u_root_u:
					continue
				var gi: int = g_of_u[ui]
				var expect := _expect_pinned(uw, ui)
				var got := sk.get_bone_global_pose(gi)
				var dt := (got.origin - expect.origin).length()
				var da := _ang_deg(got.basis.orthonormalized().get_rotation_quaternion(), expect.basis.orthonormalized().get_rotation_quaternion())
				if dt > worst:
					worst = dt
					worst_offender = cname + "/" + ubones[ui][0]
				worst_ang = maxf(worst_ang, da)
				samples += 1
			for gi in g_of_u.values():
				var p: int = sk.get_bone_parent(gi)
				if p < 0:
					continue
				var rest_len: float = (g_rest_w[gi].origin - g_rest_w[p].origin).length()
				var posed := sk.get_bone_global_pose(gi)
				var posed_p := sk.get_bone_global_pose(p)
				var len_dev := absf((posed.origin - posed_p.origin).length() - rest_len)
				if len_dev > worst_len:
					worst_len = len_dev
					worst_len_clip = cname + "/" + sk.get_bone_name(gi)
		if ap.get_animation(cname).loop_mode != Animation.LOOP_NONE:
			var uwa := _unity_worlds(frames[0])
			var uwb := _unity_worlds(frames[last])
			var closure := 0.0
			for ui in g_of_u.keys():
				if ui == u_root_u:
					continue
				var ea := _expect_pinned(uwa, ui).origin
				var eb := _expect_pinned(uwb, ui).origin
				closure = maxf(closure, (ea - eb).length())
			if closure > worst_loop:
				worst_loop = closure
				worst_loop_clip = cname
	ap.stop()
	print("VERIFY samples=", samples, " worst_pose_err=", snappedf(worst, 0.0001), " (", worst_offender, ")")
	print("VERIFY worst_angle_err_deg=", snappedf(worst_ang, 0.01), " worst_bone_length_dev=", snappedf(worst_len, 0.0001), " (", worst_len_clip, ")")
	print("VERIFY worst_loop_seam=", snappedf(worst_loop, 0.0001), " (", worst_loop_clip, ")")
	print("VERIFY idle-mid Head pose=", sk.get_bone_global_pose(g_of_u[_name_idx("Head")]).origin.snapped(Vector3.ONE * 0.001),
		" rest=", g_rest_w[g_of_u[_name_idx("Head")]].origin.snapped(Vector3.ONE * 0.001))
	_verify_tread(sk, ap)
	print("VERIFY animation list=", ap.get_animation_list())


# The synthesized tread has no Unity source to diff against, so check it directly:
# hands must stay below the head (the head rides the waterline while surface swimming),
# bone lengths must be untouched, and the loop must close.
func _verify_tread(sk: Skeleton3D, ap: AnimationPlayer) -> void:
	if not ap.has_animation(TREAD_NAME):
		print("  TREAD MISSING")
		return
	var head: int = sk.find_bone("Head")
	var hands: Array = [sk.find_bone("LeftHand"), sk.find_bone("RightHand")]
	var feet: Array = [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
	var worst_len := 0.0
	var worst_hand := -INF
	var min_foot := INF
	var head_y := 0.0
	var first: Array = []
	var lastp: Array = []
	_reset_to_rest(sk)
	ap.play(TREAD_NAME)
	for f in range(TREAD_KEYS):
		ap.seek(TREAD_LENGTH * float(f) / float(TREAD_KEYS), true)
		head_y = sk.get_bone_global_pose(head).origin.y
		var snap: Array = []
		for h in hands:
			worst_hand = maxf(worst_hand, sk.get_bone_global_pose(h).origin.y)
			snap.append(sk.get_bone_global_pose(h).origin)
		for ft in feet:
			min_foot = minf(min_foot, sk.get_bone_global_pose(ft).origin.y)
		if f == 0:
			first = snap
		if f == TREAD_KEYS - 1:
			lastp = snap
		for gi in range(sk.get_bone_count()):
			var p: int = sk.get_bone_parent(gi)
			if p < 0:
				continue
			var rest_len: float = (g_rest_w[gi].origin - g_rest_w[p].origin).length()
			var posed := sk.get_bone_global_pose(gi)
			worst_len = maxf(worst_len, absf((posed.origin - sk.get_bone_global_pose(p).origin).length() - rest_len))
	ap.stop()
	var seam := 0.0
	for i in range(first.size()):
		seam = maxf(seam, (first[i] - lastp[i]).length())
	print("TREAD head_y=", snappedf(head_y, 0.0001), " max_hand_y=", snappedf(worst_hand, 0.0001),
		" (runtime clamp target=head-0.18=", snappedf(head_y - 0.18, 0.0001), ") min_foot_y=", snappedf(min_foot, 0.0001),
		" bone_len_dev=", snappedf(worst_len, 0.0001), " hand_loop_seam=", snappedf(seam, 0.0001))
	if worst_len > 0.001:
		print("TREAD FAIL: bone length drifted by ", worst_len)
	if seam > 0.05:
		print("TREAD FAIL: arm loop seam ", seam, " is too large")


func _reset_to_rest(sk: Skeleton3D) -> void:
	for i in range(sk.get_bone_count()):
		var r := sk.get_bone_rest(i)
		sk.set_bone_pose_position(i, r.origin)
		sk.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
		sk.set_bone_pose_scale(i, r.basis.get_scale())


func _name_idx(nm: String) -> int:
	for i in range(ubones.size()):
		if ubones[i][0] == nm:
			return i
	return -1


func _trs(a) -> Transform3D:
	var pos := Vector3(a[0], a[1], a[2])
	var q := Quaternion(a[3], a[4], a[5], a[6])
	var s := Vector3(a[7], a[8], a[9])
	pos = Vector3(-pos.x, pos.y, pos.z)
	q = Quaternion(q.x, -q.y, -q.z, q.w)
	return Transform3D(Basis(q) * Basis.from_scale(s), pos)


func _varies_vec3(keys: Array, rest: Vector3, eps := POS_EPS) -> bool:
	for k in keys:
		if (k - rest).length() > eps:
			return true
	return false


func _varies_quat(keys: Array, rest: Quaternion) -> bool:
	for k in keys:
		if _ang_deg(rest, k) > ROT_EPS_DEG:
			return true
	return false


func _ang_deg(a: Quaternion, b: Quaternion) -> float:
	var dot := absf(clampf(a.dot(b), 0.0, 1.0))
	return rad_to_deg(2.0 * acos(dot))


func _rel_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain := []
	var n := node
	while n != null and n != ancestor:
		chain.push_front(n.transform)
		n = n.get_parent()
	var t := Transform3D.IDENTITY
	for m in chain:
		t = t * m
	return t


func _set_owners(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_set_owners(c, o)


func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r != null:
			return r
	return null
