extends SceneTree

const OUT := "res://Assets/Terrain/island_assets.tres"
const LAYER_DIR := "res://Assets/Terrain/layers/"

const LAYERS := [
	[0, "Rock", "Rock.png"],
	[1, "Sand", "Sand.png"],
	[2, "NewLayer 2", "Grass.png"],
	[3, "Grass", "Grass.png"],
	[4, "Dirt", "Dirt.png"],
]


func _initialize() -> void:
	var probe := Terrain3DTextureAsset.new()
	print("=== Terrain3DTextureAsset properties ===")
	for p in probe.get_property_list():
		if p["type"] != TYPE_NIL:
			print("  ", p["name"], " type=", p["type"], " usage=", p["usage"])
	print("=== Terrain3DAssets methods/props ===")
	var ap := Terrain3DAssets.new()
	for p in ap.get_property_list():
		print("  prop ", p["name"], " type=", p["type"])
	for m in ap.get_method_list():
		print("  method ", m["name"])

	var assets := Terrain3DAssets.new()
	assets.resource_name = "island_assets"
	var list: Array[Terrain3DTextureAsset] = []
	for row in LAYERS:
		var ta := Terrain3DTextureAsset.new()
		ta.id = int(row[0])
		ta.resource_name = str(row[1])
		ta.albedo_texture = load(LAYER_DIR + str(row[2]))
		list.append(ta)
	assets.texture_list = list
	if assets.has_method("update_list"):
		assets.update_list()
	var err := ResourceSaver.save(assets, OUT)
	print("save ", OUT, " err=", err, " ", error_string(err))
	quit(0)
