extends SceneTree

## Why holding a key turns a cliff jump into a crawl: the same drop twice, with and without input.
##
## probe_cliff.gd already showed that a body falling through open air over land reports
## Mode = EnteringWater for the entire fall, with wading and shallow-floor both correctly false.
## That does not look wrong on its own, because in open air the float is fully disengaged
## (engage = 0), so the fall limit opens back up to MaxFallSpeed and free fall happens normally.
##
## The problem is WHICH code is running. EnteringWater routes to SimulateSwim, not
## SimulateGround, so a body in open air is handed to the surface-swim simulation. Two things in
## that function misbehave when there is no water there:
##
##   - The dive charge (PlayerController.cs:439-448). diveHold needs only input.Y > 0 and the
##     camera looking more than DiveLookDownDeg down. It never checks whether there is any water
##     anywhere near. After DiveDelay seconds it does MoveToward(_verticalVelocity, -diveSpeed),
##     and diveSpeed is SwimSpeed = 3 m/s. So holding W while looking down in mid-air yanks a
##     -27 m/s fall up to -3 m/s. That is "the max fall speed is now low again".
##   - Horizontal movement runs at SurfaceSwimSpeed via SwimAcceleration instead of MoveSpeed via
##     Acceleration, so the arrows steer differently in the air than on the ground. That is the
##     "acts very strangely, sometimes not moving, then jerking to another position".
##
## Nothing here is a fallback for the wrong answer; it is the right answer being produced by the
## wrong function. Probe: free fall first, then the same fall with W held and the camera looking
## straight down, and compare the two descent curves.
##
## No assertions. Inspection only, like the other probe_*.gd.

const MODE_NAMES := ["Grounded", "Airborne", "Wading", "EnteringWater", "SurfaceSwimming", "UnderwaterSwimming"]
const DROP_A := "A: no input (free fall)"
const DROP_B := "B: W held + camera straight down"
const MAX_TICKS := 400

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var camera: Camera3D
var ticks := 0
var phase := 0          # 0 setup, 1 drop A (no input), 2 drop B (input), 3 done
var cliff := Vector3.ZERO
var rows := []
var results := {}
var holding := false
var warm := 0          # ticks to ignore is_on_floor() after a teleport (see start_drop)


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func press(want: bool) -> void:
	if holding == want:
		return
	holding = want
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = want
	ev.echo = false
	Input.parse_input_event(ev)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 6:
		return false

	if phase == 0:
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		player = world.get_node_or_null("Player")
		zone = world.get_node_or_null("WaterZone")
		camera = player.get_node_or_null("Head/Camera3D")
		if player == null or zone == null:
			printerr("FAIL: player or WaterZone missing")
			quit(1)
			return true
		find_cliff()
		start_drop("A: no input (free fall)")
		phase = 1
		ticks = 0
		return false

	if phase == 3:
		press(false)
		summarise()
		quit(0)
		return true

	# is_on_floor() is whatever the last move_and_slide() concluded, so straight after a teleport
	# it still reports the floor the body was standing on before. Give it a few ticks to fall.
	if warm > 0:
		warm -= 1
	elif player.is_on_floor() or ticks > MAX_TICKS:
		finish_drop()
		return false

	# Tilt down far enough to clear DiveLookDownDeg, so the dive charge engages, but not so far
	# that the move vector has no horizontal component left in it.
	if phase == 2 and camera:
		camera.rotation.x = -PI * 0.25

	rows.append({
		"tick": ticks,
		"y": player.global_position.y,
		"vy": player.velocity.y,
		"mode": int(player.Mode),
		"swim_free": int(player.Mode) >= 3,
		"hspeed": Vector2(player.velocity.x, player.velocity.z).length(),
	})
	return false


func start_drop(label: String) -> void:
	player.global_position = Vector3(cliff.x, zone.WaterSurfaceY + 45.0, cliff.z)
	player.velocity = Vector3.ZERO
	# Setting `velocity` does not clear the controller's own _verticalVelocity, so the second
	# drop would start at whatever the first one landed with and the comparison would be junk.
	# Jump(0) is the public way to zero it: sqrt(0 * -2 * Gravity) is 0.
	player.Jump(0.0)
	rows.clear()
	results[label] = []
	warm = 8


func finish_drop() -> void:
	var label := DROP_A if phase == 1 else DROP_B
	results[label] = rows.duplicate()
	rows.clear()
	if phase == 1:
		press(true)
		start_drop(DROP_B)
		phase = 2
		ticks = 0
		return
	phase = 3


func summarise() -> void:
	print("")
	print("%-46s %-42s" % [DROP_A, DROP_B])
	var a: Array = results.get(DROP_A, [])
	var b: Array = results.get(DROP_B, [])
	print("")
	print("%-8s %10s %10s   %10s %10s" % ["tick", "A vy", "A hspeed", "B vy", "B hspeed"])
	var n: int = maxi(a.size(), b.size())
	for i in range(n):
		if i > 0 and i % 10 != 0 and i < n - 1:
			continue
		var av := "-"; var ah := "-"; var bv := "-"; var bh := "-"
		if i < a.size():
			av = "%.2f" % a[i]["vy"]; ah = "%.2f" % a[i]["hspeed"]
		if i < b.size():
			bv = "%.2f" % b[i]["vy"]; bh = "%.2f" % b[i]["hspeed"]
		print("%-8d %10s %10s   %10s %10s" % [i, av, ah, bv, bh])

	print("")
	for label in [DROP_A, DROP_B]:
		var r: Array = results.get(label, [])
		if r.is_empty():
			print(label, ": no rows")
			continue
		var fastest := 0.0
		var braked := 0
		var modes := {}
		var peak_h := 0.0
		var last_vy := 0.0
		for row in r:
			fastest = minf(fastest, row["vy"])
			peak_h = maxf(peak_h, row["hspeed"])
			modes[MODE_NAMES[row["mode"]]] = int(modes.get(MODE_NAMES[row["mode"]], 0)) + 1
			# A tick where the descent got SLOWER: something braked the fall.
			if last_vy < 0.0 and row["vy"] > last_vy + 0.01:
				braked += 1
			last_vy = row["vy"]
		print("--- ", label)
		print("    ticks:                %d" % r.size())
		print("    fastest descent:      %.2f m/s" % fastest)
		print("    ticks the fall braked:%d" % braked)
		print("    peak horizontal:      %.2f m/s" % peak_h)
		print("    modes seen:           %s" % modes)


func ground_at(x: float, z: float) -> float:
	var ss := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, zone.WaterSurfaceY + 60, z), Vector3(x, zone.WaterSurfaceY - 60, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


func find_cliff() -> void:
	var surface: float = zone.WaterSurfaceY
	var z := -2000
	while z <= 2000 and cliff == Vector3.ZERO:
		var x := -2000
		while x <= 2000:
			var hy := ground_at(x, z)
			if not is_nan(hy) and hy > surface + 3.0 and hy < surface + 40.0:
				cliff = Vector3(x, hy, z)
				break
			x += 50
		z += 50
	if cliff == Vector3.ZERO:
		printerr("FAIL: no island ground found above the waterline")
		quit(1)
