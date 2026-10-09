extends SceneTree

## Generates the Cinder Shot cast: the clip the Cinder Shot active glyph plays while it casts,
## saved as Scenes/CinderShotCast.tscn for the glyph's CastAnimation slot.
##
## Run:  godot --headless --path C:/Projects/Glyphwake --script tools/build_cinder_cast.gd
##
## Standalone on purpose: the pose authoring here shares only the rig and the compose-rest-to-
## world technique, not any other glyph's clip, poses or tool.
##
## The motion is a two-handed gather-and-push, authored as REFERENCE POSES, not hand-tuned
## curves. Each pose's arm angles are SOLVED to land both hands on exact target points, so
## nothing is guessed from axis intuition. The poses are slerped between and written as local
## rotation keys, so bone lengths are preserved and key0 is the rest pose:
##
##   0.00      rest (the stickman T) -- key0, so the cast transitions from any pose
##   0.00-0.30 THE GATHER: both hands come to the chest centre -- between the shoulders, a
##             touch below shoulder height and just forward of the chest -- elbows folding to
##             hold the shot between the hands
##   0.30-0.55 THE PUSH: both arms extend forward together, hands side by side at shoulder
##             height at near full reach -- this is where the shot is pushed out
##   0.55-1.00 PUSH held -- the clip's final key is the extension, not rest; the cast layer's
##             blend-out then fades it back to the active locomotion
##
## One clip, no mirror: the motion is symmetric (both hands do the same thing), so there is no
## left/right variant to keep in sync.
##
## Forward on this rig is skeleton +Z (build_stickman rotates the +Z-facing FBX by MODEL_YAW,
## so the model faces Godot's -Z). The rest pose is a T: arms out at shoulder height, the right
## arm resting along -X and yawing +90 to face forward, the left along +X and yawing -90. Fold
## is an ELBOW FLEXION about skeleton RIGHT (X) -- verified empirically on this rig: folding the
## yawed-forward forearm about X raises the fist up from a tucked elbow. Negative folds = fist
## rises (elbow-low); near zero = straight extension.

const OUT := "res://Scenes/CinderShotCast.tscn"
const STICKMAN := "res://Scenes/Stickman.tscn"
const SKELETON_PATH := "Skeleton3D"

const CLIP := "Cinder Shot"
const CAST_LENGTH := 0.5
const CAST_KEYS := 51
const ROT_EPS_DEG := 0.5

# Reflection across the x-plane, used to conjugate an authored right-arm rotation into the left
# copy where the solver's tie-breaking makes the two arms' choices drift.
const MIRROR := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))

# Targets (skeleton space: facing = +Z, the fight line = the shoulder's rest y). The chest is
# between the shoulders, CHEST_DROP below shoulder height and CHEST_FORWARD in front of the
# chest -- both hands meet on the same point, which is where the shot sits between them. The
# push hands are side by side at shoulder height, near full reach so the arms push nearly
# straight.
const CHEST_X := 0.0
const CHEST_DROP := 0.05
const CHEST_FORWARD := 0.18
const PUSH_GAP := 0.07
const PUSH_Z := 0.66

# Arm solver ranges. The yaw brackets each side's forward-facing arc (the right arm yaws +90
# from its -X rest, the left -90); the level tilts the shoulder about the forward axis; the
# fold is the elbow flexion. The gather reaches a point just past the chest, so its fold runs
# deep; the push is near full reach, so its fold runs shallow.
const YAW_LO := -130.0
const YAW_HI := 130.0
const LEVEL_LO := -70.0
const LEVEL_HI := 70.0
const GATHER_FOLD_LO := -160.0
const GATHER_FOLD_HI := -55.0
const PUSH_FOLD_LO := -45.0
const PUSH_FOLD_HI := 20.0
const FOLD_AXIS := Vector3.RIGHT

# Torso: Spine1 leans forward with the push, Spine2 half of it -- a two-handed push has no
# left/right twist, so both spine bones pitch straight. The gather keeps a hint of the lean.
const S1_PITCH_DEG := 4.0
const S2_PITCH_DEG := 2.0

var skel: Skeleton3D
var g_order: Array = []
var parent: Dictionary = {}

var _pose_bones := ["Spine1", "Spine2", "RightShoulder", "RightForeArm", "LeftShoulder", "LeftForeArm"]
var _poses := []


func _initialize() -> void:
	var scene: PackedScene = load(STICKMAN)
	if scene == null:
		printerr("FAIL: could not load ", STICKMAN)
		quit(1)
		return
	var stickman: Node3D = scene.instantiate()
	skel = stickman.get_node_or_null(SKELETON_PATH) as Skeleton3D
	if skel == null:
		printerr("FAIL: no '", SKELETON_PATH, "' in ", STICKMAN)
		stickman.free()
		quit(1)
		return

	_order_bones()
	if g_order.size() == 0:
		printerr("FAIL: empty skeleton")
		stickman.free()
		quit(1)
		return

	_build_poses()

	var times: Array = []
	for f in range(CAST_KEYS):
		times.append(CAST_LENGTH * float(f) / float(CAST_KEYS - 1))

	var tracks := _save_clip(CLIP, times, _frame_keys(times))
	if not _pack_scene():
		stickman.free()
		quit(1)
		return
	print("BUILD CINDER CAST OK -> ", OUT, " clip='", CLIP, "' len=", CAST_LENGTH,
		" keys=", CAST_KEYS, " tracks=", tracks)
	stickman.free()
	quit(0)


# Solves both arms' chest and push targets into the reference poses. Each arm is a 2-link chain
# (shoulder + forearm), posed by a shoulder rotation (yaw about UP times level about Z) plus a
# forearm fold about skeleton RIGHT -- three unknowns, solved by grid + local refinement to
# place the HAND exactly. Among equal-error candidates the gather prefers the lowest elbow
# (natural, tucked), the push the straightest arm.
func _build_poses() -> void:
	var rest := _fk_world({})
	var rs := skel.find_bone("RightShoulder")
	var rf := skel.find_bone("RightForeArm")
	var rh := skel.find_bone("RightHand")
	var ls := skel.find_bone("LeftShoulder")
	var lf := skel.find_bone("LeftForeArm")
	var lh := skel.find_bone("LeftHand")
	var s1 := skel.find_bone("Spine1")
	var s2 := skel.find_bone("Spine2")
	var s: Vector3 = rest[rs].origin
	var gy: float = s.y
	var id := Basis.IDENTITY
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(S1_PITCH_DEG))
	var pitch_half := Basis(Vector3.RIGHT, deg_to_rad(S2_PITCH_DEG))
	var pitch_small := Basis(Vector3.RIGHT, deg_to_rad(S1_PITCH_DEG * 0.25))

	var chest := Vector3(CHEST_X, gy - CHEST_DROP, s.z + CHEST_FORWARD)
	# The push hands sit just outside their own shoulders: the right arm rests along -X, so its
	# side of the body is -X and its hand pushes at -PUSH_GAP; the left at +PUSH_GAP. Centred on
	# the chest, not on either shoulder, so the two hands read as one push.
	var push_r := Vector3(CHEST_X - PUSH_GAP, gy, s.z + PUSH_Z)
	var push_l := Vector3(CHEST_X + PUSH_GAP, gy, s.z + PUSH_Z)

	var gather_r := _solve_arm(rs, rf, rh, chest, GATHER_FOLD_LO, GATHER_FOLD_HI,
		{}, 0.0, YAW_HI, "elbow")
	var gather_l := _solve_arm(ls, lf, lh, chest, GATHER_FOLD_LO, GATHER_FOLD_HI,
		{}, YAW_LO, 0.0, "elbow")
	var ext_r := _solve_arm(rs, rf, rh, push_r, PUSH_FOLD_LO, PUSH_FOLD_HI,
		{ s1: pitch, s2: pitch_half }, 0.0, YAW_HI, "fold")
	var ext_l := _solve_arm(ls, lf, lh, push_l, PUSH_FOLD_LO, PUSH_FOLD_HI,
		{ s1: pitch, s2: pitch_half }, YAW_LO, 0.0, "fold")

	var wg_r := _arm_world(rs, rf, rh, gather_r, {})
	var wg_l := _arm_world(ls, lf, lh, gather_l, {})
	var we_r := _arm_world(rs, rf, rh, ext_r, { s1: pitch, s2: pitch_half })
	var we_l := _arm_world(ls, lf, lh, ext_l, { s1: pitch, s2: pitch_half })
	var weg_r: Vector3 = (_fk_world({ rs: gather_r["shoulder"], rf: gather_r["forearm"] })[rf] as Transform3D).origin
	var weg_l: Vector3 = (_fk_world({ ls: gather_l["shoulder"], lf: gather_l["forearm"] })[lf] as Transform3D).origin
	var wep_r: Vector3 = (_fk_world({ rs: ext_r["shoulder"], rf: ext_r["forearm"], s1: pitch, s2: pitch_half })[rf] as Transform3D).origin
	var wep_l: Vector3 = (_fk_world({ ls: ext_l["shoulder"], lf: ext_l["forearm"], s1: pitch, s2: pitch_half })[lf] as Transform3D).origin

	print("  gather R: fold=%.1f yaw=%.1f err=%.4f hand=(%.3f,%.3f,%.3f) | L fold=%.1f err=%.4f hand=(%.3f,%.3f,%.3f)"
		% [gather_r["fold"], gather_r["yaw"], gather_r["error"], wg_r.x, wg_r.y, wg_r.z,
			gather_l["fold"], gather_l["error"], wg_l.x, wg_l.y, wg_l.z])
	print("  push R:   fold=%.1f yaw=%.1f err=%.4f hand=(%.3f,%.3f,%.3f) | L fold=%.1f err=%.4f hand=(%.3f,%.3f,%.3f)"
		% [ext_r["fold"], ext_r["yaw"], ext_r["error"], we_r.x, we_r.y, we_r.z,
			ext_l["fold"], ext_l["error"], we_l.x, we_l.y, we_l.z])
	print("  elbows: gather R=(%.3f,%.3f,%.3f) L=(%.3f,%.3f,%.3f) | push R=(%.3f,%.3f,%.3f) L=(%.3f,%.3f,%.3f)"
		% [weg_r.x, weg_r.y, weg_r.z, weg_l.x, weg_l.y, weg_l.z,
			wep_r.x, wep_r.y, wep_r.z, wep_l.x, wep_l.y, wep_l.z])

	_poses = [
		{
			"p": 0.00, "Spine1": id, "Spine2": id,
			"RightShoulder": id, "RightForeArm": id, "LeftShoulder": id, "LeftForeArm": id,
		},
		{
			"p": 0.30, "Spine1": pitch_small, "Spine2": id,
			"RightShoulder": gather_r["shoulder"], "RightForeArm": gather_r["forearm"],
			"LeftShoulder": gather_l["shoulder"], "LeftForeArm": gather_l["forearm"],
		},
		{
			"p": 0.55, "Spine1": pitch, "Spine2": pitch_half,
			"RightShoulder": ext_r["shoulder"], "RightForeArm": ext_r["forearm"],
			"LeftShoulder": ext_l["shoulder"], "LeftForeArm": ext_l["forearm"],
		},
		{
			"p": 0.75, "Spine1": pitch, "Spine2": pitch_half,
			"RightShoulder": ext_r["shoulder"], "RightForeArm": ext_r["forearm"],
			"LeftShoulder": ext_l["shoulder"], "LeftForeArm": ext_l["forearm"],
		},
		{
			"p": 1.00, "Spine1": pitch, "Spine2": pitch_half,
			"RightShoulder": ext_r["shoulder"], "RightForeArm": ext_r["forearm"],
			"LeftShoulder": ext_l["shoulder"], "LeftForeArm": ext_l["forearm"],
		},
	]


# Local rotation keys: the authored offsets slerped between the surrounding reference poses,
# composed rest-to-world so key0 is the rest pose on every track. Because the first pose is
# rest and the last is the held push, the clip starts from rest and ends in the extension for
# the blend-out.
func _frame_keys(times: Array) -> Dictionary:
	var rot_keys := {}
	for gi in g_order:
		rot_keys[gi] = []
	for f in range(times.size()):
		var p: float = float(f) / float(CAST_KEYS - 1)
		var w := _cast_world(p)
		for gi in g_order:
			var pgi: int = parent[gi]
			var local_transform: Transform3D = w[gi] if pgi < 0 else w[pgi].affine_inverse() * w[gi]
			rot_keys[gi].append(local_transform.basis.orthonormalized().get_rotation_quaternion())
	return rot_keys


func _save_clip(clip_name: String, times: Array, rot_keys: Dictionary) -> int:
	var anim := Animation.new()
	anim.length = CAST_LENGTH
	anim.loop_mode = Animation.LOOP_NONE
	var tracks := _emit_rotation_tracks(anim, times, rot_keys)
	_lib.add_animation(clip_name, anim)
	return tracks


# One AnimationPlayer holding the clip, packed as the whole scene -- exactly the layout
# CastAnimationLayer expects to find and merge: it instantiates the scene, takes every clip
# out of the player's libraries, and frees the instance.
func _pack_scene() -> bool:
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	ap.root_node = NodePath("..")
	ap.add_animation_library("", _lib)
	var packed := PackedScene.new()
	var err := packed.pack(ap)
	ap.free()
	if err != OK:
		printerr("FAIL: pack ", OUT, " -> ", err)
		return false
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		printerr("FAIL: save ", OUT, " -> ", err)
		return false
	return true


var _lib := AnimationLibrary.new()


# Godot requires a parent bone to exist before its child, so ascending index is already
# parents-before-children; composing in this order makes the parent's world transform
# available when the child composes from it.
func _order_bones() -> void:
	for gi in range(skel.get_bone_count()):
		g_order.append(gi)
		parent[gi] = skel.get_bone_parent(gi)


# The offset each bone asks for at phase p: a slerp between the surrounding reference poses,
# identity for bones the cast does not touch, so the track list stays upper-body only.
func _cast_offset(bn: String, p: float) -> Basis:
	if not _pose_bones.has(bn):
		return Basis.IDENTITY
	for i in range(_poses.size() - 1):
		if p >= _poses[i]["p"] and p <= _poses[i + 1]["p"]:
			var w: float = seg(p, _poses[i]["p"], _poses[i + 1]["p"])
			var qa: Quaternion = (_poses[i][bn] as Basis).get_rotation_quaternion()
			var qb: Quaternion = (_poses[i + 1][bn] as Basis).get_rotation_quaternion()
			return Basis(qa.slerp(qb, w).normalized())
	return Basis.IDENTITY


# Composes rest world transforms top-down with the pose offsets: every bone stands at rest
# unless a pose rotates it, and children inherit their parents' rotations.
func _cast_world(p: float) -> Dictionary:
	var w := {}
	for gi in g_order:
		var rest: Transform3D = skel.get_bone_rest(gi)
		var pgi: int = parent[gi]
		var world: Transform3D = rest if pgi < 0 else w[pgi] * rest
		var off: Basis = _cast_offset(skel.get_bone_name(gi), p)
		if off != Basis.IDENTITY:
			world.basis = off * world.basis
		w[gi] = world
	return w


# Composes every bone's world transform from the given per-bone offset bases -- shared by the
# arm solver (FK for a candidate pose) and the diagnostics print.
func _fk_world(offs: Dictionary) -> Dictionary:
	var w := {}
	for gi in g_order:
		var rest: Transform3D = skel.get_bone_rest(gi)
		var pgi: int = parent[gi]
		var world: Transform3D = rest if pgi < 0 else w[pgi] * rest
		if offs.has(gi):
			world.basis = offs[gi] * world.basis
		w[gi] = world
	return w


# Numerical solve: shoulder yaw a about UP, shoulder level b about Z (forward), and forearm
# fold c -- an ELBOW FLEXION about FOLD_AXIS -- so the HAND lands on target. Coarse grid then
# local refinement. `yaw_lo..yaw_hi` brackets the forward-facing yaw for that side. Refinement
# steps stay inside the fold/level/yaw ranges so it cannot escape to a degenerate doubled-back
# arm. Among equal-error candidates the tie-break picks the read: the lowest elbow for a
# gathered guard, the straightest arm for the push.
func _solve_arm(sh: int, fg: int, hd: int, target: Vector3,
		fold_lo: float, fold_hi: float, extra: Dictionary,
		yaw_lo: float, yaw_hi: float, tie: String) -> Dictionary:
	var best_a := 0.0
	var best_b := 0.0
	var best_c := 0.0
	var best_err := 1e9
	var best_tie := 1e9
	for a: float in _seq(yaw_lo, yaw_hi, 8.0):
		for b: float in _seq(LEVEL_LO, LEVEL_HI, 8.0):
			for c: float in _seq(fold_lo, fold_hi, 8.0):
				var err := _arm_error(sh, fg, hd, a, b, c, target, extra)
				var t := _tie_value(sh, fg, a, b, c, tie, extra)
				if err < best_err - 1e-6:
					best_err = err
					best_a = a
					best_b = b
					best_c = c
					best_tie = t
				elif absf(err - best_err) <= 1e-6 and t < best_tie:
					best_tie = t
					best_a = a
					best_b = b
					best_c = c
	for step in [4.0, 1.0, 0.25]:
		var improved := true
		while improved:
			improved = false
			for da in [-step, 0.0, step]:
				for db in [-step, 0.0, step]:
					for dc in [-step, 0.0, step]:
						var na := clampf(best_a + da, yaw_lo, yaw_hi)
						var nb := clampf(best_b + db, LEVEL_LO, LEVEL_HI)
						var nc := clampf(best_c + dc, fold_lo, fold_hi)
						var err := _arm_error(sh, fg, hd, na, nb, nc, target, extra)
						if err < best_err - 1e-7:
							best_err = err
							best_a = na
							best_b = nb
							best_c = nc
							improved = true
	return {
		"shoulder": Basis(Vector3.UP, deg_to_rad(best_a))
			* Basis(Vector3(0, 0, 1), deg_to_rad(best_b)),
		"forearm": Basis(FOLD_AXIS, deg_to_rad(best_c)),
		"fold": best_c,
		"yaw": best_a,
		"level": best_b,
		"error": best_err,
	}


# Tie-break value: "elbow" prefers the lowest elbow (natural tucked guard), "fold" prefers the
# straightest arm (prevents a droopy, curled extension from winning).
func _tie_value(sh: int, fg: int, a: float, b: float, c: float, tie: String, extra: Dictionary) -> float:
	if tie == "fold":
		return absf(c)
	return _elbow_y(sh, fg, a, b, c, extra)


func _arm_error(sh: int, fg: int, hd: int, a: float, b: float, c: float,
		target: Vector3, extra: Dictionary) -> float:
	var offs := extra.duplicate()
	offs[sh] = Basis(Vector3.UP, deg_to_rad(a)) * Basis(Vector3(0, 0, 1), deg_to_rad(b))
	offs[fg] = Basis(FOLD_AXIS, deg_to_rad(c))
	var w := _fk_world(offs)
	return w[hd].origin.distance_to(target)


func _elbow_y(sh: int, fg: int, a: float, b: float, c: float, extra: Dictionary) -> float:
	var offs := extra.duplicate()
	offs[sh] = Basis(Vector3.UP, deg_to_rad(a)) * Basis(Vector3(0, 0, 1), deg_to_rad(b))
	offs[fg] = Basis(FOLD_AXIS, deg_to_rad(c))
	var w := _fk_world(offs)
	return w[fg].origin.y


# World hand position for a solved arm (skeleton space), for the diagnostics print.
func _arm_world(sh: int, fg: int, hd: int, solved: Dictionary, extra: Dictionary) -> Vector3:
	var offs := extra.duplicate()
	offs[sh] = solved["shoulder"]
	offs[fg] = solved["forearm"]
	return _fk_world(offs)[hd].origin


func _seq(lo: float, hi: float, step: float) -> Array:
	var out: Array = []
	var v: float = lo
	while v <= hi + 0.001:
		out.append(v)
		v += step
	return out


func seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


func _emit_rotation_tracks(anim: Animation, times: Array, rot_keys: Dictionary) -> int:
	var tracks := 0
	for gi in g_order:
		if gi == skel.find_bone("Root"):
			continue
		var rest_rot: Quaternion = skel.get_bone_rest(gi).basis.orthonormalized().get_rotation_quaternion()
		if _varies_quat(rot_keys[gi], rest_rot):
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, NodePath("Skeleton3D:" + skel.get_bone_name(gi)))
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			for f in range(times.size()):
				anim.rotation_track_insert_key(t, times[f], rot_keys[gi][f])
			tracks += 1
	return tracks


func _varies_quat(keys: Array, rest: Quaternion) -> bool:
	var rest_deg := rad_to_deg(rest.get_angle())
	for q in keys:
		var deg: float = rad_to_deg(q.angle_to(rest))
		if deg > ROT_EPS_DEG:
			return true
	return false
