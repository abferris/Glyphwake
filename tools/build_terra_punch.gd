extends SceneTree

## Terra Strike punch cast v4: fresh angle-based authoring (no solver).
## Generates the punch animation for the Terra Strike active glyph, saved as
## Scenes/TerraStrike.tscn. Clips: "Terra Strike" (right punches) and "Terra Strike L"
## (left punches). 0.5 s, 51 keys, 6 upper-body tracks, key0 = rest, final key = guard.
##
## Run:  godot --headless --path C:/Projects/Glyphwake --script tools/build_terra_punch.gd

const OUT := "res://Scenes/TerraStrike.tscn"
const STICKMAN := "res://Scenes/Stickman.tscn"
const SKELETON_PATH := "Skeleton3D"

const CLIP_R := "Terra Strike"
const CLIP_L := "Terra Strike L"
const PUNCH_LENGTH := 0.5
const PUNCH_KEYS := 51
const ROT_EPS_DEG := 0.5

const MIRROR := Basis(Vector3(-1.0,0.0,0.0), Vector3(0.0,1.0,0.0), Vector3(0.0,0.0,1.0))

# Arm angles (degrees), skeleton local. swing 0=T, + = forward; lift + = raise; flex = elbow bend (0 straight)
# Spine: twist + into punch (right side), pitch + forward
const ARM_R := {
	"rest":  { "swing": 0.0, "lift": 0.0, "flex": 0.0 },
	"guard": { "swing": 110.0, "lift": 95.0, "flex": 45.0 },
	"ext":   { "swing": 84.0, "lift": 7.0, "flex": 5.0 },
	"hold":  { "swing": 84.0, "lift": 7.0, "flex": 5.0 },
}

const ARM_L := {
	"rest":  { "swing": 0.0, "lift": 0.0, "flex": 0.0 },
	"guard": { "swing": 110.0, "lift": 240.0, "flex": 45.0 },
	"ext":   { "swing": 110.0, "lift": 240.0, "flex": 45.0 },
	"hold":  { "swing": 110.0, "lift": 240.0, "flex": 45.0 },
}

const SPINE := {
	"rest":  { "twist": 0.0, "pitch": 0.0 },
	"rise":  { "twist": 0.0,  "pitch": 15.0 },
	"drive": { "twist": 13.0, "pitch": 3.5 },
	"hold":  { "twist": 13.0, "pitch": 3.5 },
	"back":  { "twist": 0.0,  "pitch": 15.0 },
	"guard": { "twist": 0.0,  "pitch": 15.0 },
}

const POSES := [
	{ "p": 0.00, "side": "both", "state": "rest",  "spine": "rest"  },
	{ "p": 0.16, "side": "both", "state": "guard", "spine": "rise"  },
	{ "p": 0.34, "side": "r",    "state": "ext",   "spine": "drive" },
	{ "p": 0.78, "side": "r",    "state": "hold",  "spine": "hold"  },
	{ "p": 1.00, "side": "both", "state": "guard", "spine": "guard" },
]

var skel: Skeleton3D
var g_order: Array = []
var parent: Dictionary = {}
var _lib := AnimationLibrary.new()
var _pose_bones := ["Spine1", "Spine2", "RightShoulder", "RightForeArm", "LeftShoulder", "LeftForeArm"]
var _world_cache := {}
var _root_y: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load(STICKMAN)
	if scene == null:
		printerr("FAIL: load ", STICKMAN); quit(1); return
	var stickman: Node3D = scene.instantiate()
	skel = stickman.get_node_or_null(SKELETON_PATH) as Skeleton3D
	if skel == null:
		printerr("FAIL: skeleton missing"); stickman.free(); quit(1); return
	_order_bones()
	if g_order.size() == 0:
		printerr("FAIL: empty skeleton"); stickman.free(); quit(1); return
	_root_y = _w(skel.find_bone("Root")).y
	var times: Array = []
	for f in range(PUNCH_KEYS):
		times.append(PUNCH_LENGTH * float(f)/float(PUNCH_KEYS-1))
	var keys_r := _frame_keys(times, false)
	var keys_l := _frame_keys(times, true)
	if not _audit(keys_r, times, false, "Terra Strike"):
		stickman.free(); quit(2); return
	if not _audit(keys_l, times, true, "Terra Strike L"):
		stickman.free(); quit(3); return
	var tracks := 0
	tracks += _save_clip(CLIP_R, times, keys_r)
	tracks += _save_clip(CLIP_L, times, keys_l)
	if not _pack_scene():
		stickman.free(); quit(1); return
	print("BUILD TERRA PUNCH OK -> ", OUT, " clips='", CLIP_R, "'/'", CLIP_L,
		"' len=", PUNCH_LENGTH, " keys=", PUNCH_KEYS, " tracks=", tracks)
	stickman.free(); quit(0)

func _order_bones() -> void:
	for gi in range(skel.get_bone_count()):
		g_order.append(gi)
		parent[gi] = skel.get_bone_parent(gi)

func _arm_basis(side: String, state: String) -> Basis:
	var a: Dictionary = ARM_R[state] if side == "Right" else ARM_L[state]
	var s := Basis(Vector3.UP, deg_to_rad(a["swing"]))
	var l := Basis(Vector3.FORWARD, deg_to_rad(a["lift"])) # about Z? lift is raise; use local axis
	# lift: raise is rotation that moves hand up; about skeleton's forward axis? easier: compose as swing about UP * lift about RIGHT * flex about X
	var lift_axis := Vector3.RIGHT
	var flex_axis := Vector3.RIGHT
	# standard: shoulder yaw about vertical, then lift about horizontal axis perpendicular to arm; but use consistent
	s = Basis(Vector3.UP, deg_to_rad(a["swing"]))
	lift_axis = Vector3.BACK if false else Vector3.RIGHT # placeholder
	return s * Basis(Vector3.RIGHT, deg_to_rad(a["lift"])) * Basis(Vector3.RIGHT, deg_to_rad(a["flex"]))

func _bone_off(name: String, state_r: String, state_l: String) -> Basis:
	if name == "RightShoulder":
		return _rs(ARM_R[state_r])
	if name == "RightForeArm":
		return _rf(ARM_R[state_r])
	if name == "LeftShoulder":
		return _ls(ARM_L[state_l])
	if name == "LeftForeArm":
		return _lf(ARM_L[state_l])
	if name == "Spine1":
		var sp: Dictionary = SPINE[state_r] if state_r in SPINE else SPINE["rest"]
		return Basis(Vector3.RIGHT, deg_to_rad(sp["pitch"]))
	if name == "Spine2":
		var sp: Dictionary = SPINE[state_r] if state_r in SPINE else SPINE["rest"]
		return Basis(Vector3.UP, deg_to_rad(sp["twist"]))
	return Basis.IDENTITY

func _rs(a: Dictionary) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(a["swing"])) * Basis(Vector3.FORWARD, deg_to_rad(a["lift"])) * Basis(Vector3.RIGHT, deg_to_rad(a["lift"]*0.8))
func _rf(a: Dictionary) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(a["flex"]))
func _ls(a: Dictionary) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(a["swing"])) * Basis(Vector3.FORWARD, deg_to_rad(a["lift"])) * Basis(Vector3.RIGHT, deg_to_rad(a["lift"]*0.8))
func _lf(a: Dictionary) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(a["flex"]))

func _punch_offset(bn: String, p: float) -> Basis:
	if not _pose_bones.has(bn): return Basis.IDENTITY
	for i in range(POSES.size()-1):
		if p >= POSES[i]["p"] and p <= POSES[i+1]["p"]:
			var w := _seg(p, POSES[i]["p"], POSES[i+1]["p"])
			var ba := _basis_for(bn, POSES[i], POSES[i+1], false)
			var bb := _basis_for(bn, POSES[i], POSES[i+1], true)
			var qa := ba.get_rotation_quaternion()
			var qb := bb.get_rotation_quaternion()
			return Basis(qa.slerp(qb, w).normalized())
	return Basis.IDENTITY


func _seg(t: float, a: float, b: float) -> float:
	return clampf((t-a)/(b-a), 0.0, 1.0)

func _punch_world(p: float, mirror_side: bool) -> Dictionary:
	var w := {}
	for gi in g_order:
		var rest: Transform3D = skel.get_bone_rest(gi)
		var pgi: int = parent[gi]
		var world: Transform3D = rest if pgi < 0 else w[pgi] * rest
		var bn := skel.get_bone_name(gi)
		var off: Basis = _punch_offset(bn, p)
		if mirror_side:
			off = MIRROR * _punch_offset(_swap(bn), p) * MIRROR
		if off != Basis.IDENTITY:
			world.basis = off * world.basis
		w[gi] = world
	return w

func _swap(bn: String) -> String:
	if bn.begins_with("Right"): return "Left"+bn.substr(5)
	if bn.begins_with("Left"): return "Right"+bn.substr(4)
	return bn

func _fk_world(offs: Dictionary) -> Dictionary:
	var w := {}
	for gi in g_order:
		var rest: Transform3D = skel.get_bone_rest(gi)
		var pgi: int = parent[gi]
		var world: Transform3D = rest if pgi < 0 else w[pgi] * rest
		if offs.has(gi): world.basis = offs[gi]*world.basis
		w[gi] = world
	return w

func _frame_keys(times: Array, mirror_side: bool) -> Dictionary:
	var rot_keys := {}
	for gi in g_order: rot_keys[gi] = []
	for f in range(times.size()):
		var p: float = float(f)/float(PUNCH_KEYS-1)
		var w := _punch_world(p, mirror_side)
		for gi in g_order:
			var pgi: int = parent[gi]
			var lt: Transform3D = w[gi] if pgi < 0 else w[pgi].affine_inverse()*w[gi]
			rot_keys[gi].append(lt.basis.orthonormalized().get_rotation_quaternion())
	return rot_keys

func _save_clip(name: String, times: Array, rot_keys: Dictionary) -> int:
	var anim := Animation.new()
	anim.length = PUNCH_LENGTH
	anim.loop_mode = Animation.LOOP_NONE
	var tracks := _emit_tracks(anim, times, rot_keys)
	_lib.add_animation(name, anim)
	return tracks

func _pack_scene() -> bool:
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	ap.root_node = NodePath("..")
	ap.add_animation_library("", _lib)
	var packed := PackedScene.new()
	var err := packed.pack(ap)
	ap.free()
	if err != OK: printerr("FAIL pack ", err); return false
	err = ResourceSaver.save(packed, OUT)
	if err != OK: printerr("FAIL save ", err); return false
	return true

func _emit_tracks(anim: Animation, times: Array, rot_keys: Dictionary) -> int:
	var tracks := 0
	var root := skel.find_bone("Root")
	for gi in g_order:
		if gi == root: continue
		var rest := skel.get_bone_rest(gi).basis.orthonormalized().get_rotation_quaternion()
		if _varies(rot_keys[gi], rest):
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, NodePath("Skeleton3D:"+skel.get_bone_name(gi)))
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
			for f in range(times.size()):
				anim.rotation_track_insert_key(t, times[f], rot_keys[gi][f])
			tracks += 1
	return tracks

func _varies(keys: Array, rest: Quaternion) -> bool:
	for q in keys:
		if rad_to_deg(q.angle_to(rest)) > ROT_EPS_DEG: return true
	return false

func _w(bone: int) -> Vector3:
	return skel.get_bone_global_pose(bone).origin

func _audit(keys_r: Dictionary, times: Array, mirror_side: bool, name: String) -> bool:
	var ok := true
	print("== AUDIT ", name, " mirror=", mirror_side)
	for f in range(times.size()):
		var p := float(f)/float(PUNCH_KEYS-1)
		var w := _punch_world(p, mirror_side)
		var punch: Vector3 = (w[skel.find_bone("LeftHand")] if mirror_side else w[skel.find_bone("RightHand")]).origin
		var guard_a: Vector3 = (w[skel.find_bone("RightHand")] if mirror_side else w[skel.find_bone("LeftHand")]).origin
		var guard_b: Vector3 = w[skel.find_bone("RightHand")].origin if not mirror_side else w[skel.find_bone("LeftHand")].origin
		var sp: Vector3 = w[skel.find_bone("RightShoulder")].origin
		if absf(p-1.00) < 0.001 or absf(p-0.20) < 0.001:
			var rh2: Vector3 = w[skel.find_bone("RightHand")].origin
			var lh2: Vector3 = w[skel.find_bone("LeftHand")].origin
			var apart := absf(rh2.x - lh2.x)
			var low_h := minf(rh2.y, lh2.y)
			if apart < 0.08:
				printerr("FAIL guard cross apart=%.3f at p=%.2f" % [apart,p]); ok=false
			if low_h <= sp.y + 0.01:
				printerr("FAIL guard not above shoulders low=%.3f shoulder=%.3f at p=%.2f" % [low_h,sp.y,p]); ok=false
		if p >= 0.4 and p <= 0.75:
			if absf(punch.x) > 0.05:
				printerr("FAIL drive center punch.x=%.3f p=%.2f" % [punch.x,p]); ok=false
			if punch.z < 0.54:
				printerr("FAIL drive reach punch.z=%.3f p=%.2f" % [punch.z,p]); ok=false
			if absf(punch.y - sp.y) > 0.03:
				printerr("FAIL drive height punch.y-shoulder=%.3f p=%.2f" % [punch.y-sp.y,p]); ok=false
			if absf(guard_a.x) < 0.08:
				printerr("FAIL guard hand near center x=%.3f p=%.2f" % [guard_a.x,p]); ok=false
	print("  audit ok=", ok)
	return ok

func _basis_for(bn: String, pa: Dictionary, pb: Dictionary, to_b: bool) -> Basis:
	var st: String = pb["state"] if to_b else pa["state"]
	var spst: String = pb["spine"] if to_b else pa["spine"]
	if bn == "RightShoulder": return _rs(ARM_R[st])
	if bn == "RightForeArm": return _rf(ARM_R[st])
	if bn == "LeftShoulder": return _ls(ARM_L[st])
	if bn == "LeftForeArm": return _lf(ARM_L[st])
	if bn == "Spine1": return Basis(Vector3.RIGHT, deg_to_rad(SPINE[spst]["pitch"]))
	if bn == "Spine2": return Basis(Vector3.UP, deg_to_rad(SPINE[spst]["twist"]))
	return Basis.IDENTITY
