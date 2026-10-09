extends SceneTree

## The glyph loadout and the double jump's economics, without a world:
##
##   - points live in a player-owned loadout keyed by resource path, capped by the shared
##     100-point pool
##   - the JumpCount stat reads the number of mid-air jumps the points buy: 1 at activation,
##     +1 every 10 points, 10 at the pool
##   - the height curve: each air jump starts at half the normal jump and caps at twice it
##     over its decade, so further points unlock new jumps rather than growing old ones
##   - TryAirJump is atomic: nothing fired means nothing spent, an out-of-budget or
##     insufficient-stamina attempt refuses, and a free jump (cost 0 at 21+ points) goes
##     through at any stamina
##   - the cost is the glyph's own declaration: the double jump declares stamina, so its
##     spend leaves the stamina pool and never the mana one

const TOL := 0.01
const GLYPH_PATH := "res://Resources/Glyphs/Techniques/DoubleJump.tres"
const NORMAL_JUMP := 1.5

var phase := 0
var ticks := 0
var failed := false
var loadout: Node
var resources: Node
var techniques: Node
var glyph: Resource
var other: Resource


func fail(msg: String) -> void:
	printerr("FAIL: " + msg)
	failed = true


func expect(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func close(a: float, b: float, tol: float = TOL) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	glyph = load(GLYPH_PATH)
	other = load("res://Scripts/Glyphs/Technique/TechniqueGlyphData.cs").new()
	loadout = load("res://Scripts/Glyphs/Framework/GlyphLoadout.cs").new()
	resources = load("res://Scripts/Player/Data/PlayerResources.cs").new()
	techniques = load("res://Scripts/Player/Data/PlayerTechniques.cs").new()
	if glyph == null or other == null or loadout == null or resources == null or techniques == null:
		printerr("FAIL: a glyph script or the DoubleJump resource is missing")
		quit(1)
		return
	techniques.Technique = glyph
	# PlayerTechniques resolves its loadout and resources as named children of its parent body
	# (the Player in the scene), so the code-built trio needs the same shape and names here.
	var body := Node.new()
	body.name = "Body"
	loadout.name = "Loadout"
	resources.name = "Resources"
	techniques.name = "Techniques"
	body.add_child(loadout)
	body.add_child(resources)
	body.add_child(techniques)
	root.call_deferred("add_child", body)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 3:
		return false

	if phase == 0:
		if not loadout.is_inside_tree():
			return false
		check_pool()
		check_counts()
		check_heights()
		# One point is activation; with it the first air jump is half the normal jump and
		# costs the base stamina. Full pools refill both to their max first, so the spend is
		# exact -- and mana, which nothing should touch, stays full.
		expect(loadout.TrySetPoints(glyph, 1), "allocating 1 point should fit the empty pool")
		expect(int(glyph.Costs[0].Resource) == 2,
			"the double jump must declare CostResource.Stamina (2), got %s" % glyph.Costs[0].Resource)
		var h: float = techniques.TryAirJump(0, NORMAL_JUMP)
		expect(h > 0.0, "one air jump should fire at 1 point")
		expect(close(h, 0.75), "first air jump at 1 point should be half the normal jump, got %f" % h)
		expect(close(resources.Stamina, 90.0), "stamina should drop by the base cost 10, got %f" % resources.Stamina)
		expect(close(resources.Mana, 100.0), "the air jump must not touch mana, got %f" % resources.Mana)
		# Out of jumps: the count is 1, so anything past the first refuses and nothing is spent.
		expect(techniques.TryAirJump(1, NORMAL_JUMP) < 0.0, "second air jump must refuse at 1 point")
		expect(techniques.TryAirJump(2, NORMAL_JUMP) < 0.0, "third air jump must refuse at 1 point")
		expect(close(resources.Stamina, 90.0), "a refused air jump must not spend, got %f" % resources.Stamina)
		# Starve the pool: MaxStamina 5 clamps the current value down on the next tick.
		resources.MaxStamina = 5.0
		phase = 1
		return false

	if phase == 1:
		expect(close(resources.Stamina, 5.0), "stamina should clamp to the retuned max 5, got %f" % resources.Stamina)
		expect(not resources.TrySpend(2, 10.0), "TrySpend must refuse a cost the pool cannot pay")
		expect(techniques.TryAirJump(0, NORMAL_JUMP) < 0.0, "air jump must refuse when stamina cannot pay")
		# At 21 points the cost has fallen to 0, so the jump is free at any stamina -- and the
		# first air jump's decade is done, so its height has capped at twice the normal jump.
		expect(loadout.TrySetPoints(glyph, 21), "reallocating 21 points should fit")
		var h: float = techniques.TryAirJump(0, NORMAL_JUMP)
		expect(h > 0.0, "a free jump should fire at any stamina")
		expect(close(h, 3.0), "first air jump at 21 points should have capped at twice the normal jump, got %f" % h)
		expect(close(resources.Stamina, 5.0), "a zero-cost jump must not spend, got %f" % resources.Stamina)
		verdict()
		return true

	return false


func check_pool() -> void:
	expect(not loadout.TrySetPoints(glyph, -1), "a negative allocation must refuse")
	expect(loadout.Entries.size() == 0, "a refused allocation must not create an entry")
	expect(loadout.TrySetPoints(glyph, 0), "a zero allocation is legal and stores the entry")
	expect(not loadout.TrySetPoints(glyph, 101), "an allocation past the 100-point pool must refuse")
	expect(loadout.TrySetPoints(glyph, 100), "sinking the whole pool into one glyph is legal")
	expect(loadout.TotalPoints() == 100, "total points should be 100, got %d" % loadout.TotalPoints())
	expect(loadout.PointsFor(glyph) == 100, "points for the glyph should be 100, got %d" % loadout.PointsFor(glyph))
	# A glyph built in code has no resource path, so it matches by instance -- and it is a
	# different glyph, so the exhausted pool must refuse it.
	expect(not loadout.TrySetPoints(other, 1), "an allocation past the pool must refuse for a second glyph")
	expect(loadout.PointsFor(other) == 0, "a refused glyph should have no points")


func check_counts() -> void:
	# 1 at activation, +1 every 10 points, 10 at the pool: the decade design.
	var cases := {1: 1, 10: 1, 11: 2, 20: 2, 21: 3, 31: 4, 91: 10, 100: 10}
	for points in cases:
		var got: int = techniques.AirJumpCountAt(points)
		expect(got == cases[points], "air jump count at %d points should be %d, got %d" % [points, cases[points], got])
	expect(techniques.AirJumpCountAt(0) == 1, "the count is the glyph's stat; activation is checked separately")


func check_heights() -> void:
	# Each air jump unlocks at half the normal jump and caps at twice it over its decade.
	var cases := {
		[1, 1]: 0.75, [1, 5]: 1.75, [1, 10]: 3.0,
		[2, 11]: 0.75, [2, 20]: 3.0,
		[3, 21]: 0.75, [3, 30]: 3.0,
		[10, 91]: 0.75, [10, 100]: 3.0,
		# Past a jump's decade the height caps: further points buy new jumps, not growth.
		[1, 50]: 3.0, [2, 50]: 3.0,
	}
	for key in cases:
		var got: float = techniques.AirJumpHeightAt(key[0], key[1], NORMAL_JUMP)
		expect(close(got, cases[key]), "air jump %d at %d points should be %f, got %f" % [key[0], key[1], cases[key], got])


func verdict() -> void:
	print("TEST GLYPH LOADOUT ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
