extends SceneTree

## One-off generator for Resources/Glyphs/GlyphCatalog.tres.
##
## Written by hand, the typed arrays would be a guess: Godot has to serialize
## Array[TechniqueGlyphData] in whatever form it actually accepts, and a wrong guess fails
## silently the same way a hand-written scene export did. So the catalog is built in code and
## handed to ResourceSaver, and the file that comes out is by construction the format Godot
## reads back.
##
## Re-run after adding a glyph:  godot --headless --path C:/Projects/Glyphwake
##                                --script tools/build_catalog.gd
##
## The glyph list below is the only thing to edit; adding a new glyph is one line here plus one
## new .tres, and Scenes/Player.tscn is not touched either way.

const CATALOG_PATH := "res://Resources/Glyphs/GlyphCatalog.tres"
const TECHNIQUE_PATH := "res://Resources/Glyphs/Techniques/DoubleJump.tres"


func _initialize() -> void:
	var catalog: Resource = load("res://Scripts/Glyphs/Framework/GlyphCatalog.cs").new()
	var double_jump: Resource = load(TECHNIQUE_PATH)
	if catalog == null or double_jump == null:
		printerr("FAIL: could not load GlyphCatalog.cs or ", TECHNIQUE_PATH)
		quit(1)
		return

	# append(), not assignment. Assigning an untyped GDScript literal ([glyph]) to a C# typed-array
	# property replaces the array with an untyped one, which then saves without its element type
	# and reads back as Array[Resource] -- the type is then gone for good. append() mutates the
	# already-typed array in place and keeps it.
	catalog.Techniques.append(double_jump)
	catalog.DefaultSeedPoints = 5

	var declared: String = str(catalog.Techniques.get_typed_class_name())
	if declared != "TechniqueGlyphData":
		printerr("FAIL: Techniques is typed '", declared, "' before saving, expected TechniqueGlyphData")
		quit(1)
		return

	var err := ResourceSaver.save(catalog, CATALOG_PATH)
	if err != OK:
		printerr("FAIL: ResourceSaver.save returned ", err)
		quit(1)
		return
	print("BUILD CATALOG OK -> ", CATALOG_PATH)
	quit(0)