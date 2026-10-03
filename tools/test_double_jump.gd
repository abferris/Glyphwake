extends SceneTree

## The double jump in the live player, on real Space taps against the World scene.
##
## The controller's ground jump is technique-independent; the technique is what lets a
## mid-air press produce a second upward spike. Everything asserted is measured off the arc
## and read from the scene's own data (the loadout entry's points, the glyph's cost and the
## body's JumpHeight), so retuning any of them cannot stale the test:
##
##   1. a mid-air Space tap produces a second upward spike at the air-jump height, not the
##      ground-jump height
##   2. the mana dropped by the glyph's cost at the loadout's points
##   3. a third tap does nothing while the points only buy one air jump
##   4. landing hands the chain back: after touching down the air jump works again
##   5. zero points refuse the air jump but not the ground jump
##   6. the air jump redirects the horizontal velocity toward the held input without
##      gaining or losing speed

const GRAVITY := 9.81
const TOL := 0.01
const FALL_VY := -1.5   # past the apex of either jump, still well above landing
const WARM_TICKS := 8   # is_on_floor() survives the teleport otherwise
const SPIKE_GUARD := 0.35  # gravity a tick or two of descent is allowed to have taken

var phase := 0
var tick := 0
var t := 0
var failed := false

var world: Node3D
var player: CharacterBody3D
var loadout: Node
var glyph: Resource

var jump_height := 1.5
var pts := 0
var amount := 0.0
var per_point := 0.0

var max_vy := 0.0
var seen_spike := false
var mana_before := 0.0
var hv_pre := Vector2.ZERO

var held := {}
var release_at := {}


func fail(msg: String) -> void:
	printerr("FAIL: " + msg)
	failed = true


func next_phase() -> void:
	phase += 1
	t = 0
	max_vy = 0.0
	seen_spike = false


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
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
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
		if t < 8:
			# The terrain colliders are not in the physics space state on the first tick
			# after the scene enters the tree; the ground search needs a few frames first.
			return false
		player = world.get_node("Player")
		loadout = player.get_node_or_null("Loadout")
		if player.get_node_or_null("Resources") == null or loadout == null \
				or player.get_node_or_null("Techniques") == null:
			fail("the player is missing its glyph runtime (Loadout / Resources / Techniques)")
			report()
			return true
		read_data()
		find_ground()
		next_phase()
		return false

	# --- ground jump, then the arc it produces ---
	if phase == 1:
		if t <= WARM_TICKS:
			return false
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 2:
		max_vy = maxf(max_vy, player.velocity.y)
		if player.velocity.y > 3.0:
			seen_spike = true
		if not seen_spike or player.velocity.y >= 0.0:
			if t > 200:
				fail("the ground jump never spiked or never came down")
				next_phase()
			return false
		var expected := ground_vy()
		if max_vy < expected - SPIKE_GUARD:
			fail("ground jump peaked at %f, below the %f the body's JumpHeight produces" % [max_vy, expected])
		next_phase()
		return false

	# --- falling, then the first air jump ---
	if phase == 3:
		if player.velocity.y > FALL_VY:
			return false
		mana_before = resources().Mana
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 4:
		max_vy = maxf(max_vy, player.velocity.y)
		if player.velocity.y > 3.0:
			seen_spike = true
		if t == 2:
			var dropped: float = mana_before - resources().Mana
			var cost := cost_at()
			if dropped < cost - 0.5 or dropped > cost + 0.05:
				fail("the air jump spent %f mana, expected the glyph's cost %f (regen aside)" % [dropped, cost])
		if not seen_spike or player.velocity.y >= 0.0:
			if t > 200:
				fail("the air jump never spiked or never came down")
				next_phase()
			return false
		var expected := air_vy(1)
		if max_vy < expected - SPIKE_GUARD:
			fail("air jump peaked at %f, below the %f its points buy -- or only the ground jump fired" % [max_vy, expected])
		next_phase()
		return false

	# --- a third tap with only one air jump bought: nothing may happen ---
	if phase == 5:
		if player.velocity.y > FALL_VY:
			return false
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 6:
		if player.velocity.y > -0.5:
			fail("a third tap produced an upward spike at vy=%f with only one air jump bought" % player.velocity.y)
		if t >= 15:
			next_phase()
		return false

	# --- landing hands the chain back ---
	if phase == 7:
		if not player.is_on_floor():
			if t > 200:
				fail("never landed within 200 ticks after the air jumps")
				next_phase()
			return false
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 8:
		max_vy = maxf(max_vy, player.velocity.y)
		if player.velocity.y > 3.0:
			seen_spike = true
		if not seen_spike or player.velocity.y >= 0.0:
			if t > 200:
				fail("the ground jump never spiked or never came down after landing")
				next_phase()
			return false
		var expected := ground_vy()
		if max_vy < expected - SPIKE_GUARD:
			fail("ground jump peaked at %f after landing" % max_vy)
		next_phase()
		return false

	if phase == 9:
		if player.velocity.y > FALL_VY:
			return false
		mana_before = resources().Mana
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 10:
		max_vy = maxf(max_vy, player.velocity.y)
		if player.velocity.y > 3.0:
			seen_spike = true
		if t == 2:
			if mana_before - resources().Mana < cost_at() - 0.5:
				fail("the air jump after landing spent less than its cost")
		if not seen_spike or player.velocity.y >= 0.0:
			if t > 200:
				fail("the air jump after landing never spiked or never came down")
				next_phase()
			return false
		var expected := air_vy(1)
		if max_vy < expected - SPIKE_GUARD:
			fail("air jump peaked at %f after landing; the chain was not handed back" % max_vy)
		next_phase()
		return false

	# --- zero points refuse the air jump, not the ground jump ---
	if phase == 11:
		if not player.is_on_floor():
			if t > 200:
				fail("never landed within 200 ticks")
				next_phase()
			return false
		loadout.TrySetPoints(glyph, 0)
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 12:
		max_vy = maxf(max_vy, player.velocity.y)
		if player.velocity.y >= 0.0:
			return false
		if max_vy < ground_vy() - SPIKE_GUARD:
			fail("ground jump peaked at %f with the glyph at zero points" % max_vy)
		next_phase()
		return false

	if phase == 13:
		if player.velocity.y > FALL_VY:
			return false
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 14:
		if player.velocity.y > -0.5:
			fail("an air jump fired at vy=%f with zero points in the glyph" % player.velocity.y)
		if t >= 15:
			next_phase()
		return false

	# --- the redirect: an arc built holding W, swung toward D, at unchanged speed ---
	if phase == 15:
		if not player.is_on_floor():
			if t > 200:
				fail("never landed within 200 ticks")
				next_phase()
			return false
		loadout.TrySetPoints(glyph, pts)
		press_key(KEY_W)
		next_phase()
		return false

	if phase == 16:
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		if speed < 4.8:
			if t > 90:
				fail("grounded run never reached 4.8 m/s; at %f" % speed)
				next_phase()
			return false
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 17:
		if player.velocity.y > FALL_VY:
			return false
		hv_pre = Vector2(player.velocity.x, player.velocity.z)
		release_key(KEY_W)
		press_key(KEY_D)
		tap(KEY_SPACE)
		next_phase()
		return false

	if phase == 18:
		if t == 2:
			var hv_post := Vector2(player.velocity.x, player.velocity.z)
			var turned := angle_between(hv_pre, hv_post)
			# Redirect 0.5 of the way through a right angle is a 45 degree swing.
			if absf(turned - 45.0) > 6.0:
				fail("the air jump turned the arc %f degrees, expected 45" % turned)
			if absf(hv_post.length() - hv_pre.length()) > 0.25:
				fail("the redirect changed the speed from %f to %f" % [hv_pre.length(), hv_post.length()])
			if player.velocity.y < air_vy(1) - SPIKE_GUARD:
				fail("the redirect tap never jumped: vy=%f" % player.velocity.y)
			release_key(KEY_D)
			next_phase()
			return false
		return false

	report()
	return true


func read_data() -> void:
	jump_height = player.JumpHeight
	var entries: Array = loadout.Entries
	if entries.is_empty():
		fail("the player's loadout has no entries")
		report()
		quit(1)
		return
	pts = entries[0].Points
	glyph = entries[0].Glyph
	amount = glyph.Costs[0].Amount
	per_point = glyph.Costs[0].AmountPerPoint
	print("loadout: %d points in %s, cost %f + %f/pt, JumpHeight %f" %
		[pts, glyph.DisplayName, amount, per_point, jump_height])
	if pts < 1:
		fail("the scene's loadout has %d points; the behavioral pass needs an activated glyph" % pts)


func resources() -> Node:
	return player.get_node("Resources")


func ground_vy() -> float:
	return sqrt(2.0 * GRAVITY * jump_height)


func air_height(index: int) -> float:
	# The same curve PlayerTechniques.AirJumpHeightAt implements, rebuilt from the scene's
	# own numbers so a retune cannot stale the expectation.
	var unlock := 10.0 * (index - 1) + 1.0
	var ramp := clampf((pts - unlock) / 9.0, 0.0, 1.0)
	return jump_height * lerpf(0.5, 2.0, ramp)


func air_vy(index: int) -> float:
	return sqrt(2.0 * GRAVITY * air_height(index))


func cost_at() -> float:
	return maxf(0.0, amount + per_point * (pts - 1))


func angle_between(a: Vector2, b: Vector2) -> float:
	if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(absf(a.normalized().angle_to(b.normalized())))


func find_ground() -> void:
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
		return
	player.global_position = found + Vector3(0, 0.5, 0)
	player.velocity = Vector3.ZERO
	# Clearing velocity does not clear the controller's own _verticalVelocity; Jump(0) is the
	# public way to zero it.
	player.Jump(0.0)
	print("ground at ", found)


func report() -> void:
	print("TEST DOUBLE JUMP ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
