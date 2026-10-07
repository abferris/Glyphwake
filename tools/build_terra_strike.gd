extends SceneTree

## Generates the Terra Strike punch cast: the clip the Terra Strike active glyph plays while
## it launches, saved as Scenes/TerraStrike.tscn for the glyph's CastAnimation slot.
##
## Run:  godot --headless --path C:/Projects/Glyphwake --script tools/build_terra_strike.gd
##
## The punch is synthesized exactly like the air steps (build_stickman.gd `_astep_offset`):
## rest world poses composed top-down with per-bone local rotations, then written back as
## the local rotation each key, so bone lengths are preserved. Unlike the air step, only the
## UPPER BODY is animated -- spine, shoulders, arms -- which is the whole point: the cast
## layer's one-shot takes over exactly the bones a clip's tracks name, so a clip with no leg
## tracks leaves the legs playing the locomotion underneath. A punch that animated the legs
## would freeze them mid-stride on ground and, in the air, cancel the jump's tuck.
##
## The pose is a left-lead boxing stance remembered only for the cast's duration: the torso
## turns so the LEFT side faces the punch (the enemy is read off the camera, which the model
## already faces), the right fist chambers at the hip, then a fast extension drives it through
## toward the target. Every rotation returns to rest by the last key, so the one-shot's
## blend-out hands the body back to locomotion cleanly. 0.25 s is the target length; the
## user tunes it, and every angle below is the first-pass number a playtest corrects -- the
## axis signs follow the air step's conventions (forward swing on a hanging segment is a
## +RIGHT rotation on this rig; a lean into the character's left is a -UP twist).

const OUT := "res://Scenes/TerraStrike.tscn"
const STICKMAN := "res://Scenes/Stickman.tscn"
const SKELETON_PATH := "Skeleton3D"

const CLIP := "Terra Strike"
const PUNCH_LENGTH := 0.25
const PUNCH_KEYS := 25
const ROT_EPS_DEG := 0.5

# First-pass pose, all tuned by playtest. +seg(). All envelopes end at 0 so the last key is
# rest and the blend-out has nothing to fight.
const TWIST_DEG := 22.0          # torso yaw into the left-lead stance, -UP = left side toward target
const CHEST_PITCH_DEG := 10.0    # chest lean into the strike on top of the twist
const GUARD_RAISE_DEG := 70.0    # left upper arm up to guard, +RIGHT
const GUARD_YAW_DEG := 25.0      # left shoulder forward into the stance
const GUARD_ELBOW_DEG := 95.0    # left forearm folded for the guard
const RIGHT_PULL_DEG := 20.0     # right shoulder draw back while chambering
const RIGHT_SWING_DEG := 65.0    # right shoulder swing through the strike
const RIGHT_RAISE_DEG := 10.0    # right elbow lift in the chamber
const RIGHT_ELBOW_DEG := 100.0   # right elbow fold in the chamber
const RIGHT_OVER_DEG := 6.0      # right elbow snaps *past* straight at the strike's peak


var skel: Skeleton3D
var g_order: Array = []
var parent: Dictionary = {}


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

	var times: Array = []
	for f in range(PUNCH_KEYS):
		times.append(PUNCH_LENGTH * float(f) / float(PUNCH_KEYS - 1))

	var rot_keys := {}
	for gi in g_order:
		rot_keys[gi] = []
	for f in range(PUNCH_KEYS):
		var p: float = float(f) / float(PUNCH_KEYS - 1)
		var w := _punch_world(p)
		for gi in g_order:
			var pgi: int = parent[gi]
			var local_transform: Transform3D = w[gi] if pgi < 0 else w[pgi].affine_inverse() * w[gi]
			rot_keys[gi].append(local_transform.basis.orthonormalized().get_rotation_quaternion())

	var anim := Animation.new()
	anim.length = PUNCH_LENGTH
	anim.loop_mode = Animation.LOOP_NONE
	var tracks := _emit_rotation_tracks(anim, times, rot_keys)

	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	ap.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	lib.add_animation(CLIP, anim)
	ap.add_animation_library("", lib)
	var packed := PackedScene.new()
	var perr := packed.pack(ap)
	var serr := ResourceSaver.save(packed, OUT)
	print("BUILD TERRA STRIKE OK -> ", OUT, " clip='", CLIP, "' len=", snappedf(anim.length, 0.001),
		" keys=", PUNCH_KEYS, " tracks=", tracks)
	if perr != OK or serr != OK:
		printerr("FAIL: pack=", perr, " save=", serr)
		quit(1)
		return
	stickman.free()
	quit(0)


# Bones in index order. Godot requires a parent bone to exist before its child, so ascending
# index is already parents-before-children; composing in this order makes the parent's world
# transform available when the child composes from it.
func _order_bones() -> void:
	for gi in range(skel.get_bone_count()):
		g_order.append(gi)
		parent[gi] = skel.get_bone_parent(gi)


# Composes rest world transforms top-down with the punch's offsets, the air step's structure:
# every bone stands at rest unless the punch rotates it, and children inherit their parents'
# rotations because the parent's composition is already in the chain.
func _punch_world(p: float) -> Dictionary:
	var w := {}
	for gi in g_order:
		var rest: Transform3D = skel.get_bone_rest(gi)
		var pgi: int = parent[gi]
		var world: Transform3D = rest if pgi < 0 else w[pgi] * rest
		var off: Basis = _punch_offset(skel.get_bone_name(gi), p)
		if off != Basis.IDENTITY:
			world.basis = off * world.basis
		w[gi] = world
	return w


# The punch asks each bone for, at phase p. Only upper-body / spine bones rotate; everything
# else returns identity so the clip's track list stays upper-body only and the cast's one-shot
# leaves the legs to the locomotion. Every term carries a (1 - rc) so the pose returns to rest
# by the last key.
func _punch_offset(bn: String, p: float) -> Basis:
	var cz := seg(p, 0.0, 0.28)    # chamber
	var st := seg(p, 0.30, 0.52)   # strike
	var rc := seg(p, 0.82, 1.0)    # recover
	var body := 1.0 - rc
	match bn:
		"Spine2":
			# The stance twist: -UP turns the left side toward the target, easing off as the
			# strike winds the chest back around. The chest pitch leads the arm through.
			return Basis(Vector3.UP, deg_to_rad(-TWIST_DEG * cz * (1.0 - 0.5 * st) * body)) \
				* Basis(Vector3.RIGHT, deg_to_rad(CHEST_PITCH_DEG * st * body))
		"Spine1":
			# The waist follows the chest part of the way so the pitch reads as a torso lean
			# rather than a kink at one vertebra; the twist stays up at Spine2.
			return Basis(Vector3.RIGHT, deg_to_rad(0.4 * CHEST_PITCH_DEG * st * body))
		"RightShoulder":
			return Basis(Vector3.UP, deg_to_rad((-RIGHT_PULL_DEG * cz + RIGHT_SWING_DEG * st) * body)) \
				* Basis(Vector3.RIGHT, deg_to_rad(RIGHT_RAISE_DEG * cz * body))
		"RightForeArm":
			return Basis(Vector3.RIGHT,
				deg_to_rad((RIGHT_ELBOW_DEG * (cz - st) - RIGHT_OVER_DEG * st) * body))
		"LeftShoulder":
			return Basis(Vector3.RIGHT, deg_to_rad(GUARD_RAISE_DEG * cz * body)) \
				* Basis(Vector3.UP, deg_to_rad(-GUARD_YAW_DEG * cz * body))
		"LeftForeArm":
			return Basis(Vector3.RIGHT, deg_to_rad(GUARD_ELBOW_DEG * cz * body))
	return Basis.IDENTITY


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