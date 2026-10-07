extends SceneTree

## Cast probe: fires the air-step cast through the controller's real path (a Space tap mid-air
## against the World scene) and watches the one-shot's state, the controller's cast state and
## the locomotion underneath, so a cast that fails to fire or refuses to hand back says which
## side is stuck.
##
## Diagnostics only, nothing to assert: prints one line per tick after the air jump.

const WORLD := "res://Scenes/World.tscn"

var phase := 0
var tick := 0
var t := 0
var world: Node3D
var player: CharacterBody3D
var tree: AnimationTree

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


func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	for key in release_at.keys():
		if tick >= release_at[key]:
			release_key(key)
			release_at.erase(key)

	if phase == 0:
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		if t < 8:
			return false
		player = world.get_node("Player")
		tree = player.get_node("AnimTree")
		var loadout: Node = player.get_node("Loadout")
		loadout.TrySetPoints(loadout.Entries[0].Glyph, 100)
		player.global_position = find_ground() + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO
		player.Jump(0.0)
		phase = 1
		t = 0
		return false

	if phase == 1:
		if t < 20:
			return false
		tap(KEY_SPACE)
		phase = 2
		t = 0
		return false

	if phase == 2:
		if player.is_on_floor() or player.velocity.y > 0.5:
			if t > 100:
				printerr("probe: never airborne")
				quit(1)
			return false
		tap(KEY_SPACE)
		phase = 3
		t = 0
		return false

	if phase == 3:
		var active = tree.get("parameters/Cast/active")
		var internal = tree.get("parameters/Cast/internal_active")
		var skeleton: Skeleton3D = player.get_node("Visual/Skeleton3D")
		var foot: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin
		print("tick=%d cast='%s' active=%s internal=%s anim='%s' footY=%.4f grounded=%s" % [
			t, player.CastState, str(active), str(internal),
			player.AnimationState, foot.y, str(player.is_on_floor())])
		if t >= 90:
			print("probe done")
			quit(0)
			return true
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
