extends SceneTree

const DATA_DIR := "res://Assets/Terrain/island_data"
const ASSETS := "res://Assets/Terrain/island_assets.tres"
const OUT := "res://Scenes/World.tscn"
const SPAWN_XZ := Vector2(1540, 260)
const CAPSULE_HALF_HEIGHT := 0.9

var world: Node3D
var terrain: Terrain3D
var check: Node3D
var stage := 0


func _initialize() -> void:
	world = Node3D.new()
	world.name = "World"
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	match stage:
		0:
			if not world.is_inside_tree():
				return false
			_build()
		1:
			var packed := PackedScene.new()
			var perr := packed.pack(world)
			var err := ResourceSaver.save(packed, OUT)
			print("pack err=", perr, " save err=", err, " ", error_string(err))
		2:
			var ps := load(OUT) as PackedScene
			print("reloaded=", ps)
			check = ps.instantiate()
			check.name = "WorldCheck"
			root.call_deferred("add_child", check)
		3:
			var t = check.get_node_or_null("Terrain3D")
			print("check terrain=", t, " children=", check.get_children())
			if t:
				print("  assets=", t.assets, " data_dir=", t.data_directory, " collision_mode=", t.collision_mode)
				print("  regions=", t.data.get_region_count(), " height(0,0)=", t.data.get_height(Vector3(0, 0, 0)))
			quit(0)
			return true
		_:
			quit(1)
			return true
	stage += 1
	return false


func _build() -> void:
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	world.add_child(terrain)
	terrain.owner = world
	if terrain.material == null:
		terrain.material = Terrain3DMaterial.new()
	terrain.assets = load(ASSETS)
	terrain.data_directory = DATA_DIR
	terrain.region_size = 256
	terrain.vertex_spacing = 1000.0 / 512.0
	terrain.collision_mode = 1
	print("terrain assets=", terrain.assets, " regions=", terrain.data.get_region_count())

	var water := MeshInstance3D.new()
	water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	water.mesh = pm
	water.position = Vector3(500, 55, 0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.09, 0.31, 0.45, 0.72)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.metallic = 0.3
	wmat.roughness = 0.08
	water.material_override = wmat
	world.add_child(water)
	water.owner = world

	var water_zone := Area3D.new()
	water_zone.name = "WaterZone"
	water_zone.set_script(load("res://Scripts/World/WaterZone.cs"))
	water_zone.monitoring = true
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "ZoneShape"
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(9000, 50, 9000)
	zone_shape.shape = zone_box
	water_zone.add_child(zone_shape)
	water_zone.position = Vector3(500, 30, 0)
	water_zone.set("WaterSurfaceY", 55.0)
	world.add_child(water_zone)
	water_zone.owner = world
	zone_shape.owner = world

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ssao_enabled = true
	we.environment = env
	world.add_child(we)
	we.owner = world

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.4
	world.add_child(sun)
	sun.owner = world

	var player_scene := load("res://Scenes/Player.tscn") as PackedScene
	if player_scene:
		var p := player_scene.instantiate()
		p.name = "Player"
		var player_pos := Vector3(SPAWN_XZ.x, 0, SPAWN_XZ.y)
		var ground: float = terrain.data.get_height(player_pos)
		p.position = Vector3(SPAWN_XZ.x, ground + CAPSULE_HALF_HEIGHT + 0.05, SPAWN_XZ.y)
		print("spawn=", p.position, " terrain_h=", ground)
		world.add_child(p)
		p.owner = world
	else:
		push_warning("Player.tscn not found")
