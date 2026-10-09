extends SceneTree

## Generates the Terra Strike punch cast: the clip the Terra Strike active glyph plays while
## it launches, saved as Scenes/TerraStrike.tscn for the glyph's CastAnimation slot.
##
## Run:  godot --headless --path C:/Projects/Glyphwake --script tools/build_terra_strike.gd
##
## The punch is authored as REFERENCE POSES, not hand-tuned curves. Each pose's arm angles are
## SOLVED to land a fist on an exact target point, so nothing is guessed from axis intuition --
## the two earlier attempts both failed because sign-getting wrong reads as a shrug. The poses
## are nlerped between and written as local rotation keys through the same compose-rest-to-world
## pipeline as before, so bone lengths are preserved and key0 is the rest pose.
##
## The motion is a boxer's fighting-pose straight:
##   0.00      rest (the stickman T) -- key0, so the cast transitions from any pose
##   0.00-0.12 RISE to the guard: both arms rotate up-forward, elbows fold to an acute angle,
##             fists end at SHOULDER HEIGHT in front of the chest, shoulders come UP into the
##             guard rather than thrusting forward
##   0.12-0.44 THE DRIVE: the punching forearm unfolds until the fist reaches the reticule
##             dead-ahead at shoulder height, Spine2 twisting in behind the punch
##   0.44-0.60 STABLE: full extension holds (this is the payload's hit window)
##   0.60-0.78 RECOVER: the hand returns level into the guard, the twist rotates back out
##   0.78-1.00 FIGHTING POSE held -- the clip's FINAL key is the guard, not rest; the cast
##             layer's blend-out then fades the guard back to the active locomotion
##
## The scene ships both "Terra Strike" (right punches) and its mirror "Terra Strike L" (left
## punches). The mirror is the same machinery as before: each bone takes its contralateral
## partner's authored rotation conjugated by the x-plane reflection (m * B * m), which mirrors
## reflection-sense rotations correctly, so the two clips cannot drift apart.
##
## Forward on this rig is skeleton +Z (build_stickman rotates the +Z-facing FBX by MODEL_YAW,
## so the model faces Godot's -Z). The rest pose is a T: arms out at shoulder height. Fist
## targets live in skeleton space -- the fight line is the shoulder's y, the reticle is dead
## ahead on it.

const OUT := "res://Scenes/TerraStrike.tscn"
const STICKMAN := "res://Scenes/Stickman.tscn"
const SKELETON_PATH := "Skeleton3D"

const CLIP := "Terra Strike"
const CLIP_MIRROR := "Terra Strike L"
const PUNCH_LENGTH := 0.5
const PUNCH_KEYS := 51
const ROT_EPS_DEG := 0.5

# Reflection across the x-plane, used to conjugate each authored rotation into the left copy.
const MIRROR := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))

# Fist targets (skeleton space: facing = +Z, the fight line = the shoulder's rest y). The
# guard fists sit at shoulder height just forward of the shoulders, elbows tucked low so the
# forearms fold up to an acute angle; the reticle is dead-ahead, near full reach so the punch
# lands on a nearly-straight arm. Fold is an ELBOW FLEXION about skeleton RIGHT (X) for both
# arms -- verified empirically: folding the yawed-forward forearm about X raises the fist up
# from a tucked elbow (this rig's right arm rests along -X). Negative folds = fist rises
# (elbow-low guard); near zero = straight extension. The left arm's yaw grid must be negative
# (its rest arm points +X, so it yaws the opposite way about UP to face forward).
const GUARD_X := 0.0
const GUARD_Z := 0.28
const RETICLE_Z := 0.66
const GUARD_FOLD_LO := -135.0
const GUARD_FOLD_HI := -55.0
const EXT_FOLD_LO := -45.0
const EXT_FOLD_HI := 20.0
const YAW_LO := -130.0
const YAW_HI := 130.0
const LEVEL_LO := -70.0
const LEVEL_HI := 70.0
const FOLD_AXIS := Vector3.RIGHT

# Torso: Spine2 twists toward the punching side as the arm arrives, rotates back on the
# recover; Spine1 leans a touch forward with the punch and keeps a hint through the guard.
const TWIST_DEG := 11.0
const PITCH_DEG := 4.0

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
	for f in range(PUNCH_KEYS):
		times.append(PUNCH_LENGTH * float(f) / float(PUNCH_KEYS - 1))

	var keys_r := _frame_keys(times, false)
	var keys_l := _frame_keys(times, true)

	var tracks := 0
	tracks += _save_clip(CLIP, times, keys_r)
	tracks += _save_clip(CLIP_MIRROR, times, keys_l)
	if not _pack_scene():
		stickman.free()
		quit(1)
		return
	print("BUILD TERRA STRIKE OK -> ", OUT, " clips='", CLIP, "'/'", CLIP_MIRROR,
		"' len=", PUNCH_LENGTH, " keys=", PUNCH_KEYS, " tracks=", tracks)
	stickman.free()
	quit(0)


# Solves the arm-chain fist targets into the reference poses. Each arm is a 2-link chain
# (shoulder + forearm), posed by a shoulder rotation (yaw about UP times level about Z) plus a
# forearm fold about Z -- three unknowns, solved by grid + local refinement to place the HAND
# exactly. Among equal-error candidates the lowest elbow wins, which keeps guards natural
# (elbow down, forearm up) instead of the mirrored contortion.
func _build_poses() -> void:
	var rest := _fk_world({})
	var rs := skel.find_bone("RightShoulder")
	var rf := skel.find_bone("RightForeArm")
	var rh := skel.find_bone("RightHand")
	var ls := skel.find_bone("LeftShoulder")
	var lf := skel.find_bone("LeftForeArm")
	var lh := skel.find_bone("LeftHand")
	var s2 := skel.find_bone("Spine2")
	var s1 := skel.find_bone("Spine1")
	var s: Vector3 = rest[rs].origin
	var gy: float = s.y
	var id := Basis.IDENTITY
	var twist := Basis(Vector3.UP, deg_to_rad(TWIST_DEG))
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(PITCH_DEG))
	var pitch_small := Basis(Vector3.RIGHT, deg_to_rad(PITCH_DEG * 0.25))

	var g_r := _solve_arm(rs, rf, rh, Vector3(s.x - GUARD_X, gy, s.z + GUARD_Z),
		GUARD_FOLD_LO, GUARD_FOLD_HI, {}, 0.0, YAW_HI, "elbow")
	var g_l := _solve_arm(ls, lf, lh, Vector3(s.x + GUARD_X, gy, s.z + GUARD_Z),
		GUARD_FOLD_LO, GUARD_FOLD_HI, {}, YAW_LO, 0.0, "elbow")
	var e_r := _solve_arm(rs, rf, rh, Vector3(0.0, gy, s.z + RETICLE_Z),
		EXT_FOLD_LO, EXT_FOLD_HI, { s2: twist, s1: pitch }, 0.0, YAW_HI, "fold")

	var wp_r := _arm_world(rs, rf, rh, g_r, {})
	var wp_l := _arm_world(ls, lf, lh, g_l, {})
	var we_r := _arm_world(rs, rf, rh, e_r, { s2: twist, s1: pitch })

	print("  guards: R fold=%.1f err=%.4f hand=(%.3f,%.3f,%.3f) | L fold=%.1f err=%.4f hand=(%.3f,%.3f,%.3f)"
		% [g_r["fold"], g_r["error"], wp_r.x, wp_r.y, wp_r.z,
			g_l["fold"], g_l["error"], wp_l.x, wp_l.y, wp_l.z])
	print("  ext R:  fold=%.1f err=%.4f hand=(%.3f,%.3f,%.3f)"
		% [e_r["fold"], e_r["error"], we_r.x, we_r.y, we_r.z])

	_poses = [
		{
			"p": 0.00, "Spine1": id, "Spine2": id,
			"RightShoulder": id, "RightForeArm": id, "LeftShoulder": id, "LeftForeArm": id,
		},
		{
			"p": 0.12, "Spine1": pitch_small, "Spine2": id,
			"RightShoulder": g_r["shoulder"], "RightForeArm": g_r["forearm"],
			"LeftShoulder": g_l["shoulder"], "LeftForeArm": g_l["forearm"],
		},
		{
			"p": 0.44, "Spine1": pitch, "Spine2": twist,
			"RightShoulder": e_r["shoulder"], "RightForeArm": e_r["forearm"],
			"LeftShoulder": g_l["shoulder"], "LeftForeArm": g_l["forearm"],
		},
		{
			"p": 0.60, "Spine1": pitch, "Spine2": twist,
			"RightShoulder": e_r["shoulder"], "RightForeArm": e_r["forearm"],
			"LeftShoulder": g_l["shoulder"], "LeftForeArm": g_l["forearm"],
		},
		{
			"p": 0.78, "Spine1": pitch_small, "Spine2": id,
			"RightShoulder": g_r["shoulder"], "RightForeArm": g_r["forearm"],
			"LeftShoulder": g_l["shoulder"], "LeftForeArm": g_l["forearm"],
		},
		{
			"p": 1.00, "Spine1": pitch_small, "Spine2": id,
			"RightShoulder": g_r["shoulder"], "RightForeArm": g_r["forearm"],
			"LeftShoulder": g_l["shoulder"], "LeftForeArm": g_l["forearm"],
		},
	]


# Local rotation keys for one side: the authored offsets, or the mirrored left punch -- each
# bone takes its contralateral partner's authred offset conjugated by the x-plane mirror.
# Because mirroring happens on the OFFSET (a pure rotation applied in skeleton space), key0
# stays the rest pose on both sides, unlike mirroring composed world poses whose origins cannot
# be reproduced by rotation-only tracks.
func _frame_keys(times: Array, mirror_side: bool) -> Dictionary:
	var rot_keys := {}
	for gi in g_order:
		rot_keys[gi] = []
	for f in range(times.size()):
		var p: float = float(f) / float(PUNCH_KEYS - 1)
		var w := _punch_world(p, mirror_side)
		for gi in g_order:
			var pgi: int = parent[gi]
			var local_transform: Transform3D = w[gi] if pgi < 0 else w[pgi].affine_inverse() * w[gi]
			rot_keys[gi].append(local_transform.basis.orthonormalized().get_rotation_quaternion())
	return rot_keys


func _save_clip(clip_name: String, times: Array, rot_keys: Dictionary) -> int:
	var anim := Animation.new()
	anim.length = PUNCH_LENGTH
	anim.loop_mode = Animation.LOOP_NONE
	var tracks := _emit_rotation_tracks(anim, times, rot_keys)
	_lib.add_animation(clip_name, anim)
	return tracks


# One AnimationPlayer holding both clips, packed as the whole scene -- exactly the layout
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


# The offset each bone asks for at phase p: a nlerp between the surrounding reference poses,
# identity for bones the fight does not touch, so the track list stays upper-body only. Because
# every pose holds key0 = rest at one end and the GUARD at the other, the clip starts from rest
# and ends in the fighting pose for the blend-out.
func _punch_offset(bn: String, p: float) -> Basis:
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
# unless a pose rotates it, and children inherit their parents' rotations. For the mirrored
# clip each bone uses its contralateral partner's offset reflected across the x-plane.
func _punch_world(p: float, mirror_side: bool) -> Dictionary:
	var w := {}
	for gi in g_order:
		var rest: Transform3D = skel.get_bone_rest(gi)
		var pgi: int = parent[gi]
		var world: Transform3D = rest if pgi < 0 else w[pgi] * rest
		var bn := skel.get_bone_name(gi)
		var off: Basis = _punch_offset(bn, p)
		if mirror_side:
			off = MIRROR * _punch_offset(_swap_side(bn), p) * MIRROR
		if off != Basis.IDENTITY:
			world.basis = off * world.basis
		w[gi] = world
	return w


func _swap_side(bn: String) -> String:
	if bn.begins_with("Right"):
		return "Left" + bn.substr(5)
	if bn.begins_with("Left"):
		return "Right" + bn.substr(4)
	return bn


# Composes every bone's world transform from the given per-bone offset bases -- shared by the
# arm solver (FK for a candidate pose) and the clip writer.
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
# local refinement. `yaw_lo..yaw_hi` brackets the forward-facing yaw for that side (the right
# arm rests along -X and yaws +90; the left along +X and yaws -90). Refinement steps stay
# inside the fold/level/yaw ranges so it cannot escape to a degenerate doubled-back arm. Among
# equal-error candidates the lowest elbow wins, which keeps guards elbow-down, fist-up.
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
# straightest arm (a level cross; prevents a droopy, curled reticle extension from winning).
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