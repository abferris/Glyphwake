extends SceneTree

var world: Node3D
var player: CharacterBody3D
var terrain: Terrain3D
var camera: Camera3D
var zone: Area3D
var frames := 0
var started := false
var spot := Vector3.ZERO
var spot_h := 0.0


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 4:
		terrain = world.get_node_or_null("Terrain3D")
		player = world.get_node_or_null("Player")
		camera = world.get_node_or_null("Player/Head/Camera3D")
		zone = world.get_node_or_null("WaterZone")
		terrain.set_camera(camera)
		terrain.collision_mode = 3
		player.global_position = Vector3(500, 300, 0)
	if frames == 90:
		var ss := player.get_world_3d().direct_space_state
		var found := false
		var best := INF
		var z := -3000
		while z <= 3000:
			var x := -2000
			while x <= 3000:
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, zone.WaterSurfaceY + 40, z), Vector3(x, zone.WaterSurfaceY - 40, z))
				q.exclude = [player.get_rid()]
				var hit := ss.intersect_ray(q)
				if hit.has("position"):
					var hy: float = hit["position"].y
					if hy > zone.WaterSurfaceY - 2.3 and hy < zone.WaterSurfaceY - 0.3:
						var d: float = absf(x - 500) + absf(z)
						if d < best:
							best = d
							spot = Vector3(x, hy + 2.0, z)
							spot_h = hy
							found = true
				x += 25
			z += 25
		print("search done found=", found, " spot=", spot, " collision_ground_h=", spot_h, " depth=", zone.WaterSurfaceY - spot_h)
		if found:
			player.global_position = spot
			started = true
	if started and frames > 96 and frames % 60 == 0:
		print("f=", frames, " body_y=", snappedf(player.global_position.y, 0.01), " eye_y=", snappedf(camera.global_position.y, 0.01),
			" swim=", player.IsSwimming, " under=", player.IsUnderwater, " wade=", player.IsWading, " floor=", player.is_on_floor(),
			" vel=", player.velocity)
	if started and frames > 540:
		print("FINAL body_y=", snappedf(player.global_position.y, 0.01), " eye_y=", snappedf(camera.global_position.y, 0.01),
			" swim=", player.IsSwimming, " under=", player.IsUnderwater, " wade=", player.IsWading, " floor=", player.is_on_floor())
		print("expected standing body_y=", snappedf(spot_h + 0.9, 0.01))
		quit(0)
		return true
	return false
