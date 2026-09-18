@tool
extends EditorScript

const R16 := "res://Assets/Terrain/heightmaps/island.r16"
const OUT_DIR := "res://Assets/Terrain/island_data"

func _run() -> void:
	print("=== Glyphwake island import ===")
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.region_size = 256
	terrain.vertex_spacing = 1000.0 / 512.0
	print("vertex_spacing=", terrain.vertex_spacing,
		" region_size=", terrain.region_size,
		" region_world=", terrain.region_size * terrain.vertex_spacing)

	var root := get_editor_interface().get_edited_scene_root()
	print("edited scene root=", root)
	if root:
		for c in root.get_children():
			if c is Terrain3D:
				c.free()
		root.add_child(terrain)

	var img: Image = Terrain3DUtil.load_image(
		R16, ResourceLoader.CACHE_MODE_IGNORE,
		Vector2(50.0, 650.0), Vector2i(2561, 3073))
	print("image size=", img.get_size(), " format=", img.get_format())
	print("min/max=", Terrain3DUtil.get_min_max(img))

	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = img

	terrain.data.import_images(images, Vector3(-2000, 0, -3000), 0.0, 1.0)
	terrain.data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)
	print("region count=", terrain.data.get_region_count())
	print("height range=", terrain.data.get_height_range())

	print("--- landmarks (world x,z -> y) ---")
	var pts: Array[Vector3] = [
		Vector3(871.1, 0, 5.9), Vector3(500, 0, 0), Vector3(0, 0, 0),
		Vector3(-2000, 0, -3000), Vector3(3000, 0, -3000),
		Vector3(-2000, 0, 3000), Vector3(3000, 0, 3000),
		Vector3(-750, 0, -1500), Vector3(1750, 0, 1500),
	]
	for p in pts:
		print("  (", p.x, ",", p.z, ") -> ", terrain.data.get_height(p))

	var out: Image = terrain.data.layered_to_image(Terrain3DRegion.TYPE_HEIGHT)
	print("layered size=", out.get_size(), " min/max=", Terrain3DUtil.get_min_max(out))
	var thumb: Image = Terrain3DUtil.get_thumbnail(out, out.get_size())

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var err: int = thumb.save_png(OUT_DIR + "/import_dump.png")
	print("dump save err=", err, " ", error_string(err))
	terrain.data.save_directory(OUT_DIR)
	print("=== done; data saved to ", OUT_DIR, " ===")
