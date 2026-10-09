extends SceneTree

## Probe: the redirect sequence — grounded run holding W, ground jump, mid-air switch to D
## with a Space tap. Prints (phase, tick, vy, hs, mode, stamina) per tick.

var world: Node3D
var player: CharacterBody3D
var t := 0
var phase := 0
var surface := 0.0
var ground := Vector3.ZERO


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func press(key: Key, want: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = want
	ev.echo = false
	Input.parse_input_event(ev)


func _physics_process(_delta: float) -> bool:
	t += 1
	if phase == 0:
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		if t < 8:
			return false
		player = world.get_node("Player")
		surface = world.get_node("WaterZone").WaterSurfaceY
		var ss := player.get_world_3d().direct_space_state
		var z := -2000
		while z <= 2000 and ground == Vector3.ZERO:
			var x := -2000
			while x <= 2000:
				var q := PhysicsRayQueryParameters3D.create(
					Vector3(x, surface + 60, z), Vector3(x, surface - 60, z))
				q.exclude = [player.get_rid()]
				var hit := ss.intersect_ray(q)
				if hit.has("position"):
					var hy: float = hit["position"].y
					if hy > surface + 3.0 and hy < surface + 40.0:
						ground = Vector3(x, hy, z)
						break
				x += 50
			z += 50
		player.global_position = ground + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO
		player.Jump(0.0)
		print("ground at ", ground)
		phase = 1
		t = 0
		return false

	var hs := Vector2(player.velocity.x, player.velocity.z).length()

	if phase == 1:
		if t < 8:
			return false
		press(KEY_W, true)
		phase = 2
		t = 0
		return false

	if phase == 2:
		if hs < 4.8:
			if t > 90:
				print("FAIL: run never reached 4.8")
				quit(1)
			return false
		press(KEY_SPACE, true)
		phase = 3
		t = 0
		return false

	if phase == 3:
		if t >= 2:
			press(KEY_SPACE, false)
		print("rise   t=%d vy=%.3f hs=%.3f mode=%d stamina=%.2f" %
			[t, player.velocity.y, hs, int(player.Mode), player.get_node("Resources").Stamina])
		if player.velocity.y < -1.5:
			press(KEY_W, false)
			press(KEY_D, true)
			press(KEY_SPACE, true)
			phase = 4
			t = 0
		return false

	if phase == 4:
		if t >= 2:
			press(KEY_SPACE, false)
		print("airtap t=%d vy=%.3f hs=%.3f mode=%d stamina=%.2f" %
			[t, player.velocity.y, hs, int(player.Mode), player.get_node("Resources").Stamina])
		if t >= 30:
			quit(0)
		return false

	return false
