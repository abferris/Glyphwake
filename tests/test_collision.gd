extends SceneTree

var world: Node3D
var player: CharacterBody3D
var terrain: Terrain3D
var frames := 0
var ready_at := 0


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	if ps == null:
		push_error("World.tscn missing")
		quit(1)
		return
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == ready_at:
		terrain = world.get_node_or_null("Terrain3D")
		player = world.get_node_or_null("Player")
		var cam = world.get_node_or_null("Player/Head/Camera3D")
		print("cam=", cam, " terrain=", terrain, " player=", player)
		if terrain and cam:
			terrain.set_camera(cam)
		if terrain:
			print("regions=", terrain.data.get_region_count(), " collision_mode=", terrain.collision_mode)
		if player:
			print("start player=", player.global_position, " terrain_h=", terrain.data.get_height(player.global_position))
	if ready_at > 0 and frames > ready_at and frames % 60 == 0:
		print("f=", frames, " pos=", player.global_position, " floor=", player.is_on_floor(), " vel=", player.velocity, " th=", terrain.data.get_height(player.global_position))
	if ready_at > 0 and frames > ready_at + 600:
		print("FINAL pos=", player.global_position, " floor=", player.is_on_floor(), " th=", terrain.data.get_height(player.global_position))
		print("expected rest y = th + capsule half height (0.9) = ", terrain.data.get_height(player.global_position) + 0.9)
		quit(0)
		return true
	if frames == 2:
		ready_at = 4
	if frames > 4000:
		print("TIMEOUT")
		quit(2)
		return true
	return false
