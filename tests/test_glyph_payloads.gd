extends SceneTree

## Glyph attachments: the animation a glyph plays on its caster, and the two scenes an active
## glyph puts into the world.
##
##   - a cast animation whose scene really holds the named clip validates
##   - an AnimationPlayer below the scene root is still found
##   - a wrong clip name is reported rather than silently playing nothing
##   - a scene with no AnimationPlayer is reported
##   - a cast animation with no scene or no clip is "no animation", not broken
##   - an active glyph's CastAnimation / Payload / ImpactPayload survive a save and load
##
## The two negative Validate cases deliberately push Godot errors, so an ERROR: line in the output
## here is expected and is not the verdict. The verdict is the last line.
##
## The test scenes are written to user:// and read back rather than built in memory and used
## directly, because the risk being covered is the clip surviving a save -- a library assembled in
## code and never written to disk says nothing about a scene an artist authored in the editor.

const CAST_ANIM_SCRIPT := "res://Scripts/Glyphs/Framework/GlyphCastAnimation.cs"
const ACTIVE_SCRIPT := "res://Scripts/Glyphs/Active/ActiveGlyphData.cs"

const CAST_OK := "user://test_cast_ok.tscn"
const CAST_NESTED := "user://test_cast_nested.tscn"
const CAST_NO_PLAYER := "user://test_cast_no_player.tscn"
const PAYLOAD := "user://test_payload.tscn"
const IMPACT := "user://test_impact.tscn"
const ACTIVE_TRES := "user://test_active.tres"
const TUNED_TRES := "user://test_cast_tuned.tres"

var failed := false
var cast_ok: PackedScene
var cast_nested: PackedScene
var cast_no_player: PackedScene
var payload: PackedScene
var impact: PackedScene


func fail(msg: String) -> void:
	printerr("FAIL: " + msg)
	failed = true


func expect(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func _physics_process(_delta: float) -> bool:
	# On the first tick rather than in _initialize, so that failing to build the fixtures stops the
	# run before it starts asserting against nulls.
	cast_ok = write_scene(build_cast_scene("Cast Fire", false), CAST_OK)
	cast_nested = write_scene(build_cast_scene("Cast Fire", true), CAST_NESTED)
	cast_no_player = write_scene(Node3D.new(), CAST_NO_PLAYER)
	payload = write_scene(Node3D.new(), PAYLOAD)
	impact = write_scene(Node3D.new(), IMPACT)

	if cast_ok == null or cast_nested == null or cast_no_player == null or payload == null or impact == null:
		fail("the test fixture scenes should all build and save")
		return verdict()

	check_cast_animation()
	check_round_trip()
	return verdict()


## An AnimationPlayer holding one clip. Wrapped in a Node3D when nested, because a scene that had
## to be the player itself would not exercise the depth-first search.
func build_cast_scene(clip_name: String, nested: bool) -> Node:
	var player := AnimationPlayer.new()
	var anim := Animation.new()
	anim.length = 0.5
	var library := AnimationLibrary.new()
	library.add_animation(clip_name, anim)
	player.add_animation_library("", library)

	if not nested:
		return player

	var root := Node3D.new()
	root.add_child(player)
	# pack() silently drops any node whose owner is unset, and a child built in code has owner ==
	# null -- so without this the scene saves as a bare Node3D and the nested case reads as "no
	# AnimationPlayer in the scene" rather than as the fixture bug it is. An editor-authored scene
	# has owners set, which is why this only bites a scene assembled by script.
	player.owner = root
	return root


## Packs a node tree, writes it, and reads it back. Returns null on any failure so a broken
## fixture is reported once rather than as a cascade of confusing assertion failures.
func write_scene(root: Node, path: String) -> PackedScene:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		printerr("FAIL: could not pack %s: %d" % [path, err])
		return null

	err = ResourceSaver.save(packed, path)
	if err != OK:
		printerr("FAIL: could not save %s: %d" % [path, err])
		return null

	var loaded: PackedScene = load(path)
	if loaded == null:
		printerr("FAIL: %s did not load back" % path)
	return loaded


func make_cast(scene: PackedScene, clip: String) -> Resource:
	var anim: Resource = load(CAST_ANIM_SCRIPT).new()
	anim.Scene = scene
	anim.Clip = clip
	return anim


func check_cast_animation() -> void:
	# A clip that is really in the scene validates. This is the whole contract: the scene holds the
	# clip, so the glyph can go on naming it.
	expect(make_cast(cast_ok, "Cast Fire").Validate(),
		"a cast animation naming a clip the scene holds should validate")

	# The player need not be the scene root -- a scene may wrap it in whatever structure suits it.
	expect(make_cast(cast_nested, "Cast Fire").Validate(),
		"an AnimationPlayer below the scene root should still be found")

	# The case the editor cannot catch: Scene accepts any scene, so a typo in the clip name is
	# authorable, and used to mean a cast that silently plays nothing.
	expect(not make_cast(cast_ok, "Cast Fyre").Validate(),
		"a clip the scene does not hold must be reported, not accepted")

	# A scene with no AnimationPlayer at all is the other uncheckable authoring mistake.
	expect(not make_cast(cast_no_player, "Cast Fire").Validate(),
		"a scene with no AnimationPlayer must be reported")

	# Absent is not broken. A glyph with no cast animation casts without one, and the game is first
	# person, so this is the common case rather than a mistake to be told about.
	expect(not load(CAST_ANIM_SCRIPT).new().HasAnimation,
		"a cast animation with no scene or clip has nothing to play")
	expect(not make_cast(null, "Cast Fire").HasAnimation, "a null scene has nothing to play")
	expect(not make_cast(cast_ok, "").HasAnimation, "an empty clip name has nothing to play")
	expect(make_cast(cast_ok, "Cast Fire").HasAnimation, "a scene and a clip is playable")


## The attachments have to survive being authored as a .tres, which is the only way a designer ever
## sets them. Building one in code and reading the fields straight back would pass even if the
## exports did not serialize at all.
func check_round_trip() -> void:
	var active: Resource = load(ACTIVE_SCRIPT).new()
	active.DisplayName = "Fire Blast"
	active.CastAnimation = make_cast(cast_ok, "Cast Fire")
	active.Payload = payload
	active.ImpactPayload = impact

	var err := ResourceSaver.save(active, ACTIVE_TRES)
	expect(err == OK, "the test active glyph should save, got error %d" % err)

	var loaded: Resource = load(ACTIVE_TRES)
	if loaded == null:
		fail("the saved active glyph did not load back")
		return

	expect(loaded.DisplayName == "Fire Blast", "a plain field should survive the round trip")
	expect(loaded.Payload == payload, "the projectile payload should survive the round trip")
	expect(loaded.ImpactPayload == impact,
		"the impact payload should survive the round trip, got %s" % str(loaded.ImpactPayload))
	expect(loaded.CastAnimation != null, "the cast animation should survive the round trip")

	if loaded.CastAnimation != null:
		expect(loaded.CastAnimation.Scene == cast_ok, "the cast animation's scene should survive")
		expect(str(loaded.CastAnimation.Clip) == "Cast Fire", "the cast animation's clip should survive")
		expect(loaded.CastAnimation.Validate(),
			"a cast animation that round-tripped should still validate against its reloaded scene")

	# The blend times are numbers a designer tunes, so they need the same guarantee as the refs.
	var tuned: Resource = load(CAST_ANIM_SCRIPT).new()
	tuned.Scene = cast_ok
	tuned.Clip = "Cast Fire"
	tuned.BlendIn = 0.4
	tuned.BlendOut = 0.05
	ResourceSaver.save(tuned, TUNED_TRES)

	var tuned_back: Resource = load(TUNED_TRES)
	expect(is_equal_approx(tuned_back.BlendIn, 0.4),
		"BlendIn should survive the round trip, got %f" % tuned_back.BlendIn)
	expect(is_equal_approx(tuned_back.BlendOut, 0.05),
		"BlendOut should survive the round trip, got %f" % tuned_back.BlendOut)


func verdict() -> bool:
	print("TEST GLYPH PAYLOADS ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
	return true