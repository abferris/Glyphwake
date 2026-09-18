extends SceneTree

var world: Node3D
var player: CharacterBody3D
var terrain: Terrain3D
var camera: Camera3D
var zone: Area3D
var frames := 0
var started := false


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
		print("terrain=", terrain, " player=", player, " cam=", camera, " zone=", zone)
		if terrain and camera:
			terrain.set_camera(camera)
		player.global_position = Vector3(-750, 80.6, -1500)
		print("placed at ", player.global_position, " seafloor_h=", terrain.data.get_height(player.global_position), " water_surface=", zone.WaterSurfaceY)
		started = true
	if started and frames % 60 == 0:
		print("f=", frames, " body_y=", snappedf(player.global_position.y, 0.01), " eye_y=", snappedf(camera.global_position.y, 0.01),
			" swim=", player.IsSwimming, " under=", player.IsUnderwater, " wade=", player.IsWading,
			" overlaps=", zone.get_overlapping_bodies().size(), " vel=", player.velocity)
	if started and frames > 600:
		var skel := player.get_node("Visual/Skeleton3D") as Skeleton3D
		var bone_h := 0.7
		if skel:
			var b := skel.find_bone("Head")
			if b >= 0:
				bone_h = (skel.global_transform * skel.get_bone_global_pose(b)).origin.y - player.global_position.y
		var want_body: float = zone.WaterSurfaceY + 0.4 - bone_h
		print("FINAL body_y=", snappedf(player.global_position.y, 0.01), " eye_y=", snappedf(camera.global_position.y, 0.01),
			" swim=", player.IsSwimming, " under=", player.IsUnderwater)
		print("expected body_y=", want_body, " head_bone_h=", snappedf(bone_h, 0.001),
			" water=", zone.WaterSurfaceY)
		var failed := false
		if not player.IsSwimming:
			printerr("FAIL: expected to be swimming in the lake")
			failed = true
		if player.IsUnderwater:
			printerr("FAIL: expected to float at the surface, not be submerged")
			failed = true
		if absf(player.global_position.y - want_body) > 0.15:
			printerr("FAIL: expected to float at body_y≈", want_body, ", got ", player.global_position.y)
			failed = true
		if camera.global_position.y < zone.WaterSurfaceY:
			printerr("FAIL: the eye is below the surface (", camera.global_position.y, " < ", zone.WaterSurfaceY, ")")
			failed = true
		print("TEST SWIM ", "FAILED" if failed else "OK")
		quit(1 if failed else 0)
		return true
	return false
