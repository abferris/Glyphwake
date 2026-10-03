extends SceneTree

## Cliff probe: fall through open air from a high surface on the island -- the part of the drop
## that happens BEFORE any water -- and log the descent.
##
## The suspicion this checks: LocomotionState decides "shallow floor" with
##     shallow = WaterSurfaceY - groundY < WadeDepth
## which has no lower bound, so ground that sits ABOVE the waterline -- which is every cliff on
## the island -- makes the difference negative and therefore shallow. That latches IsWading and
## IsOverShallowFloor while the body is falling through open air, and PlayerController answers
## overShallowFloor with -MaxSwimVerticalSpeed as the descent limit, bypassing MaxFallSpeed.
##
## No assertions. Inspection only, like the other probe_*.gd.

const MAX_TICKS := 600
const MODE_NAMES := ["Grounded", "Airborne", "Wading", "EnteringWater", "SurfaceSwimming", "UnderwaterSwimming"]

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var ticks := 0
var phase := 0
var cliff := Vector3.ZERO
var has_cliff := false
var rows := []
var capped_at := NAN
var min_free_fall := INF


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
		find_cliff()
		phase = 1
		return false

	if phase == 1:
		# Start high above a piece of island that is itself above the waterline, so the whole
		# drop is open air over land. Nothing here should ever be swimming.
		player.global_position = Vector3(cliff.x, zone.WaterSurfaceY + 45.0, cliff.z)
		player.velocity = Vector3.ZERO
		rows.clear()
		print("cliff top y=", snappedf(cliff.y, 0.01), " (", snappedf(cliff.y - zone.WaterSurfaceY, 0.01),
			"m above the waterline) at ", Vector2(cliff.x, cliff.z))
		print("dropping from y=", snappedf(player.global_position.y, 0.01),
			" -- pure open air, no water touched")
		phase = 2
		return false

	if player.is_on_floor() or ticks > MAX_TICKS:
		report()
		quit(0)
		return true

	rows.append({
		"tick": ticks,
		"y": player.global_position.y,
		"vy": player.velocity.y,
		"under": player.IsUnderwater,
		"wading": player.IsWading,
		"shallow": player.IsOverShallowFloor,
		"mode": int(player.Mode),
		"ground": player.GroundY,
		"inwater": player.IsSwimming,
	})
	return false


func ground_at(x: float, z: float) -> float:
	var ss := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, zone.WaterSurfaceY + 60, z), Vector3(x, zone.WaterSurfaceY - 60, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


func find_cliff() -> void:
	# Island ground between 3 and 40 m above the waterline: high enough to be clearly land, low
	# enough that the zone (which tops out 50 m above the waterline) definitely overlaps it.
	var surface: float = zone.WaterSurfaceY
	var z := -2000
	while z <= 2000 and not has_cliff:
		var x := -2000
		while x <= 2000:
			var hy := ground_at(x, z)
			if not is_nan(hy) and hy > surface + 3.0 and hy < surface + 40.0:
				cliff = Vector3(x, hy, z)
				has_cliff = true
				break
			x += 50
		z += 50
	if not has_cliff:
		printerr("FAIL: no island ground found above the waterline")
		quit(1)


func report() -> void:
	print("")
	print("tick      y      vy   wading shallow  mode            groundY")
	for r in rows:
		print("%5d %7.2f %7.2f %7s %7s  %-15s %s" % [
			r["tick"], r["y"], r["vy"], str(r["wading"]), str(r["shallow"]),
			MODE_NAMES[r["mode"]], ("%.2f" % r["ground"]) if not is_inf(r["ground"]) else "-inf"])

	print("")
	var air := rows.filter(func(r): return not r["inwater"])
	var ever_shallow := false
	for r in rows:
		if r["shallow"]:
			ever_shallow = true
	print("ticks in open air (never entered the swim state): %d of %d" % [air.size(), rows.size()])
	print("ever reported IsOverShallowFloor while in open air: %s" % str(ever_shallow))
	var fastest := 0.0
	for r in rows:
		fastest = minf(fastest, r["vy"])
	print("fastest descent: %.2f m/s" % fastest)
	var first_slow := -1
	for r in rows:
		if r["vy"] < -8.0 and first_slow < 0:
			first_slow = r["tick"]
	if first_slow >= 0:
		print("first tick past -8 m/s: %d" % first_slow)
	else:
		print("NEVER exceeded -8 m/s: the fall was capped in open air")
