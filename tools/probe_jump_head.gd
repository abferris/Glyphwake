extends SceneTree

## Head-level probe: the jump clips tuck the spine, and the head used to dip with it. This
## watches the head bone's tilt from vertical while a jump clip plays -- a neutral ground jump
## (no input, no runtime tilt, the clip's own tuck is all there is) and a W-held jump (the
## runtime lean pitches the visual too).
##
## While a jump clip plays the tilt must stay near zero: that is the AirbornePose correction
## holding the head upright. The ticks after the landing show the release easing the head back
## into the idle pose.

const WORLD := "res://Scenes/World.tscn"
const TILT_LIMIT_DEG := 5.0
const AFTER_LAND_TICKS := 14

var phase := 0
var tick := 0
var world: Node3D
var player: CharacterBody3D
var skeleton: Skeleton3D
var head := -1
var worst := 0.0
var after_land := 0
var hold_w := false

var held := {}
var release_at := {}


func tap(key: int) -> void:
	press_key(key)
	release_at[key] = tick + 2


func press_key(key: int) -> void:
	if held.get(key, false):
		return
	held[key] = true
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = true
	ev.echo = false
	Input.parse_input_event(ev)


func release_key(key: int) -> void:
	if not held.get(key, false):
		return
	held[key] = false
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = false
	ev.echo = false
	Input.parse_input_event(ev)


func _initialize() -> void:
	world = (load(WORLD) as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func head_tilt_deg() -> float:
	var pose: Transform3D = skeleton.get_bone_global_pose(head)
	var up: Vector3 = (skeleton.global_transform.basis * pose.basis * Vector3.UP).normalized()
	return rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))


func bone_up_pitch_deg(bn: String) -> float:
	var bi := skeleton.find_bone(bn)
	if bi < 0:
		return 0.0
	var pose: Transform3D = skeleton.get_bone_global_pose(bi)
	var up: Vector3 = (skeleton.global_transform.basis * pose.basis * Vector3.UP).normalized()
	return rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))


func pose_line() -> String:
	var head_pose: Vector3 = skeleton.get_bone_global_pose(head).origin
	var lsh := skeleton.get_bone_global_pose(skeleton.find_bone("LeftShoulder")).origin
	var rsh := skeleton.get_bone_global_pose(skeleton.find_bone("RightShoulder")).origin
	var lhand := skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin
	var shoulder_dy: float = ((lsh.y + rsh.y) * 0.5 - head_pose.y)
	var hand_above_sho: float = lhand.y - lsh.y
	return "Spine=%.1f Spine1=%.1f Spine2=%.1f shoY-headY=%.3f hand-sho=%.3f" % [
		bone_up_pitch_deg("Spine"), bone_up_pitch_deg("Spine1"), bone_up_pitch_deg("Spine2"),
		shoulder_dy, hand_above_sho]


func _physics_process(_delta: float) -> bool:
	tick += 1
	for key in release_at.keys():
		if tick >= release_at[key]:
			release_key(key)
			release_at.erase(key)

	if hold_w:
		press_key(KEY_W)

	match phase:
		0:
			if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
				return false
			if tick < 8:
				return false
			player = world.get_node("Player")
			skeleton = player.get_node("Visual/Skeleton3D")
			head = skeleton.find_bone("Head")
			if head < 0:
				printerr("probe: no Head bone on the skeleton")
				quit(1)
				return true
			player.global_position = find_ground() + Vector3(0, 0.5, 0)
			player.velocity = Vector3.ZERO
			player.Jump(0.0)
			phase = 1
			return false

		1:
			# The first jump: no input held, so the dip the probe watches is the clip's own.
			if tick < 30:
				return false
			tap(KEY_SPACE)
			phase = 2
			after_land = 0
			return false

		2:
			var tilt := head_tilt_deg()
			var jumping: bool = player.AnimationState in ["Jumping Up", "Jump Forward L", "Jump Forward R"]
			if jumping:
				worst = maxf(worst, tilt)
				if tilt > TILT_LIMIT_DEG:
					print("tick=%d anim='%s' tilt=%.2f grounded=%s" % [
						tick, player.AnimationState, tilt, str(player.is_on_floor())])
					print("FAIL the head tilted %.2f deg while '%s' played, over the %.1f limit" % [
						tilt, player.AnimationState, TILT_LIMIT_DEG])
					quit(1)
					return true
				if tick % 6 == 0:
					print("tick=%d anim='%s' tilt=%.2f %s" % [
						tick, player.AnimationState, tilt, pose_line()])
			if player.is_on_floor():
				after_land += 1
				if after_land == 1:
					print("landed: anim='%s' tilt=%.2f" % [player.AnimationState, tilt])
				elif after_land <= AFTER_LAND_TICKS:
					print("  release tick %d anim='%s' tilt=%.2f" % [
						after_land - 1, player.AnimationState, tilt])
				elif not hold_w:
					print("neutral jump worst tilt while airborne: %.2f deg (limit %.1f)" % [worst, TILT_LIMIT_DEG])
					# --- the second jump: W held, the runtime lean pitches the visual ---
					hold_w = true
					worst = 0.0
					phase = 3
					tick = 0
					return false
				else:
					print("W-held jump worst tilt while airborne: %.2f deg (limit %.1f)" % [worst, TILT_LIMIT_DEG])
					print("probe done")
					quit(0)
					return true
			return false

		3:
			# Settled from the first jump; jump again with W held.
			if tick < 30:
				return false
			tap(KEY_SPACE)
			phase = 2
			after_land = 0
			return false

	return false


func find_ground() -> Vector3:
	var surface: float = world.get_node("WaterZone").WaterSurfaceY
	var ss := player.get_world_3d().direct_space_state
	var found := Vector3.ZERO
	var z := -2000
	while z <= 2000 and found == Vector3.ZERO:
		var x := -2000
		while x <= 2000:
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, surface + 60, z), Vector3(x, surface - 60, z))
			q.exclude = [player.get_rid()]
			var hit := ss.intersect_ray(q)
			if hit.has("position"):
				var hy: float = hit["position"].y
				if hy > surface + 3.0 and hy < surface + 40.0:
					found = Vector3(x, hy, z)
					break
			x += 50
		z += 50
	if found == Vector3.ZERO:
		printerr("probe: no island ground found above the waterline")
		quit(1)
	return found
