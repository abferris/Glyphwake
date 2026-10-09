extends SceneTree

## The Terra Strike active glyph: the first active cast, and the payload pattern behind it.
##
## The wiring is asserted off the scene's own data, so a retune cannot stale it; the behaviour
## off reads of the controller's and payload's own state:
##
##   1. the catalog's active is Terra Strike: display name, icon, and a CastAnimation whose
##      scene really holds the "Terra Strike" clip (and the left-arm mirror under its variant)
##   2. the punch clip is ~0.5 s (the user's spec number) and upper-body only: no leg track,
##      which is what leaves locomotion playing underneath a cast
##   3. the playback layer merged the punch and its mirror into the cast library alongside
##      the air steps, and the tree is wrapped with the cast's one-shot
##   4. LMB fires the punch on dry land: CastState "Terra Strike", locomotion underneath, and
##      the cast hands back when the clip ends
##   5. the payload spawned and freed itself with the cast (the fist's life is the cast's)
##   6. the strike damages a dummy in front of the caster, once: the hit window, the mask, and
##      the one-hit-per-body-per-cast rule all in one read
##   7. the punch also fires mid-air: the spec only requires "not grounded"
##
## The dummy rides the player collision layer (2) and the payload's TargetMask is set at runtime,
## the way a menu will; the default mask hits nothing, because no enemy layer exists yet.

const WORLD := "res://Scenes/World.tscn"
const WARM_TICKS := 8

# The fist's measured reach in player space (this test's own window prints): the rear-right
# straight drives the fist from the raised guard to the reticle at x ~0 (dead ahead), reaching
# player-local (~-0.12, ~-0.08, ~-0.33) at full extension. NOTE: the in-game rig compresses
# the bare-Scene probe's heights (probe hand ~+1.34) onto a low local origin, so the box sits
# low, on the printed strike line -- read the strike=/dummy= prints to re-place if it moves.
const DUMMY_OFFSET := Vector3(0.0, 0.0, -0.3)
const DUMMY_HALF := Vector3(0.25, 0.3, 0.35)

var phase := 0
var tick := 0
var t := 0
var failed := false

var world: Node3D
var player: CharacterBody3D
var glyph: Resource
var cast: Resource
var payload: Node
var dummy: Node
var cast_started_at := 0
var mouse_seen := false

var mouse_release_at := -1


func fail(msg: String) -> void:
	printerr("FAIL: " + msg)
	failed = true


func expect(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func next_phase() -> void:
	phase += 1
	t = 0


func tap_mouse() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	mouse_release_at = tick + 2


func release_mouse() -> void:
	if mouse_release_at < 0:
		return
	mouse_release_at = -1
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
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

	release_mouse()

	if phase == 0:
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		if t < WARM_TICKS:
			return false
		player = world.get_node("Player")
		var actives: Node = player.get_node_or_null("Actives")
		if actives == null:
			fail("the player has no Actives node")
			report()
			return true
		glyph = actives.Active
		if glyph == null:
			fail("the player's active did not resolve from the catalog")
			report()
			return true
		cast = glyph.CastAnimation
		expect(glyph.DisplayName == "Terra Strike",
			"the resolved active is '%s', expected Terra Strike" % glyph.DisplayName)
		expect(glyph.Icon != null, "Terra Strike has no icon")
		expect(cast != null and cast.HasAnimation, "Terra Strike has no cast animation")
		if cast == null or not cast.HasAnimation:
			report()
			return true
		next_phase()
		return false

	# --- the punch clip: the spec's length, upper-body tracks only ---
	if phase == 1:
		expect(cast.Validate(), "the punch cast should validate against its scene")
		var scene_inst: Node = (cast.Scene as PackedScene).instantiate()
		var scene_player := find_anim_player(scene_inst)
		expect(scene_player != null, "the punch scene holds no AnimationPlayer")
		if scene_player != null:
			expect(scene_player.has_animation("Terra Strike"),
				"the punch scene has no clip 'Terra Strike'")
			var anim := scene_player.get_animation("Terra Strike")
			expect(absf(anim.length - 0.5) < 0.01,
				"the punch clip is %.3f s, expected ~0.5 (the spec's number)" % anim.length)
			var track_count := anim.get_track_count()
			expect(track_count > 0, "the punch clip has no tracks")
			for i in range(track_count):
				var p := anim.track_get_path(i)
				expect(p.get_subname_count() == 1,
					"punch track %d is not a bone track: %s" % [i, p])
				if p.get_subname_count() == 1:
					var bone := str(p.get_subname(0))
					expect(not bone.contains("Leg") and not bone.contains("Foot"),
						"punch track %d animates a leg ('%s'): the punch must leave locomotion playing" % [i, bone])
			expect(scene_player.has_animation("Terra Strike L"),
				"the punch scene has no mirror clip 'Terra Strike L' for the left-arm variant")
		scene_inst.free()

		var merged: PackedStringArray = player.get_node("Visual/Anim").get_animation_list()
		expect(merged.has("cast/Terra Strike"),
			"the merged library has no 'cast/Terra Strike'; the playback layer did not merge it")
		expect(merged.has("cast/Terra Strike L"),
			"the merged library has no 'cast/Terra Strike L'; the left-arm variant did not merge")
		expect(player.CastClipNames.size() == 11,
			"the player merged %d cast clips, expected 11 (8 air steps + the punch + its mirror + Cinder Shot's cast)" % player.CastClipNames.size())
		var tree: AnimationTree = player.get_node("AnimTree")
		var wrapped := tree.tree_root as AnimationNodeBlendTree
		expect(wrapped != null and wrapped.has_node("Cast"),
			"the tree root is not wrapped with the cast's one-shot")
		next_phase()
		return false

	# --- on dry land, fire the punch ---
	if phase == 2:
		if t < 10:
			return false
		player.global_position = find_ground() + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO
		player.Jump(0.0)
		next_phase()
		return false

	if phase == 3:
		if t < 20:
			return false
		spawn_dummy()
		cast_started_at = tick
		tap_mouse()
		next_phase()
		return false

	# --- the cast fired: the clip, the locomotion underneath ---
	if phase == 4:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			mouse_seen = true
		if player.CastState == "":
			if t > 30:
				fail("no cast fired on LMB within 30 ticks (mouse press seen: %s)" % mouse_seen)
				next_phase()
			return false
		expect(mouse_seen,
			"the cast fired but the parsed mouse press never reached Input.is_mouse_button_pressed")
		expect(player.CastState == "Terra Strike",
			"the punch played '%s', expected 'Terra Strike'" % player.CastState)
		expect(player.AnimationState != "",
			"locomotion stopped playing underneath the punch")
		next_phase()
		return false

	# --- the payload on its clock: spawned, masked, riding the hand through the punch ---
	if phase == 5:
		if t == 1:
			payload = find_node(world, "TerraFist")
			expect(payload != null, "the punch spawned no TerraFist payload")
			if payload == null:
				report()
				return true
			# The dummy rides the player layer; the payload's mask is retuned the way a menu
			# will, live, before the hit window opens.
			payload.TargetMask = 2
		if t > 1 and t <= 40 and is_instance_valid(payload):
			# The positions print so a placement miss can be read off the run rather than
			# guessed at. The payload frees itself at its own clock's end, so the node is
			# only probed while the cast is up.
			var strike := find_node(payload, "StrikeArea") as Node3D
			if t == 2:
				expect(strike != null,
					"the payload built no StrikeArea")
			if strike != null:
				print("tick %d strike=%s dummy=%s hits=%d" % [t, strike.global_position,
					dummy.global_position, dummy.hits])
		if player.CastState != "":
			return false
		if t < 5:
			# The payload frees on its own clock, within a tick of the animation's end; the
			# grace stops the read from racing it.
			return false
		expect(find_node(world, "TerraFist") == null,
			"the payload outlived its cast; the fist did not free itself")
		if dummy == null:
			fail("the damage dummy disappeared")
			report()
			return true
		expect(dummy.hits == 1,
			"the dummy took %d hits, expected exactly 1 (the window is once per body per cast)" % dummy.hits)
		expect(is_equal_approx(dummy.last_amount, 10.0),
			"the dummy took %.2f damage, expected the glyph's 10.0 placeholder" % dummy.last_amount)
		print("punch: cast %d ticks, dummy took %.1f damage from %s"
			% [tick - cast_started_at, dummy.last_amount, dummy.last_direction])
		next_phase()
		return false

	# --- the punch also fires mid-air ---
	if phase == 6:
		if t < 20:
			return false
		var space := InputEventKey.new()
		space.physical_keycode = KEY_SPACE
		space.pressed = true
		Input.parse_input_event(space)
		next_phase()
		return false

	if phase == 7:
		if player.is_on_floor():
			if t > 100:
				fail("the jump never lifted the body")
				report()
				return true
			return false
		if player.velocity.y > 0.5:
			return false
		var space := InputEventKey.new()
		space.physical_keycode = KEY_SPACE
		space.pressed = false
		Input.parse_input_event(space)
		tap_mouse()
		next_phase()
		return false

	if phase == 8:
		if player.CastState == "":
			if t > 30:
				fail("no cast fired on the mid-air LMB within 30 ticks")
				next_phase()
			return false
		expect(player.CastState == "Terra Strike",
			"the mid-air punch played '%s', expected 'Terra Strike'" % player.CastState)
		next_phase()
		return false

	if phase == 9:
		if player.CastState != "":
			if t > 300:
				fail("the mid-air punch never handed back")
				report()
				return true
			return false
		expect(dummy.hits == 1,
			"the dummy took %d hits by the end, expected 1: a fresh payload's default mask hits nothing"
				% dummy.hits)
		print("mid-air punch fired and handed back")
		report()
		return true

	return false


func spawn_dummy() -> void:
	var script := GDScript.new()
	script.source_code = """
extends StaticBody3D
var hits := 0
var last_amount := 0.0
var last_direction := Vector3.ZERO
func apply_damage(amount: float, direction: Vector3) -> void:
	hits += 1
	last_amount = amount
	last_direction = direction
"""
	script.reload()
	dummy = script.new()
	dummy.collision_layer = 2
	dummy.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = DUMMY_HALF * 2.0
	shape.shape = box
	dummy.add_child(shape)
	world.add_child(dummy)
	dummy.global_position = player.global_position + DUMMY_OFFSET


func find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := find_anim_player(c)
		if found != null:
			return found
	return null


func find_node(n: Node, node_name: String) -> Node:
	if n.name == node_name:
		return n
	for c in n.get_children():
		var found := find_node(c, node_name)
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
	print("TEST TERRA STRIKE ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
