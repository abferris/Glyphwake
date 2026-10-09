extends SceneTree

## View toggle test: first person is the default, ViewToggleKey swaps to the third person boom
## and back, the head camera is the one that owns the viewport, the boom never ends up inside
## the terrain behind the player, and the debug chase camera takes the viewport over cleanly and
## gives it back, keeping the underwater tint while it holds it.

const SETTLE := 30
const FACE_REACH := 0.35
const TP_KEYS := 1

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var chase: Camera3D
var ticks := 0
var stage := 0
var view_key: Key = KEY_F1
var chase_key: Key = KEY_F3
var fp_dist := 0.0
var tp_dist := 0.0
var slope_spot := Vector3.INF
var failed := false


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 4:
		return false

	if stage == 0:
		if ticks < 25:
			return false
		player = world.get_node_or_null("Player")
		camera = player.get_node_or_null("Head/Camera3D")
		chase = player.get_node_or_null("DebugChaseCamera")
		if camera == null:
			_fail("no Head/Camera3D in the player scene")
			_finish()
			return true
		view_key = camera.get("ViewToggleKey")
		player.global_position = Vector3(1000, 100, -1100)
		stage = 1
		return false

	if stage == 1:
		# let the player land and the camera settle first
		if ticks < 25 + SETTLE:
			return false
		fp_dist = _boom()
		print("FP default: key=", OS.get_keycode_string(view_key), " first_person=", camera.get("FirstPerson"),
			" current=", camera.current, " chase_current=", chase.current if chase else null,
			" distance_from_head=", snappedf(fp_dist, 0.01))
		if not camera.current:
			_fail("first person should be the default view, but the head camera is not current")
		if chase != null and chase.current:
			_fail("the debug chase camera should not hold the viewport until it is toggled on")
		if fp_dist > FACE_REACH + 0.2:
			_fail("expected the camera in front of the head, got " + str(snappedf(fp_dist, 0.01)))
		_send_key(view_key, true)
		stage = 2
		return false

	if stage == 2:
		if ticks < 25 + SETTLE * 2:
			return false
		tp_dist = _boom()
		print("TP after toggle: first_person=", camera.get("FirstPerson"), " current=", camera.current,
			" distance_from_head=", snappedf(tp_dist, 0.01))
		if camera.get("FirstPerson"):
			_fail("the toggle should have left first person mode")
		if not camera.current:
			_fail("third person must keep the head camera current, or the viewport goes black")
		if tp_dist < FACE_REACH + 0.5:
			_fail("third person should sit further back than first person, got " + str(snappedf(tp_dist, 0.01)))
		if camera.global_position.y < _head_y():
			_fail("the third person boom ended up below the head")
		_send_key(view_key, true)
		stage = 3
		return false

	if stage == 3:
		if ticks < 25 + SETTLE * 3:
			return false
		var back := _boom()
		print("FP again: first_person=", camera.get("FirstPerson"), " distance_from_head=", snappedf(back, 0.01))
		if not camera.get("FirstPerson"):
			_fail("the toggle should have returned to first person")
		if absf(back - tp_dist) < 0.1 or absf(back - fp_dist) > 0.1:
			_fail("the camera did not settle back on the first person spot, got " + str(snappedf(back, 0.01)))
		_send_key(view_key, true)
		stage = 4
		return false

	if stage == 4:
		# stand at the foot of rising ground so the boom has something to hit: with yaw 0 the
		# body's forward is -Z, so the third person boom extends toward +Z
		if ticks < 25 + SETTLE * 4:
			return false
		slope_spot = _find_slope_base()
		if slope_spot == Vector3.INF:
			_fail("no rising ground found to test the boom against")
			_finish()
			return true
		player.global_position = slope_spot
		player.rotation.y = 0.0
		stage = 5
		return false

	if stage == 5:
		if ticks < 25 + SETTLE * 5:
			return false
		var full: float = camera.get("ThirdPersonDistance")
		var boom := _boom()
		# the ground directly under wherever the boom actually ended up
		var under := _ground(camera.global_position.x, camera.global_position.z)
		var rise := _ground(slope_spot.x, slope_spot.z + 2.5) - slope_spot.y
		print("TP at slope base: boom=", snappedf(boom, 0.01), " of ", snappedf(full, 0.01),
			" cam_y=", snappedf(camera.global_position.y, 0.01),
			" ground_under_cam=", snappedf(under, 0.01),
			" rise_behind=", snappedf(rise, 0.01))
		if boom > full - 0.05:
			_fail("the boom did not pull in against the slope, still at " + str(snappedf(boom, 0.01)))
		if camera.global_position.y < under - 0.05:
			_fail("the boom ended up inside the ground: cam_y=" + str(snappedf(camera.global_position.y, 0.01))
				+ " ground_under_cam=" + str(snappedf(under, 0.01)))
		if chase == null:
			_fail("the debug chase camera is missing from the player scene")
			_finish()
			return true
		stage = 6
		return false

	if stage == 6:
		# Submerge first, so the chase camera has to borrow a real underwater environment
		# instead of two nulls that trivially compare equal.
		if ticks < 25 + SETTLE * 6:
			return false
		player.global_position = Vector3(-750, 74.0, -1500)
		stage = 7
		return false

	if stage == 7:
		if ticks < 25 + SETTLE * 7:
			return false
		chase_key = chase.get("ToggleKey")
		print("submerged: under=", player.IsUnderwater, " swimming=", player.IsSwimming,
			" head_env_null=", camera.environment == null)
		if not player.IsUnderwater or not player.IsSwimming:
			_fail("the player is not submerged, so the underwater tint cannot be checked")
		if camera.environment == null:
			_fail("the head camera has no environment while submerged, the tint is not applied")
		_send_key(chase_key, true)
		stage = 8
		return false

	if stage == 8:
		if ticks < 25 + SETTLE * 8:
			return false
		var behind := chase.global_position.distance_to(player.global_position)
		print("chase on: key=", OS.get_keycode_string(chase_key), " chase_current=", chase.current,
			" head_current=", camera.current, " distance_from_body=", snappedf(behind, 0.01),
			" env_matches_head=", chase.environment == camera.environment)
		if not chase.current:
			_fail("the chase camera should hold the viewport after its toggle")
		if camera.current:
			_fail("two cameras are current at once, so the viewport is ambiguous")
		if behind < 1.0:
			_fail("the chase camera is sitting on the body instead of behind it, distance "
				+ str(snappedf(behind, 0.01)))
		if chase.environment != camera.environment:
			_fail("the chase camera lost the underwater tint, its environment differs from the head camera's")
		if chase.environment == null:
			_fail("the chase camera has no environment at all while submerged")
		_send_key(chase_key, true)
		stage = 9
		return false

	if stage == 9:
		if ticks < 25 + SETTLE * 9:
			return false
		print("chase off: chase_current=", chase.current, " head_current=", camera.current)
		if chase.current:
			_fail("the chase camera kept the viewport after being toggled off")
		if not camera.current:
			_fail("the head camera did not get the viewport back, the screen would be black")
		_finish()
		return true
	return false


func _finish() -> void:
	print("TEST VIEW ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)


func _head_y() -> float:
	var skel := player.get_node("Visual/Skeleton3D") as Skeleton3D
	return (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head"))).origin.y


## How far the camera sits from the head bone, which is what the view mode actually moves.
func _boom() -> float:
	return camera.global_position.distance_to(Vector3(player.global_position.x, _head_y(), player.global_position.z))


func _ground(x: float, z: float) -> float:
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -100, z))
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	return hit["position"].y if hit.has("position") else NAN


## A spot where the ground 2.5 m behind the player stands at least 1.2 m higher, so an
## unclipped boom would be inside the hillside.
func _find_slope_base() -> Vector3:
	var z := -2000.0
	while z <= 2000.0:
		var x := -1000.0
		while x <= 2000.0:
			var here := _ground(x, z)
			if not is_nan(here) and _ground(x, z + 2.5) - here > 1.2:
				return Vector3(x, here + 1.0, z)
			x += 50.0
		z += 50.0
	return Vector3.INF


func _send_key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _fail(msg: String) -> void:
	failed = true
	printerr("FAIL: ", msg)
