extends SceneTree

const EXPORT_DIR := "C:/Projects/My project/Assets/TerrainExport"
const MANIFEST := EXPORT_DIR + "/splat_manifest.json"
const SPLAT_DIR := EXPORT_DIR + "/splats"
const DATA_DIR := "res://Assets/Terrain/island_data"
const R16 := "res://Assets/Terrain/heightmaps/island.r16"
const RW := 256
const W := 2816
const H := 3328
const ORIGIN_X := -2000
const ORIGIN_Z := -3000
const TILE_PX := 512
const SPACING := 1000.0 / 512.0

var terrain: Terrain3D
var stage := 0
var height_img: Image
var control_img: Image
var probes: Array = []
var filled := 0
var unknown_layers: Dictionary = {}


func _init() -> void:
	terrain = Terrain3D.new()
	root.call_deferred("add_child", terrain)


func _process(_delta: float) -> bool:
	match stage:
		0:
			if not terrain.is_inside_tree():
				return false
			terrain.data_directory = DATA_DIR
			terrain.region_size = RW
			terrain.vertex_spacing = SPACING
			print("regions loaded = ", terrain.data.get_region_count())
		1:
			var raw: Image = Terrain3DUtil.load_image(
				R16, ResourceLoader.CACHE_MODE_IGNORE,
				Vector2(50.0, 650.0), Vector2i(2561, 3073))
			print("raw height = ", raw.get_size(), " fmt=", raw.get_format(), " min/max=", Terrain3DUtil.get_min_max(raw))
			height_img = _pad_height(raw)
			control_img = _build_control()
			if control_img == null:
				quit(1)
				return true
			print("control image = ", control_img.get_size(), " fmt=", control_img.get_format(), " tiles=", filled)
			if not unknown_layers.is_empty():
				print("UNKNOWN LAYER NAMES: ", unknown_layers)
		2:
			var imgs: Array[Image] = []
			imgs.resize(Terrain3DRegion.TYPE_MAX)
			imgs[Terrain3DRegion.TYPE_HEIGHT] = height_img
			imgs[Terrain3DRegion.TYPE_CONTROL] = control_img
			terrain.data.import_images(imgs, Vector3(ORIGIN_X, 0, ORIGIN_Z), 0.0, 1.0)
			print("import_images done (height + control)")
		3:
			terrain.data.save_directory(DATA_DIR)
			print("save_directory done")
		4:
			var ok := 0
			for p in probes:
				var got: int = terrain.data.get_control(p[0])
				var want: int = p[1]
				var mark := "OK" if got == want else "MISMATCH"
				if got == want:
					ok += 1
				print("  ", mark, " ", p[0], " got=", got, " want=", want)
			print("verify: ", ok, "/", probes.size(), " probes match")
			var h := terrain.data.get_height(Vector3(0, 0, 0))
			var r := terrain.data.get_height_range()
			print("height(0,0)=", h, " (want 197.0268)  range=", r, " (want 0..636.4133)  regions=", terrain.data.get_region_count())
			quit(0)
			return true
	stage += 1
	return false


func _build_control() -> Image:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_error("cannot open " + MANIFEST)
		return null
	var m = JSON.parse_string(f.get_as_text())
	if typeof(m) != TYPE_DICTIONARY:
		push_error("bad manifest json")
		return null

	var id_by_name: Dictionary = {}
	var sea_id := 0
	for l in m["layers"]:
		var nm: String = str(l["name"])
		id_by_name[nm] = int(l["index"])
		var albedo := str(l.get("albedo", "")).to_lower()
		if albedo.contains("sand"):
			sea_id = int(l["index"])
	print("layer ids: ", id_by_name, " sea_id=", sea_id)

	var px := PackedInt32Array()
	px.resize(W * H)
	px.fill(_encode(sea_id, sea_id, 0))

	for t in m["terrains"]:
		var names: PackedStringArray = str(t["layerNames"]).split("|", false)
		var l2g: Array = []
		for nm in names:
			if id_by_name.has(nm):
				l2g.append(id_by_name[nm])
			else:
				unknown_layers[nm] = int(unknown_layers.get(nm, 0)) + 1
				l2g.append(0)
		var img := Image.load_from_file(SPLAT_DIR + "/" + str(t["file"]))
		if img == null:
			push_error("cannot load splat " + str(t["file"]))
			return null
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var ox := int((int(t["posX"]) - ORIGIN_X) / 1000) * TILE_PX
		var oy := int((int(t["posZ"]) - ORIGIN_Z) / 1000) * TILE_PX
		var data := img.get_data()
		for y in TILE_PX:
			var row := (oy + y) * W + ox
			for x in TILE_PX:
				var i := (y * TILE_PX + x) * 4
				var a0 := data[i]
				var a1 := data[i + 1]
				var a2 := data[i + 2]
				var a3 := data[i + 3]
				if a0 == 0 and a1 == 0 and a2 == 0 and a3 == 0:
					continue
				var bi := 0
				var bv := a0
				var oi := -1
				var ov := 0
				for k in [1, 2, 3]:
					var w: int = [a0, a1, a2, a3][k]
					if w > bv:
						oi = bi
						ov = bv
						bi = k
						bv = w
					elif w > ov:
						oi = k
						ov = w
				var base := int(l2g[bi]) if bi < l2g.size() else sea_id
				var over := int(l2g[oi]) if oi >= 0 and oi < l2g.size() else base
				var blend := 0 if (bv + ov) == 0 else int(round(float(ov) / float(bv + ov) * 255.0))
				px[row + x] = _encode(base, over, blend)
		filled += 1
		if probes.size() < 12:
			var wx := int(t["posX"]) + 256 * SPACING
			var wz := int(t["posZ"]) + 256 * SPACING
			probes.append([Vector3(wx, 0, wz), px[(oy + 256) * W + ox + 256]])

	var img_out := Image.create_from_data(W, H, false, Image.FORMAT_RF, px.to_byte_array())
	return img_out


func _encode(base: int, over: int, blend: int) -> int:
	return ((base & 0x1F) << 27) | ((over & 0x1F) << 22) | ((blend & 0xFF) << 14)


func _pad_height(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var sdata := src.get_data()
	var sea_row := PackedFloat32Array()
	sea_row.resize(W)
	sea_row.fill(50.0)
	var sea_bytes := sea_row.to_byte_array()
	var out := PackedByteArray()
	for y in h:
		out.append_array(sdata.slice(y * w * 4, (y + 1) * w * 4))
		out.append_array(sea_bytes.slice(w * 4, W * 4))
	for y in H - h:
		out.append_array(sea_bytes)
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RF, out)
	print("padded height = ", img.get_size(), " min/max=", Terrain3DUtil.get_min_max(img))
	return img
