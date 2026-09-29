extends SceneTree

const PLAYER := "res://Scenes/Player.tscn"
const FLOOR_Y := 0.0

var stage := 0
var player: CharacterBody3D
var anim: AnimationPlayer
var skel: Skeleton3D
var phys_mark := 0
var start_hand := Vector3.ZERO
var idle_pos := Vector3.ZERO
var surface_y := 0.0
var surf_eye_min := INF
var surf_eye_max := -INF
var surf_eye_sum := 0.0
var surf_body_max := -INF
var surf_under := 0
var surf_samples := 0


func _sample_surface() -> void:
	var cam := player.get_node("Head/Camera3D") as Camera3D
	surf_eye_min = minf(surf_eye_min, cam.global_position.y)
	surf_eye_max = maxf(surf_eye_max, cam.global_position.y)
	surf_eye_sum += cam.global_position.y
	surf_body_max = maxf(surf_body_max, player.global_position.y)
	if player.IsUnderwater:
		surf_under += 1
	surf_samples += 1
var total_frames := 0
var failed := false


func _initialize() -> void:
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor.add_child(shape)
	floor.position = Vector3(0, FLOOR_Y - 0.5, 0)
	root.call_deferred("add_child", floor)

	player = (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
	player.position = Vector3(0, FLOOR_Y + 0.9, 0)
	root.call_deferred("add_child", player)
	print("player instantiated")


func _process(_delta: float) -> bool:
	total_frames += 1
	match stage:
		0:
			if not player.is_inside_tree():
				return false
			anim = player.get_node_or_null("Visual/Anim") as AnimationPlayer
			skel = player.get_node_or_null("Visual/Skeleton3D") as Skeleton3D
			_check_wiring()
			anim.play("Idle")
			phys_mark = Engine.get_physics_frames()
		1:
			if Engine.get_physics_frames() - phys_mark < 30:
				return false
			idle_pos = skel.get_bone_global_pose(skel.find_bone("LeftHand")).origin
			print("IDLE hand=", idle_pos.snapped(Vector3.ONE * 0.001), " clip=", anim.current_animation)
			anim.play("Walk Forward")
			phys_mark = Engine.get_physics_frames()
		2:
			if Engine.get_physics_frames() - phys_mark < 20:
				return false
			start_hand = skel.get_bone_global_pose(skel.find_bone("LeftHand")).origin
			print("WALK hand=", start_hand.snapped(Vector3.ONE * 0.001), " clip=", anim.current_animation)
			var moved := (start_hand - idle_pos).length()
			print("hand delta idle->walk=", snappedf(moved, 0.0001))
			if moved < 0.05:
				_fail("skeleton pose did not change between Idle and Walk Forward")
			_send_key(KEY_W, true)
			phys_mark = Engine.get_physics_frames()
		3:
			if Engine.get_physics_frames() - phys_mark < 45:
				return false
			print("W-HELD clip=", anim.current_animation, " speed=", snappedf(player.velocity.length(), 0.01),
				" pos=", player.global_position.snapped(Vector3.ONE * 0.01))
			if anim.current_animation != "Walk Forward" and anim.current_animation != "Run Forward":
				_fail("expected Walk/Run Forward while holding W, got " + anim.current_animation)
			_send_key(KEY_W, false)
			phys_mark = Engine.get_physics_frames()
		4:
			if Engine.get_physics_frames() - phys_mark < 45:
				return false
			print("RELEASED clip=", anim.current_animation, " speed=", snappedf(player.velocity.length(), 0.01))
			_send_key(KEY_SHIFT, true)
			_send_key(KEY_W, true)
			phys_mark = Engine.get_physics_frames()
		5:
			if Engine.get_physics_frames() - phys_mark < 60:
				return false
			print("SPRINT clip=", anim.current_animation, " speed=", snappedf(player.velocity.length(), 0.01),
				" scale=", snappedf(anim.speed_scale, 0.01))
			if anim.current_animation != "Run Forward" and anim.current_animation != "Run Fast":
				_fail("expected Run while sprinting, got " + anim.current_animation)
			_send_key(KEY_W, false)
			_send_key(KEY_SHIFT, false)
			player.EnterWater(player.global_position.y + 5.0)
			phys_mark = Engine.get_physics_frames()
		6:
			if Engine.get_physics_frames() - phys_mark < 30:
				return false
			print("UNDERWATER clip=", anim.current_animation, " underwater=", player.IsUnderwater,
				" stroke=", snappedf(anim.speed_scale, 0.01))
			if anim.current_animation != "Swimming Loop":
				_fail("expected Swimming Loop underwater, got " + anim.current_animation)
			if absf(anim.speed_scale - 1.0) > 0.05:
				_fail("expected a calm stroke pace with no input, speed_scale=" + str(anim.speed_scale))
			_send_key(KEY_W, true)
			phys_mark = Engine.get_physics_frames()
		7:
			if Engine.get_physics_frames() - phys_mark < 30:
				return false
			print("UNDERWATER-W clip=", anim.current_animation, " stroke=", snappedf(anim.speed_scale, 0.01))
			if anim.current_animation != "Swimming Loop":
				_fail("expected Swimming Loop while moving underwater, got " + anim.current_animation)
			if anim.speed_scale < 1.2:
				_fail("expected the stroke to speed up while moving, speed_scale=" + str(anim.speed_scale))
			_send_key(KEY_W, false)
			player.global_position += Vector3.UP * 3.0
			surface_y = player.global_position.y + 0.5
			player.EnterWater(surface_y)
			surf_eye_min = INF
			surf_eye_max = -INF
			surf_eye_sum = 0.0
			surf_body_max = -INF
			surf_under = 0
			surf_samples = 0
			phys_mark = Engine.get_physics_frames()
		8:
			# The Swimming Loop clip swings the Head node through the stroke, so a single
			# sampled instant can land mid-beat with the head below the waterline. Sample the
			# whole treading window and judge the average instead of one arbitrary frame.
			_sample_surface()
			if Engine.get_physics_frames() - phys_mark < 90:
				return false
			print("SURFACE clip=", anim.current_animation, " underwater=", player.IsUnderwater,
				" wading=", player.IsWading, " body_y=", snappedf(player.global_position.y, 0.01),
				" surface_y=", snappedf(surface_y, 0.01),
				" sub=", snappedf(player.WadeSubmersion, 0.001),
				" vy=", snappedf(player.velocity.y, 0.01),
				" body_pitch=", snappedf(rad_to_deg(player.BodyPitch), 0.01),
				" head_bone_y=", snappedf((skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head"))).origin.y, 0.01),
				" eye min/avg/max=", snappedf(surf_eye_min, 0.01), "/", snappedf(surf_eye_sum / float(surf_samples), 0.01),
				"/", snappedf(surf_eye_max, 0.01),
				" underwater_frames=", surf_under, "/", surf_samples)
			if anim.current_animation != "Swimming Loop":
				_fail("expected Swimming Loop at the surface, got " + anim.current_animation)
			if player.IsWading:
				_fail("expected to tread at the surface, not wade, wading=" + str(player.IsWading))
			# treading holds the head bone on the waterline, so the eye should average at or
			# just above it rather than sitting under
			if surf_eye_sum / float(surf_samples) < surface_y - 0.05:
				_fail("expected the eye to average at the waterline, got " + str(snappedf(surf_eye_sum / float(surf_samples), 0.01)) + " < " + str(snappedf(surface_y - 0.05, 0.01)))
			if surf_under * 2 > surf_samples:
				_fail("the eye spent " + str(surf_under) + "/" + str(surf_samples) + " frames underwater while treading")
			if surf_body_max < surface_y - 0.2:
				_fail("expected to tread at the surface, body never got above " + str(snappedf(surf_body_max, 0.01)))
			player.ExitWater()
			phys_mark = Engine.get_physics_frames()
		9:
			if Engine.get_physics_frames() - phys_mark < 90:
				return false
			print("AFTER-EXIT clip=", anim.current_animation, " swimming=", player.IsSwimming)
			_send_key(KEY_SPACE, true)
			phys_mark = Engine.get_physics_frames()
		10:
			if Engine.get_physics_frames() - phys_mark < 10:
				return false
			_send_key(KEY_SPACE, false)
			var want := anim.get_animation("Jumping Up").length / 1.106
			print("JUMP clip=", anim.current_animation, " airborne=", not player.IsGrounded,
				" speed_scale=", snappedf(anim.speed_scale, 0.01), " want≈", snappedf(want, 0.01))
			if anim.current_animation != "Jumping Up":
				_fail("expected Jumping Up while airborne, got " + anim.current_animation)
			if absf(anim.speed_scale - want) > 0.1:
				_fail("expected the jump to span the 1.11 s airtime, speed_scale=" + str(anim.speed_scale))
			_report_alignment()
			print(("FAILED: " + _errors[0]) if failed else "TEST STICKMAN OK")
			quit(1 if failed else 0)
			return true
		_:
			quit(1)
			return true
	stage += 1
	return false


var _errors: Array[String] = []


func _check_wiring() -> void:
	if anim == null:
		_fail("Visual/Anim AnimationPlayer missing")
		return
	if skel == null:
		_fail("Visual/Skeleton3D missing")
		return
	var names := anim.get_animation_list()
	print("wiring: animations=", names.size(), " bones=", skel.get_bone_count())
	for want in ["Idle", "Walk Forward", "Run Forward", "Run Fast", "Swimming Loop", "Swim Forward", "Jumping Up"]:
		if not anim.has_animation(want):
			_fail("missing clip " + want)
	print("wiring: player mesh=", player.get_node_or_null("Visual/Skeleton3D/SM_StickMan") != null,
		" head_node_y=", player.get_node("Head").position.y)
	var vis := player.get_node_or_null("Visual") as Node3D
	var pfwd := -player.global_transform.basis.z
	var face := vis.global_transform.basis.z
	print("facing: model forward(+Z model space)=", face.snapped(Vector3.ONE * 0.001),
		" player forward=", pfwd.snapped(Vector3.ONE * 0.001), " dot=", snappedf(face.dot(pfwd), 0.001))
	if face.dot(pfwd) < 0.99:
		_fail("the model faces " + str(face) + " but the player faces " + str(pfwd))


func _report_alignment() -> void:
	var head_bone := skel.get_bone_global_pose(skel.find_bone("Head")).origin
	var top_bone := skel.get_bone_global_pose(skel.find_bone("HeadTop_End")).origin
	print("ALIGN player=", player.global_position.snapped(Vector3.ONE * 0.01),
		" capsule_bottom=", snappedf(player.global_position.y - 0.9, 0.01))
	print("ALIGN head_bone=", head_bone.snapped(Vector3.ONE * 0.001), " top_bone=", top_bone.snapped(Vector3.ONE * 0.001),
		" camera_y=", snappedf((player.get_node("Head") as Node3D).global_position.y, 0.001))
	var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
	if cam:
		var head_global := (player.get_node("Head") as Node3D).global_position
		print("eye: offset_from_head_node=", (cam.global_position - head_global).snapped(Vector3.ONE * 0.001),
			" eye_offset=", cam.EyeOffset, " face_reach=", cam.FaceReach, " fov=", cam.get("fov"))


func _send_key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _fail(msg: String) -> void:
	failed = true
	_errors.append(msg)
	printerr("FAIL: ", msg)
