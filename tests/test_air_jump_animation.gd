extends SceneTree

## The air-step cast in the live player: the double jump's CastAnimation plays over the
## locomotion tree as a layer, one step per air jump.
##
## The wiring is asserted off the scene's own data (the glyph's CastAnimation resource and the
## cast scene it names), so a retune cannot stale it; the behaviour is asserted off reads of
## the controller's own state:
##
##   1. the cast resource carries 8 variants on 8 distinct keys, and every variant's clip
##      exists in the cast scene's own AnimationPlayer
##   2. the playback layer merged all 8 into the player's library under the cast/ namespace
##   3. the tree root is wrapped with the cast's one-shot, and the locomotion keeps playing
##      underneath while the cast is active
##   4. an air jump fires the step: the default direction (no input held) is Forward, and the
##      first step leads left (no gait behind the standing-still ground jump)
##   5. the next air jump alternates the lead foot
##   6. the cast hands back when the step ends: nothing is playing and locomotion shows through
##
## The exact clip names asserted in 4 and 5 pin the documented defaults (Forward with no input,
## the chain starting left with no stride); changing either is a design change and this test
## says so, the way the redirect test reads the retuned number instead.

const WORLD := "res://Scenes/World.tscn"
const WARM_TICKS := 8

var phase := 0
var tick := 0
var t := 0
var failed := false

var world: Node3D
var player: CharacterBody3D
var glyph: Resource
var cast: Resource

var clips_by_key := {}
var first_clip := ""
var second_clip := ""
var cast_ticks := 0

var held := {}
var release_at := {}


func fail(msg: String) -> void:
	printerr("FAIL: " + msg)
	failed = true


func expect(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func next_phase() -> void:
	phase += 1
	t = 0


func tap(key: int) -> void:
	press_key(key)
	release_at[key] = tick + 2


func press_key(key: int) -> void:
	if held.get(key, false):
		return
	held[key] = true
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = true
	ev.echo = false
	Input.parse_input_event(ev)


func release_key(key: int) -> void:
	if not held.get(key, false):
		return
	held[key] = false
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = false
	ev.echo = false
	Input.parse_input_event(ev)


func _initialize() -> void:
	world = (load(WORLD) as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	if tick > 3000:
		fail("the test ran out of ticks in phase %d" % phase)
		report()
		return true

	for key in release_at.keys():
		if tick >= release_at[key]:
			release_key(key)
			release_at.erase(key)

	if phase == 0:
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		if t < WARM_TICKS:
			return false
		player = world.get_node("Player")
		var loadout: Node = player.get_node_or_null("Loadout")
		if loadout == null or loadout.Entries.is_empty():
			fail("the player's loadout has no entries")
			report()
			return true
		glyph = loadout.Entries[0].Glyph
		cast = glyph.CastAnimation
		expect(cast != null, "the double jump has no CastAnimation; the air step cannot play")
		if cast == null:
			report()
			return true
		next_phase()
		return false

	# --- the wiring: variants resolve to real clips, merged into the player's library ---
	if phase == 1:
		var variants: Array = cast.Variants
		expect(variants.size() == 8,
			"the cast animation has %d variants, expected 8 (four families, two lead feet)" % variants.size())
		var keys := {}
		for v in variants:
			keys[v.Key] = true
			clips_by_key[v.Key] = v.Clip
		expect(keys.size() == variants.size(),
			"the cast variants resolve to %d distinct keys for %d variants" % [keys.size(), variants.size()])

		var scene_inst: Node = (cast.Scene as PackedScene).instantiate()
		var scene_player := find_anim_player(scene_inst)
		expect(scene_player != null, "the cast scene holds no AnimationPlayer")
		if scene_player != null:
			for v in variants:
				expect(scene_player.has_animation(v.Clip),
					"the cast scene has no clip '%s' for key '%s'" % [v.Clip, v.Key])
		scene_inst.free()

		var merged: PackedStringArray = player.get_node("Visual/Anim").get_animation_list()
		for v in variants:
			expect(merged.has("cast/" + v.Clip),
				"the merged library has no 'cast/%s'; the playback layer did not merge it" % v.Clip)
		expect(player.CastClipNames.size() == 11,
			"the player merged %d cast clips, expected 11 (the 8 air steps + the punch + its mirror + Cinder Shot's cast)" % player.CastClipNames.size())

		var tree: AnimationTree = player.get_node("AnimTree")
		var wrapped := tree.tree_root as AnimationNodeBlendTree
		expect(wrapped != null and wrapped.has_node("Cast"),
			"the tree root is not wrapped with the cast's one-shot")
		next_phase()
		return false

	# --- points to the full pool, then the ground jump on dry land ---
	if phase == 2:
		var loadout: Node = player.get_node("Loadout")
		# The pool is shared: the seeding gave the other glyphs points too, so they are zeroed
		# first -- sinking the whole pool into one technique is legal only with the rest at 0.
		# A technique must always be usable: its activation is its own trigger (Space here),
		# never the mouse, so the selected skill in the bar never gates this.
		for entry in loadout.Entries:
			if entry.Glyph != null and entry.Glyph != glyph:
				loadout.TrySetPoints(entry.Glyph, 0)
		loadout.TrySetPoints(glyph, 100)
		player.global_position = find_ground() + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO
		player.Jump(0.0)
		next_phase()
		return false

	if phase == 3:
		if t < 20:
			return false
		tap(KEY_SPACE)
		next_phase()
		return false

	# --- airborne past the spike, then the first air jump ---
	if phase == 4:
		if player.is_on_floor():
			if t > 100:
				fail("the ground jump never lifted the body")
				next_phase()
			return false
		if player.velocity.y > 0.5:
			return false
		tap(KEY_SPACE)
		next_phase()
		return false

	# --- the first air jump fires the step ---
	if phase == 5:
		if player.CastState == "":
			if t > 30:
				fail("no cast fired on the air jump within 30 ticks")
				next_phase()
			return false
		first_clip = player.CastState
		expect(clips_by_key.values().has(first_clip),
			"the air jump played '%s', which is not one of the cast scene's clips" % first_clip)
		# Every air step plays the forward variant (direction is body tilt, not the clip);
		# with no gait behind the standing-still ground jump the chain starts on the left.
		expect(first_clip == "Air Step Forward L",
			"the first step played '%s', expected 'Air Step Forward L' (no input, no stride)" % first_clip)
		expect(player.AnimationState == "Jumping Up",
			"the locomotion stopped playing underneath the cast: %s" % player.AnimationState)
		next_phase()
		return false

	# --- the second air jump alternates the lead foot ---
	if phase == 6:
		if t < 12:
			return false
		if player.is_on_floor():
			fail("the body landed before the second air jump; the arc is too short to step twice")
			report()
			return true
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 7:
		if player.CastState == "" or player.CastState == first_clip:
			if t > 30:
				fail("the second air jump did not switch the step (playing '%s', was '%s')"
					% [player.CastState, first_clip])
				next_phase()
			return false
		second_clip = player.CastState
		expect(second_clip.ends_with(" R"),
			"the second step played '%s', expected the lead foot to alternate to R" % second_clip)
		next_phase()
		return false

	# --- the cast hands back when the step ends ---
	if phase == 8:
		if player.CastState != "":
			if t > 300:
				fail("the cast never handed back; the step is still playing after 5 s")
				next_phase()
			cast_ticks += 1
			return false
		expect(cast_ticks > 0, "the cast was never seen playing before it handed back")
		expect(player.AnimationState != "",
			"locomotion did not resume after the cast handed back")
		print("air steps: '%s' then '%s', cast held %d ticks, back to '%s'"
			% [first_clip, second_clip, cast_ticks, player.AnimationState])
		report()
		return true

	return false


func find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := find_anim_player(c)
		if found != null:
			return found
	return null


func find_ground() -> Vector3:
	var surface: float = world.get_node("WaterZone").WaterSurfaceY
	var ss := player.get_world_3d().direct_space_state
	var found := Vector3.ZERO
	var z := -2000
	while z <= 2000 and found == Vector3.ZERO:
		var x := -2000
		while x <= 2000:
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, surface + 60, z), Vector3(x, surface - 60, z))
			q.exclude = [player.get_rid()]
			var hit := ss.intersect_ray(q)
			if hit.has("position"):
				var hy: float = hit["position"].y
				if hy > surface + 3.0 and hy < surface + 40.0:
					found = Vector3(x, hy, z)
					break
			x += 50
		z += 50
	if found == Vector3.ZERO:
		fail("no island ground found above the waterline")
		report()
		quit(1)
	return found


func report() -> void:
	print("TEST AIR JUMP ANIMATION ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
