extends SceneTree

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var frames := 0
var started := false
var pressed := false


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 4:
		player = world.get_node_or_null("Player")
		camera = world.get_node_or_null("Player/Head/Camera3D")
		var terrain = world.get_node_or_null("Terrain3D") as Node3D
		if terrain and camera:
			terrain.set_camera(camera)
		player.global_position = Vector3(-750, 80.6, -1500)
		started = true
	if started and not pressed:
		pressed = true
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F2
		ev.pressed = true
		ev.echo = false
		camera.call_deferred("_unhandled_input", ev)
	if started and frames == 90:
		camera.LookPitch = deg_to_rad(-90.0)
	if started and frames > 620:
		camera.call_deferred("_unhandled_input", InputEventKey.new())
		var lines = FileAccess.get_file_as_string("user://swim_debug.txt")
		print("--- swim_debug.txt ---")
		print(lines)
		var ok = lines != null and lines.contains("pitch=-1.57") or (lines != null and lines.contains("pitch=-90.00"))
		print("DEBUG DUMP ", "OK" if ok else "MISSING")
		quit(0 if ok else 1)
		return true
	return false