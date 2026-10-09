extends SceneTree

## The Cinder Shot active glyph: the first projectile, with the two-handed gather-and-push cast.
##
##   1. the catalog's active list holds Cinder Shot: Inferno, the Kindling school, a Projectile
##      target, an Impulse cast, and a cast animation whose scene really holds the "Cinder Shot"
##      clip -- upper-body tracks only, which is what leaves locomotion playing underneath
##   2. the payload scene instantiates and carries the shot payload's script
##   3. the damage scales linearly with levels: the base at activation, +5 per point past it
##   4. LMB fires the cast: the shot spawns between both hands and RIDES their midpoint while
##      the cast gathers, then is pushed forwards at the push and damages a dummy sitting on
##      the aim ray, once, then frees itself
##   5. the shot is affected by gravity: fired at the sky it rises, peaks, and falls, then dies
##      in the terrain
##
## The dummy rides the player collision layer (2) and the shot's TargetMask is retuned at
## runtime the way a menu will; the default mask is the World layer, so an unaugmented shot
## resolves in the terrain and nowhere else.

const WORLD := "res://Scenes/World.tscn"
const WARM_TICKS := 40
const SHOT_RANGE := 3.0
const UP_PITCH_DEG := 85.0
const BASE_DAMAGE := 10.0
const PER_POINT := 5.0
const FALL_M := 0.5
# The ride tolerance is loose because the reads race: the test reads the hands' midpoint off
# the skeleton's current pose while the shot's position is the payload's last physics-tick
# write, and during the gather the hands move ~0.05-0.09 m per tick. A shot that had stopped
# riding would sit at the right hand or at the sides, 0.3-0.5 m off.
const RIDE_M := 0.15
const RIDE_TICKS := 12

var phase := 0
var tick := 0
var t := 0
var failed := false

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var glyph: Resource
var loadout: Node
var shot: Node
var dummy: Node
var peak_y := 0.0
var last_y := 0.0
var fell := false
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
		camera = player.get_node_or_null("Head/Camera3D")
		loadout = player.get_node_or_null("Loadout")
		var actives: Node = player.get_node_or_null("Actives")
		if actives == null or loadout == null or camera == null:
			fail("the player has no Actives node, no Loadout, or no head camera")
			report()
			return true
		glyph = find_glyph(loadout)
		if glyph == null:
			fail("the catalog's active list has no Cinder Shot")
			report()
			return true

		expect(glyph.DisplayName == "Cinder Shot",
			"the glyph is '%s', expected Cinder Shot" % glyph.DisplayName)
		expect(glyph.Elements.has(1), "Cinder Shot has no Inferno element (1)")
		expect(glyph.School == 0, "Cinder Shot is not the Kindling school (0)")
		expect(glyph.TargetType == 2, "Cinder Shot is not a Projectile target (2)")
		expect(glyph.CastMode == 0, "Cinder Shot is not an Impulse cast (0)")
		expect(glyph.CastAnimation != null, "Cinder Shot has no cast animation")
		if glyph.CastAnimation != null:
			expect(glyph.CastAnimation.Validate(),
				"the Cinder Shot cast should validate against its scene")
			var cast_inst: Node = (glyph.CastAnimation.Scene as PackedScene).instantiate()
			var cast_player := find_anim_player(cast_inst)
			expect(cast_player != null, "the cast scene holds no AnimationPlayer")
			if cast_player != null:
				expect(cast_player.has_animation("Cinder Shot"),
					"the cast scene has no clip 'Cinder Shot'")
				var anim := cast_player.get_animation("Cinder Shot")
				expect(absf(anim.length - 0.5) < 0.01,
					"the cast clip is %.3f s, expected ~0.5" % anim.length)
				var track_count := anim.get_track_count()
				expect(track_count > 0, "the cast clip has no tracks")
				for i in range(track_count):
					var p := anim.track_get_path(i)
					expect(p.get_subname_count() == 1,
						"cast track %d is not a bone track: %s" % [i, p])
					if p.get_subname_count() == 1:
						var bone := str(p.get_subname(0))
						expect(not bone.contains("Leg") and not bone.contains("Foot"),
							"cast track %d animates a leg ('%s'): the cast must leave locomotion playing" % [i, bone])
			cast_inst.free()
		expect(glyph.Payload != null, "Cinder Shot has no payload scene")
		if glyph.Payload != null:
			var payload: Node = glyph.Payload.instantiate()
			expect(str(payload.get_script().resource_path).ends_with("CinderShotPayload.cs"),
				"the payload scene's script is %s, expected the shot payload" % payload.get_script().resource_path)
			payload.free()
		# The scaling is the glyph's own curve, read straight off the data: the base at
		# activation, +5 per point past it, linear.
		expect(is_equal_approx(glyph.StatAt(0, 1), BASE_DAMAGE),
			"damage at 1 point is %.2f, expected the %.1f base" % [glyph.StatAt(0, 1), BASE_DAMAGE])
		expect(is_equal_approx(glyph.StatAt(0, 2), BASE_DAMAGE + PER_POINT),
			"damage at 2 points is %.2f, expected %.1f" % [glyph.StatAt(0, 2), BASE_DAMAGE + PER_POINT])
		expect(is_equal_approx(glyph.StatAt(0, 3), BASE_DAMAGE + PER_POINT * 2.0),
			"damage at 3 points is %.2f, expected %.1f" % [glyph.StatAt(0, 3), BASE_DAMAGE + PER_POINT * 2.0])
		expect(is_equal_approx(glyph.StatAt(0, 10), BASE_DAMAGE + PER_POINT * 9.0),
			"damage at 10 points is %.2f, expected %.1f" % [glyph.StatAt(0, 10), BASE_DAMAGE + PER_POINT * 9.0])

		# The cast damage the body's own path returns: retune to one point so the read is the
		# clean base, the way a menu will; the test override hands the glyph directly.
		expect(loadout.TrySetPoints(glyph, 1), "the loadout refused one point on Cinder Shot")
		actives.Active = glyph

		# The dummy sits on the aim ray: the camera's centre -- the reticule is drawn there --
		# SHOT_RANGE out.
		spawn_dummy(camera.global_position + -camera.global_transform.basis.z * SHOT_RANGE)
		next_phase()
		return false

	if phase == 1:
		if t < 10:
			return false
		tap_mouse()
		next_phase()
		return false

	if phase == 2:
		if shot == null:
			shot = find_node(world, "CinderShot")
		if shot == null:
			if t > 30:
				fail("no shot spawned on LMB within 30 ticks")
				next_phase()
			return false
		# Retune the mask the way a menu will: the world plus the dummy's layer, live, in flight.
		shot.TargetMask = 3
		next_phase()
		return false

	# --- the ride: the shot parks on the hands' midpoint while the cast gathers ---
	if phase == 3:
		if shot == null or not is_instance_valid(shot):
			fail("the shot disappeared before the push")
			next_phase()
			return true
		if player.CastState != "Cinder Shot":
			fail("the cast played '%s', expected 'Cinder Shot'" % player.CastState)
		if t < RIDE_TICKS:
			var mid: Vector3 = hands_midpoint()
			var d: float = (shot.global_position - mid).length()
			expect(d < RIDE_M,
				"the shot sat %.3f m from the hands' midpoint while the cast gathered" % d)
			return false
		next_phase()
		return false

	if phase == 4:
		if shot != null and is_instance_valid(shot):
			return false
		# The free read races the payload's own end-of-frame cleanup; wait out a short grace
		# before reading the assertions off it.
		if t < 3:
			return false
		if dummy == null:
			fail("the damage dummy disappeared")
			report()
			return true
		expect(dummy.hits == 1,
			"the dummy took %d hits, expected exactly 1 (one shot, one contact)" % dummy.hits)
		expect(is_equal_approx(dummy.last_amount, BASE_DAMAGE),
			"the dummy took %.2f damage, expected the %.1f base" % [dummy.last_amount, BASE_DAMAGE])
		print("shot: dummy took %.1f damage from %s" % [dummy.last_amount, dummy.last_direction])
		next_phase()
		return false

	# --- the gravity read: fired at the sky, the arc rises, peaks, and falls ---
	if phase == 5:
		if t < 10:
			return false
		camera.LookPitch = deg_to_rad(UP_PITCH_DEG)
		peak_y = 0.0
		last_y = 0.0
		fell = false
		tap_mouse()
		next_phase()
		return false

	if phase == 6:
		if shot == null:
			shot = find_node(world, "CinderShot")
		if shot != null and is_instance_valid(shot):
			last_y = shot.global_position.y
			peak_y = maxf(peak_y, last_y)
			if peak_y - last_y > FALL_M:
				fell = true
			return false
		# The free read races the payload's own end-of-frame cleanup; wait out a short grace
		# before reading the assertions off it.
		if t < 3:
			return false
		expect(fell, "the shot never fell after its peak: gravity is not acting on it")
		expect(dummy.hits == 1,
			"the sky shot took %d extra hits on the dummy, expected none (it flew past it)" % (dummy.hits - 1))
		print("sky shot: peaked at %.2f m, fell to %.2f m, freed itself" % [peak_y, last_y])
		report()
		return true

	return false


func hands_midpoint() -> Vector3:
	var skeleton: Skeleton3D = player.get_node("Visual/Skeleton3D")
	var lh: int = skeleton.find_bone("LeftHand")
	var rh: int = skeleton.find_bone("RightHand")
	var l: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(lh)).origin
	var r: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(rh)).origin
	return (l + r) * 0.5


func spawn_dummy(at: Vector3) -> void:
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
	box.size = Vector3(0.6, 0.8, 0.6)
	shape.shape = box
	dummy.add_child(shape)
	world.add_child(dummy)
	dummy.global_position = at


func find_glyph(loadout: Node) -> Resource:
	var catalog: Resource = loadout.Catalog
	if catalog == null:
		return null
	for active in catalog.Actives:
		if active != null and active.DisplayName == "Cinder Shot":
			return active
	return null


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


func report() -> void:
	print("TEST CINDER SHOT ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
