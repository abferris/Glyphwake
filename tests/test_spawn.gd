extends SceneTree

var world: Node3D
var player: CharacterBody3D
var terrain: Terrain3D
var camera: Camera3D
var zone: Area3D
var frames := 0
var start_y := 0.0


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		terrain = world.get_node("Terrain3D")
		player = world.get_node("Player")
		camera = world.get_node("Player/Head/Camera3D")
		zone = world.get_node("WaterZone")
		terrain.set_camera(camera)
		start_y = player.global_position.y
		print("spawn pos=", player.global_position, " terrain_h=", snappedf(terrain.data.get_height(player.global_position), 0.01))
	if frames > 4 and frames % 30 == 0:
		print("f=", frames, " y=", snappedf(player.global_position.y, 0.01), " ddy=", snappedf(player.global_position.y - start_y, 0.01),
			" floor=", player.is_on_floor(), " swim=", player.IsSwimming, " wade=", player.IsWading, " vel=", player.velocity)
	if frames > 210:
		var ground: float = terrain.data.get_height(player.global_position)
		print("FINAL y=", snappedf(player.global_position.y, 0.01), " floor=", player.is_on_floor(),
			" terrain_h=", snappedf(ground, 0.01), " expected_body_y=", snappedf(ground + 0.9, 0.01),
			" sink_from_spawn=", snappedf(start_y - player.global_position.y, 0.01))
		quit(0)
		return true
	return false
