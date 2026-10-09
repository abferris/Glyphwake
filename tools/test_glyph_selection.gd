extends SceneTree

## The toolbar's slot selection: the number keys reference the bar's slots, a glyph in the
## slot switches the selected skill to that number, and the dial shows the selected glyph. The
## cast input (LMB) fires only the selected skill; techniques are never in the bar and never
## route through the mouse.
##
## The behaviour is asserted off reads of the loadout's own state:
##   1. the default selection is the bar's slot 1 (Terra Strike)
##   2. a glyph in slot 2 (Cinder Shot, the bar's second authored entry) switches the selection
##      to it
##   3. pressing 1 switches back
##   4. a glyph appended at runtime (the way the rune setup menu will fill slots) takes the
##      next empty slot and answers its number
##   5. the wheel steps the equipped slots, skipping empties and wrapping at both edges
##
## The third glyph is built in code and appended to the bar's list at runtime.

const WORLD := "res://Scenes/World.tscn"
const ACTIVE_SCRIPT := "res://Scripts/Glyphs/Active/ActiveGlyphData.cs"
# Long warm-up: while the world's first frames are still catching up, a parsed tap and its
# release 2 ticks later both flush inside one process frame, and the toolbar's idle _Process
# never sees the key held -- the edge is silently missed. Past ~30 ticks the tap and its
# release land in separate process frames and register normally.
const WARM_TICKS := 40

var phase := 0
var tick := 0
var t := 0
var failed := false

var world: Node3D
var player: CharacterBody3D
var loadout: Node
var toolbar: Control
var terra: Resource
var second: Resource


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


func tap_number(key: int) -> void:
	if held.get(key, false):
		return
	held[key] = true
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.pressed = true
	press.echo = false
	Input.parse_input_event(press)
	release_at[key] = tick + 2


func scroll_wheel(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	Input.parse_input_event(ev)


func release_key(key: int) -> void:
	if not held.get(key, false):
		return
	held[key] = false
	var release := InputEventKey.new()
	release.physical_keycode = key
	release.pressed = false
	release.echo = false
	Input.parse_input_event(release)


func _initialize() -> void:
	world = (load(WORLD) as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _physics_process(_delta: float) -> bool:
	tick += 1
	t += 1
	if tick > 2000:
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
		loadout = player.get_node_or_null("Loadout")
		toolbar = player.get_node_or_null("Hud/GlyphHotkeyToolbar")
		if loadout == null or toolbar == null:
			fail("the player's loadout or the toolbar did not resolve")
			report()
			return true
		terra = loadout.SelectedActive
		expect(terra != null and terra.DisplayName == "Terra Strike",
			"the default selection is '%s', expected the bar's slot 1 (Terra Strike)"
				% (terra.DisplayName if terra != null else "null"))
		next_phase()
		return false

	# --- a glyph in slot 2 (Cinder Shot) switches the selection ---
	if phase == 1:
		if t < 4:
			return false
		tap_number(KEY_2)
		next_phase()
		return false

	if phase == 2:
		if t < 4:
			return false
		expect(loadout.SelectedActive != null and loadout.SelectedActive.DisplayName == "Cinder Shot",
			"pressing 2 kept the selection on '%s', expected Cinder Shot (the bar's slot 2)"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		next_phase()
		return false

	# --- pressing 1 switches back ---
	if phase == 3:
		if t < 4:
			return false
		tap_number(KEY_1)
		next_phase()
		return false

	if phase == 4:
		if t < 4:
			return false
		expect(loadout.SelectedActive == terra,
			"pressing 1 switched the selection to '%s', expected Terra Strike"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		next_phase()
		return false

	# --- a glyph appended at runtime takes the next empty slot and answers its number ---
	if phase == 5:
		second = load(ACTIVE_SCRIPT).new()
		second.DisplayName = "Test Active"
		toolbar.Glyphs.append(second)
		next_phase()
		return false

	if phase == 6:
		if t < 4:
			return false
		tap_number(KEY_3)
		next_phase()
		return false

	if phase == 7:
		if t < 4:
			return false
		expect(loadout.SelectedActive == second,
			"pressing 3 with 'Test Active' in the slot kept the selection on '%s'"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		next_phase()
		return false

	# --- the wheel steps the equipped slots, skipping empties and wrapping ---
	if phase == 8:
		if t < 4:
			return false
		tap_number(KEY_1)
		next_phase()
		return false

	if phase == 9:
		if t < 4:
			return false
		expect(loadout.SelectedActive == terra,
			"pressing 1 switched the selection to '%s', expected Terra Strike before the wheel steps"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		scroll_wheel(true)
		next_phase()
		return false

	if phase == 10:
		if t < 4:
			return false
		expect(loadout.SelectedActive != null and loadout.SelectedActive.DisplayName == "Cinder Shot",
			"wheel down from slot 1 stepped to '%s', expected Cinder Shot (the next equipped)"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		scroll_wheel(true)
		next_phase()
		return false

	if phase == 11:
		if t < 4:
			return false
		expect(loadout.SelectedActive == second,
			"wheel down from slot 2 stepped to '%s', expected 'Test Active' (the next equipped)"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		scroll_wheel(true)
		next_phase()
		return false

	if phase == 12:
		if t < 4:
			return false
		expect(loadout.SelectedActive == terra,
			"wheel down from the last slot stepped to '%s', expected the wrap back to Terra Strike"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		scroll_wheel(false)
		next_phase()
		return false

	if phase == 13:
		if t < 4:
			return false
		expect(loadout.SelectedActive == second,
			"wheel up from the first slot stepped to '%s', expected the wrap to 'Test Active'"
				% (loadout.SelectedActive.DisplayName if loadout.SelectedActive != null else "null"))
		print("wheel: down steps right, up steps left, empties skipped, edges wrap")
		report()
		return true

	return false


func report() -> void:
	print("TEST GLYPH SELECTION ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
