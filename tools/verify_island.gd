extends SceneTree

const DATA_DIR := "res://Assets/Terrain/island_data"
const OUT_DIR := "res://Assets/Terrain/island_previews"
const W := 2816
const H := 3328
const STEP := 2

const LAYER_COLORS := {
	0: Color8(115, 112, 107),
	1: Color8(209, 191, 140),
	2: Color8(107, 158, 82),
	3: Color8(107, 158, 82),
	4: Color8(133, 102, 71),
}
const LAYER_NAMES := {0: "Rock", 1: "Sand", 2: "NewLayer 2", 3: "Grass", 4: "Dirt"}

var terrain: Terrain3D
var stage := 0


func _init() -> void:
	terrain = Terrain3D.new()
	root.call_deferred("add_child", terrain)


func _process(_delta: float) -> bool:
	match stage:
		0:
			if not terrain.is_inside_tree():
				return false
			terrain.data_directory = DATA_DIR
			terrain.region_size = 256
			terrain.vertex_spacing = 1000.0 / 512.0
			print("regions=", terrain.data.get_region_count())
			print("range=", terrain.data.get_height_range())
		1:
			var pts := [
				[Vector3(871.1, 0, 5.9), 636.4], [Vector3(500, 0, 0), 422.2],
				[Vector3(0, 0, 0), 197.03], [Vector3(-2000, 0, -3000), 50.0],
				[Vector3(3000, 0, -3000), 50.0], [Vector3(-2000, 0, 3000), 50.0],
				[Vector3(3000, 0, 3000), 50.0], [Vector3(-750, 0, -1500), -1],
				[Vector3(1750, 0, 1500), -1],
			]
			print("--- landmark heights (want / got) ---")
			for p in pts:
				var got: float = terrain.data.get_height(p[0])
				var want = p[1]
				var mark := ""
				if want >= 0.0:
					mark = "OK" if absf(got - float(want)) < 0.1 else "MISMATCH"
				print("  (", p[0].x, ",", p[0].z, ") want=", want, " got=", got, " ", mark)
		2:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
			var himg: Image = terrain.data.layered_to_image(Terrain3DRegion.TYPE_HEIGHT)
			print("layered height ", himg.get_size(), " min/max=", Terrain3DUtil.get_min_max(himg))
			var thumb: Image = Terrain3DUtil.get_thumbnail(himg, himg.get_size() / STEP)
			print("save height_preview -> ", thumb.save_png(OUT_DIR + "/height_preview.png"))
			var cimg: Image = terrain.data.layered_to_image(Terrain3DRegion.TYPE_CONTROL)
			var bytes := cimg.get_data()
			var counts := {}
			var prev := Image.create(W / STEP, H / STEP, false, Image.FORMAT_RGB8)
			for y in H / STEP:
				for x in W / STEP:
					var i := ((y * STEP) * W + (x * STEP)) * 4
					var v: int = bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16) | (bytes[i + 3] << 24)
					var base := (v >> 27) & 0x1F
					counts[base] = int(counts.get(base, 0)) + 1
					prev.set_pixel(x, y, LAYER_COLORS.get(base, Color.MAGENTA))
			print("save control_preview -> ", prev.save_png(OUT_DIR + "/control_preview.png"))
			var total := (W / STEP) * (H / STEP)
			var keys := counts.keys()
			keys.sort()
			print("--- control base coverage ---")
			for k in keys:
				print("  id=", k, " ", LAYER_NAMES.get(k, "?"), " ", counts[k], " px ", snappedf(100.0 * counts[k] / total, 0.01), "%")
		3:
			quit(0)
			return true
	stage += 1
	return false
