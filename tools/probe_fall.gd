extends SceneTree

## Fall-speed probe: drop the player onto deep water from a cliff height and log the descent
## every physics tick, so the fall speed cap can be read off the run rather than reasoned about.
##
## No assertions. This is an inspection script, same family as the other probe_*.gd: it prints
## what happened and always exits 0. The point of interest is the tick IsUnderwater flips on,
## because that is what selects SimulateSwim's branch.

const CLIFF_HEIGHT := 120.0
const MAX_TICKS := 900

const MODE_NAMES := ["Grounded", "Airborne", "Wading", "EnteringWater", "SurfaceSwimming", "UnderwaterSwimming"]

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var ticks := 0
var phase := 0
var deep := Vector3.ZERO
var has_deep := false
var rows := []
var prev_underwater := false


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 6:
		return false

	if phase == 0:
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		player = world.get_node_or_null("Player")
		zone = world.get_node_or_null("WaterZone")
		if player == null or zone == null:
			printerr("player or WaterZone missing")
			quit(1)
			return true
		scan()
		phase = 1
		return false

	if phase == 1:
		# Above the water zone entirely, in open air, so the drop starts as a plain Airborne fall.
		player.global_position = Vector3(deep.x, zone.WaterSurfaceY + CLIFF_HEIGHT, deep.z)
		player.velocity = Vector3.ZERO
		rows.clear()
		print("dropped from y=", snappedf(player.global_position.y, 0.01),
			" over ", snappedf(zone.WaterSurfaceY - deep.y, 0.01), "m of water at ", deep,
			"  (cliff ", CLIFF_HEIGHT, "m)")
		phase = 2
		return false

	if player.global_position.y < deep.y - 2.0 or ticks > MAX_TICKS:
		report()
		quit(0)
		return true

	rows.append({
		"tick": ticks,
		"y": player.global_position.y,
		"vy": player.velocity.y,
		"sub": player.WadeSubmersion,
		"under": player.IsUnderwater,
		"plunge": player.IsPlunging,
		"mode": int(player.Mode),
		"eye_below": zone.WaterSurfaceY - player.global_position.y,
	})
	prev_underwater = player.IsUnderwater
	return false


func ground_at(x: float, z: float) -> float:
	var ss := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, zone.WaterSurfaceY + 40, z), Vector3(x, zone.WaterSurfaceY - 40, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


func variation(x: float, z: float, hy: float) -> float:
	var worst := 0.0
	for o in [Vector2(1.5, 0.0), Vector2(-1.5, 0.0), Vector2(0.0, 1.5), Vector2(0.0, -1.5)]:
		var h := ground_at(x + o.x, z + o.y)
		if is_nan(h):
			return INF
		worst = maxf(worst, absf(h - hy))
	return worst


func scan() -> void:
	var surface: float = zone.WaterSurfaceY
	var z := -3000
	while z <= 3000 and not has_deep:
		var x := -2000
		while x <= 3000:
			var hy := ground_at(x, z)
			if not is_nan(hy) and variation(x, z, hy) < 0.6 and surface - hy > 6.0:
				deep = Vector3(x, hy, z)
				has_deep = true
				break
			x += 50
		z += 50
	if not has_deep:
		printerr("FAIL: scan found no deep water")
		quit(1)


func report() -> void:
	print("")
	print("tick      y      vy    sub   eyeBelow  under  plunge  mode")
	for r in rows:
		var mark := ""
		if r["under"] and not prev_underwater:
			mark = "   <-- IsUnderwater flipped"
		elif r["under"]:
			mark = ""
		print("%5d %7.2f %7.2f %6.3f %9.2f %7s %8s  %s%s" % [
			r["tick"], r["y"], r["vy"], r["sub"], r["eye_below"],
			str(r["under"]), str(r["plunge"]), MODE_NAMES[r["mode"]], mark])
		prev_underwater = r["under"]

	print("")
	var fastest := 0.0
	var fastest_vy := 0.0
	var flip_vy := 0.0
	var flip_found := false
	for r in rows:
		if r["vy"] < fastest:
			fastest = r["vy"]
			fastest_vy = r["eye_below"]
		if r["under"] and not flip_found:
			flip_vy = r["vy"]
			flip_found = true
	print("fastest descent reached: %.2f m/s (eye %.2f m below surface)" % [fastest, fastest_vy])
	if flip_found:
		print("IsUnderwater flipped at vy=%.2f m/s" % flip_vy)
		print("")
		print("after the flip, the descent was:")
		var seen := false
		for r in rows:
			if r["under"]:
				seen = true
			if seen:
				print("   tick %5d  y %7.2f  vy %7.2f  sub %5.3f  mode %s" % [
					r["tick"], r["y"], r["vy"], r["sub"], MODE_NAMES[r["mode"]]])
