extends SceneTree

## Wade drag sweep: stand the player in water of increasing depth, hold W, and check that the
## horizontal speed follows the depth-derived factor rather than a flat multiplier the moment
## the feet touch the zone.
##
## The player is pinned to a measured standing height every frame (a treadmill) so the depth
## under them cannot drift while the speed ramps -- otherwise they slide down the bank and the
## reading belongs to a different depth than the one being labelled. The expectation is
## recomputed from the export values plus the submersion the code actually measured, so
## re-tuning WadeMinSpeedFactor/WadeDragExponent cannot stale the test.
##
## Timing runs off the _physics_process virtual, not _process: headless idle frames run ~6x
## faster than the 60 Hz physics tick, so a pin or a settle driven from idle frames lets the
## player integrate several times in between and slide off the depth being measured.

const BUCKETS := [0.1, 0.3, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 1.6]
const DEEP := 2.8
const SETTLE_TICKS := 60
const HOLD_TICKS := 30
const FOOT_OFFSET := 0.889  # capsule bottom below the player origin, see PlayerController._restHeight

var world: Node3D
var player: CharacterBody3D
var terrain: Terrain3D
var camera: Camera3D
var zone: Area3D
var ticks := 0
var started := false
var scanned := false
var spots := {}
var phases: Array = []
var deep := Vector3.ZERO
var has_deep := false
var dry := Vector3.ZERO
var has_dry := false
var index := 0
var phase_start := 0
var standing_y := 0.0
var holding := false
var failed := false
var rows := []


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
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
	if ticks < 4:
		return false

	if not scanned:
		if ticks < 20:
			return false
		terrain = world.get_node_or_null("Terrain3D")
		player = world.get_node_or_null("Player")
		camera = world.get_node_or_null("Player/Head/Camera3D")
		zone = world.get_node_or_null("WaterZone")
		terrain.set_camera(camera)
		terrain.collision_mode = 3
		scan_shore()
		scanned = true
		started = true
		begin_phase()
		return false

	if index >= total_phases():
		press(false)
		return finish()

	# the pin runs before the nodes integrate, so the player starts every tick from the measured
	# spot and the depth under them is the one being labelled
	var spot := spot_for(index)
	player.global_position = Vector3(spot.x, standing_y, spot.z)

	var elapsed := ticks - phase_start
	if elapsed == SETTLE_TICKS:
		press(true)
	elif elapsed >= SETTLE_TICKS + HOLD_TICKS:
		press(false)
		record()
		index += 1
		begin_phase()
	return false


func total_phases() -> int:
	return phases.size() + (1 if has_deep else 0) + (1 if has_dry else 0)


## Phases are the wade buckets, then the deep control, then dry land. wading tops out where
## the eye crosses the surface (~1.68 m on this model), so past that the player is supposed to
## be swimming -- that boundary is its own check rather than another point on the drag curve.
func phase_kind(i: int) -> String:
	if i < phases.size():
		return "wade"
	return "deep" if i == phases.size() else "dry"


func spot_for(i: int) -> Vector3:
	if i < phases.size():
		return spots[phases[i]][0]
	if i == phases.size():
		return deep
	return dry


## Ground height at a column, or NAN when the ray misses.
func ground_at(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, zone.WaterSurfaceY + 40, z), Vector3(x, zone.WaterSurfaceY - 40, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


## Worst height step around a column. A steep bank makes the player slide, and a slope also
## gives a depth reading that slides off the bucket it was picked for.
func variation(ss: PhysicsDirectSpaceState3D, x: float, z: float, hy: float) -> float:
	var worst := 0.0
	for o in [Vector2(1.5, 0.0), Vector2(-1.5, 0.0), Vector2(0.0, 1.5), Vector2(0.0, -1.5)]:
		var h := ground_at(ss, x + o.x, z + o.y)
		if is_nan(h):
			return INF
		worst = maxf(worst, absf(h - hy))
	return worst


func scan_shore() -> void:
	var ss := player.get_world_3d().direct_space_state
	var surface: float = zone.WaterSurfaceY
	player.global_position = Vector3(500, 300, 0)
	var deep_d := INF
	var z := -3000
	while z <= 3000:
		var x := -2000
		while x <= 3000:
			var hy := ground_at(ss, x, z)
			if not is_nan(hy):
				var d: float = absf(x - 500) + absf(z)
				if surface - hy > DEEP and d < deep_d and variation(ss, x, z, hy) < 0.6:
					deep = Vector3(x, hy, z)
					deep_d = d
					has_deep = true
				for b in BUCKETS:
					if absf(surface - hy - b) < 0.06 and (not spots.has(b) or d < spots[b][1]):
						if variation(ss, x, z, hy) < 0.6:
							spots[b] = [Vector3(x, hy, z), d]
			x += 25
		z += 25
	phases = spots.keys()
	phases.sort()
	find_dry(ss, surface)
	print("scan done buckets=", phases, " deep=", has_deep, " dry=", has_dry)


## Fan out from the shallowest spot until dry, level ground is found: the control that proves
## the zone is not dragging anyone who is merely standing near it.
func find_dry(ss: PhysicsDirectSpaceState3D, surface: float) -> void:
	if phases.is_empty():
		return
	var from: Vector2 = Vector2(spots[phases[0]][0].x, spots[phases[0]][0].z)
	for i in 16:
		var dir := Vector2.RIGHT.rotated(TAU * i / 16.0)
		var p := from
		for step in 200:
			p += dir * 25.0
			var hy := ground_at(ss, p.x, p.y)
			if not is_nan(hy) and hy > surface + 0.05 and variation(ss, p.x, p.y, hy) < 0.6:
				dry = Vector3(p.x, hy, p.y)
				has_dry = true
				return


func begin_phase() -> void:
	phase_start = ticks
	var spot := spot_for(index)
	standing_y = spot.y + FOOT_OFFSET
	player.global_position = Vector3(spot.x, standing_y, spot.z)


func record() -> void:
	var sub: float = player.WadeSubmersion
	var horizontal: float = Vector2(player.velocity.x, player.velocity.z).length()
	var want: float = lerpf(1.0, player.WadeMinSpeedFactor, pow(sub, player.WadeDragExponent)) * player.MoveSpeed
	var kind := phase_kind(index)
	var depth: float = zone.WaterSurfaceY - (standing_y - FOOT_OFFSET)
	print(kind, " depth=", snappedf(depth, 0.01), " submersion=", snappedf(sub, 0.001),
		" swim=", player.IsSwimming, " wade=", player.IsWading, " under=", player.IsUnderwater,
		" floor=", player.is_on_floor(), " speed=", snappedf(horizontal, 0.001), " want=", snappedf(want, 0.001),
		" | body_y=", snappedf(player.global_position.y, 0.001), " eye_y=", snappedf(camera.global_position.y, 0.001),
		" water=", snappedf(zone.WaterSurfaceY, 0.001))
	if kind == "deep":
		# past the point where the eye crosses the surface the player must be swimming, not
		# wading: this is the wade -> swim handoff, and it is where the drag curve bottoms out
		if player.IsWading or not player.IsUnderwater:
			printerr("FAIL: depth ", snappedf(depth, 0.01), " should be swimming (underwater), not wading")
			failed = true
		return
	if kind == "dry":
		# the zone box is 50 m tall, so dry ground can still be inside it: what matters is that
		# no water is on the player, so the drag curve has to sit at full speed
		if sub > 0.0:
			printerr("FAIL: the dry-land control has water on it (submersion ", sub, ")")
			failed = true
		if absf(horizontal - player.MoveSpeed) > 0.35:
			printerr("FAIL: dry land is slowed (", snappedf(horizontal, 0.001), " vs ", player.MoveSpeed, ")")
			failed = true
		return
	rows.append({"sub": sub, "speed": horizontal})
	if not player.IsWading or player.IsUnderwater:
		printerr("FAIL: depth ", snappedf(depth, 0.01), " should be wading, not swimming")
		failed = true
	if absf(horizontal - want) > 0.35:
		printerr("FAIL: submersion ", snappedf(sub, 0.001), " speed ", snappedf(horizontal, 0.001), " != drag curve ", snappedf(want, 0.001))
		failed = true


func finish() -> bool:
	rows.sort_custom(func(a, b): return a["sub"] < b["sub"])
	var prev := -1.0
	for r in rows:
		if prev >= 0.0 and r["speed"] > prev + 0.05:
			printerr("FAIL: speed rose with depth (", prev, " -> ", r["speed"], ")")
			failed = true
		prev = r["speed"]
	if rows.size() < 3:
		printerr("FAIL: only ", rows.size(), " wade points found, sweep is too thin to judge")
		failed = true
	print("TEST WADE ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
	return true
