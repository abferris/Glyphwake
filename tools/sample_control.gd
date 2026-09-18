extends SceneTree

const DATA_DIR := "res://Assets/Terrain/island_data"
const SPACING := 1000.0 / 512.0
const SAMPLES := [64, 256, 448]

var terrain: Terrain3D
var stage := 0


func _initialize() -> void:
	terrain = Terrain3D.new()
	root.call_deferred("add_child", terrain)


func _process(_delta: float) -> bool:
	match stage:
		0:
			if not terrain.is_inside_tree():
				return false
			terrain.data_directory = DATA_DIR
			terrain.region_size = 256
			terrain.vertex_spacing = SPACING
		1:
			var n := 0
			for posX in [-2000, -1000, 0, 1000, 2000]:
				for posZ in [-3000, -2000, -1000, 0, 1000, 2000]:
					for p in SAMPLES:
						for q in SAMPLES:
							var wx: float = posX + (p + 0.5) * SPACING
							var wz: float = posZ + (q + 0.5) * SPACING
							var v: int = terrain.data.get_control(Vector3(wx, 0, wz))
							print("SAMPLE ", posX, " ", posZ, " ", p, " ", q, " ", (v >> 27) & 0x1F, " ", (v >> 22) & 0x1F, " ", (v >> 14) & 0xFF)
							n += 1
			print("SAMPLES_DONE ", n)
			quit(0)
			return true
		_:
			quit(1)
			return true
	stage += 1
	return false
