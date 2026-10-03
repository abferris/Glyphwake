extends SceneTree

## The glyph catalog: one place that lists which glyphs exist, so Scenes/Player.tscn does not
## grow an ext_resource, a loadout sub_resource and a technique export per glyph.
##
##   - Resources/Glyphs/GlyphCatalog.tres loads and holds the real DoubleJump resource
##   - its Techniques array is still typed after a save/load round trip, not decayed to Array
##   - lookup by trigger answers the right glyph and returns null when nothing answers
##   - AllGlyphs flattens the three typed lists
##   - a loadout with no entries seeds itself from the catalog's DefaultSeedPoints
##   - seeding leaves an existing entry alone, so a restored save or a deliberate 0 survives
##   - a loadout with no catalog is left alone, because that is the shape test_glyph_loadout
##     builds in code and it must still start empty

const CATALOG_PATH := "res://Resources/Glyphs/GlyphCatalog.tres"
const DOUBLE_JUMP_PATH := "res://Resources/Glyphs/Techniques/DoubleJump.tres"
const LOADOUT_SCRIPT := "res://Scripts/Glyphs/Framework/GlyphLoadout.cs"

var phase := 0
var ticks := 0
var failed := false
var catalog: Resource
var glyph: Resource
var seeded: Node
var bare: Node


func fail(msg: String) -> void:
	printerr("FAIL: " + msg)
	failed = true


func expect(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func _initialize() -> void:
	catalog = load(CATALOG_PATH)
	if catalog == null:
		printerr("FAIL: ", CATALOG_PATH, " did not load")
		quit(1)
		return
	glyph = load(DOUBLE_JUMP_PATH)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 2:
		return false

	if phase == 0:
		check_loads()
		check_typed_round_trip()
		check_lookup()
		phase = 1
		return false

	if phase == 1:
		stand_up(LOADOUT_SCRIPT, "SeededBody", "Loadout", catalog)
		stand_up(LOADOUT_SCRIPT, "BareBody", "Loadout", null)
		phase = 2
		return false

	if phase == 2:
		# The two bodies are added deferred, so poll rather than assume they are there yet.
		if not root.has_node("SeededBody/Loadout") or not root.has_node("BareBody/Loadout"):
			return false
		seeded = root.get_node("SeededBody/Loadout")
		bare = root.get_node("BareBody/Loadout")
		phase = 3
		return false

	if phase == 3:
		check_seeding()
		check_validate()
		verdict()
		return true

	return false


func stand_up(script_path: String, body_name: String, child_name: String, cat: Resource) -> void:
	var body := Node.new()
	body.name = body_name
	var child: Node = load(script_path).new()
	child.name = child_name
	child.Catalog = cat
	body.add_child(child)
	root.call_deferred("add_child", body)


func check_loads() -> void:
	expect(catalog.Techniques != null, "the catalog should expose a Techniques array")
	expect(catalog.Actives != null, "the catalog should expose an Actives array")
	expect(catalog.Passives != null, "the catalog should expose a Passives array")
	expect(catalog.Techniques.size() == 1, "the catalog should hold the one authored technique, got %d" % catalog.Techniques.size())
	expect(catalog.Actives.is_empty(), "no actives are authored yet")
	expect(catalog.Passives.is_empty(), "no passives are authored yet")
	expect(catalog.Techniques[0] == glyph, "the catalog should hold the DoubleJump resource itself, not a copy")


## Godot 4.7 does not preserve the script element type on an exported C# array: these three
## lists reach Godot as Array[Resource] and save without a type marker, so the editor offers any
## resource for any of them. Asserted here so a Godot upgrade that changes it is noticed --
## GlyphCatalog.Validate would then be redundant, but a redundant check is not a bug.
func check_typed_round_trip() -> void:
	var declared: String = str(catalog.Techniques.get_typed_class_name())
	expect(declared == "Resource",
		"exported C# arrays are expected to reach Godot as Array[Resource]; got '%s'" % declared)
	expect(catalog.Techniques.size() == 1 and catalog.Techniques[0] == glyph,
		"the untyped array must still hold the real glyph, which is what the design relies on")


## Validate is the editor's missing type filter, run before the loadout seeds off a catalog.
##
## Only the clean path is asserted here. The negative case -- a glyph dragged into the wrong list
## -- cannot be constructed from GDScript at all: pushing into these arrays from GDScript is
## rejected by Godot's own typed-array check regardless of the element's real type (Actives
## refuses everything, even an ActiveGlyphData). That rejection is incidental rather than the
## guarantee we want, since it also refuses correct pushes, so the wrong-list path is left to be
## confirmed in the editor when the first active glyph is authored.
func check_validate() -> void:
	expect(catalog.Validate(), "the authored catalog should validate clean")
	expect(catalog.AllGlyphs().size() == 1, "validation should not have altered the catalog")
	expect(catalog.Techniques.size() == 1, "validation should not have altered the catalog")


## The reason the catalog exists: the technique layer asks for its capability by trigger, so the
## next airborne technique is an entry in the catalog rather than an edit to the scene.
func check_lookup() -> void:
	expect(catalog.TechniqueWithTrigger(0) == glyph, "the Airborne trigger should resolve to the double jump")
	expect(catalog.TechniqueWithTrigger(1) == null,
		"WallContact has no technique yet and must resolve to null, not to the double jump")
	expect(catalog.TechniqueWithTrigger(2) == null, "HeldInput has no technique yet")
	expect(catalog.TechniqueWithTrigger(3) == null, "Submerged has no technique yet")
	expect(catalog.AllGlyphs().size() == 1, "AllGlyphs should flatten to the one authored glyph, got %d" % catalog.AllGlyphs().size())


func check_seeding() -> void:
	expect(catalog.DefaultSeedPoints == 5, "the catalog should seed 5 points, got %d" % catalog.DefaultSeedPoints)

	expect(seeded.Entries.size() == 1, "seeding should create exactly one entry, got %d" % seeded.Entries.size())
	expect(seeded.PointsFor(glyph) == 5, "the seeded double jump should hold 5 points, got %d" % seeded.PointsFor(glyph))
	expect(seeded.TotalPoints() == 5, "the whole seeded loadout should hold 5 points, got %d" % seeded.TotalPoints())

	# PointsFor sums across entries, so a duplicated entry would read double. Reusing the entry
	# is what keeps seeding idempotent.
	seeded.TrySetPoints(glyph, 0)
	expect(seeded.HasEntry(glyph), "a zero-point allocation still stores an entry")
	expect(seeded.Entries.size() == 1, "zeroing must reuse the entry, not append; got %d" % seeded.Entries.size())
	expect(seeded.PointsFor(glyph) == 0, "a deliberate zero should survive, got %d" % seeded.PointsFor(glyph))

	expect(bare.Catalog == null, "the bare loadout should have no catalog")
	expect(bare.Entries.is_empty(), "a loadout with no catalog must start empty, got %d" % bare.Entries.size())


func verdict() -> void:
	print("TEST GLYPH CATALOG ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)