extends SceneTree

## Collision layer contract: the bits are what Scripts/Core/CollisionLayers.cs says they are, and
## -- the part that actually matters -- the PlayerBody/PlayerBody-detect pairing still agrees.
##
## With everything on the default layer 1, a ray cannot tell a player from a rock, and a ground
## probe that excludes only its own body reports a second player's capsule as "the floor". That is
## invisible with one player and broken with two, which is why layers are declared here rather
## than left implicit.
##
## The dangerous part of splitting the layers is not setting them, it is that the water zones and
## the player capsule have to agree. WaterZone.cs finds the player with GetOverlappingBodies(),
## which matches the zone's mask against the capsule's layer -- so those two numbers live in two
## different scene files and a change to one that misses the other turns water entry off with no
## error, no warning, and every water test failing for a reason that looks like a locomotion
## regression. Hence this test exists: it asserts the pairing at runtime rather than trusting the
## scene files to stay in step.
##
## Also asserts the split actually discriminates, because numbers in a scene file prove nothing on
## their own: the same downward ray is fired twice, once masked to World and once to PlayerBody,
## and each has to return a different collider.

const WORLD := 1
const PLAYER_BODY := 2
const PLAYER_HITBOX := 4

const SETTLE_TICKS := 40

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var terrain: Terrain3D
var ticks := 0
var failed := false


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		failed = true
		printerr("FAIL: ", label, " is ", got, ", expected ", want)
	print("  ", "ok  " if ok else "FAIL", "  ", label, " = ", got)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 6:
		return false

	if phase_is_unstarted():
		player = world.get_node_or_null("Player")
		zone = world.get_node_or_null("WaterZone")
		terrain = world.get_node_or_null("Terrain3D")
		if player == null or zone == null:
			printerr("FAIL: Player or WaterZone missing from World.tscn")
			quit(1)
			return true
		# Terrain3D builds its collision lazily and needs a camera and a collision mode before the
		# ground exists to be hit at all.
		terrain.set_camera(player.get_node_or_null("Head/Camera3D"))
		terrain.collision_mode = 3
		# Park the player high over deep water: inside the zone's box so the pairing can be
		# observed, clear of the terrain so the two raycasts cannot both hit the same thing.
		player.global_position = Vector3(950, zone.WaterSurfaceY + 45.0, -1200)
		player.velocity = Vector3.ZERO
		return false

	if ticks < 6 + SETTLE_TICKS:
		return false

	print("declared layers")
	check("Player.collision_layer", player.collision_layer, PLAYER_BODY)
	check("Player.collision_mask", player.collision_mask, WORLD)
	check("WaterZone.collision_layer", zone.collision_layer, WORLD)
	check("WaterZone.collision_mask", zone.collision_mask, PLAYER_BODY)

	# The PlayerHitbox layer is reserved and nothing is on it yet. If something has started
	# using it, a future mask that was written to ignore it will silently start hitting things,
	# so assert the reservation rather than trusting the comment.
	print("")
	print("reserved layer still unused")
	var hitbox_users := 0
	for node in _collision_objects(world):
		if (node.collision_layer & PLAYER_HITBOX) != 0:
			hitbox_users += 1
			printerr("FAIL: ", node.get_path(), " is on PlayerHitbox, which is reserved")
			failed = true
	print("  ", "ok  " if hitbox_users == 0 else "FAIL", "  objects on PlayerHitbox = ", hitbox_users)

	print("")
	print("the pairing agrees at runtime")
	var overlapping: Array[Node3D] = zone.get_overlapping_bodies()
	var sees_player := false
	for b in overlapping:
		if b == player:
			sees_player = true
	if not sees_player:
		printerr("FAIL: WaterZone does not detect the player. Zone mask ", zone.collision_mask,
			" vs capsule layer ", player.collision_layer,
			" -- these two scene files have drifted apart.")
		failed = true
	print("  ", "ok  " if sees_player else "FAIL", "  WaterZone.GetOverlappingBodies() contains the player")

	print("")
	print("the split discriminates")
	var ss := player.get_world_3d().direct_space_state
	var from := player.global_position + Vector3.UP * 40.0
	var to := player.global_position + Vector3.DOWN * 400.0

	var world_hit := ss.intersect_ray(_masked_ray(from, to, WORLD))
	var body_hit := ss.intersect_ray(_masked_ray(from, to, PLAYER_BODY))

	var world_is_terrain: bool = world_hit.has("collider") and world_hit["collider"] != player
	if not world_is_terrain:
		printerr("FAIL: a World-masked downward ray did not hit terrain (collider=", world_hit.get("collider", "<none>"), ")")
		failed = true
	print("  ", "ok  " if world_is_terrain else "FAIL", "  World mask hits terrain, not the player")

	var body_is_player: bool = body_hit.has("collider") and body_hit["collider"] == player
	if not body_is_player:
		printerr("FAIL: a PlayerBody-masked downward ray did not hit the player's capsule (collider=", body_hit.get("collider", "<none>"), ")")
		failed = true
	print("  ", "ok  " if body_is_player else "FAIL", "  PlayerBody mask hits the player's capsule, not terrain")

	if world_hit.has("position") and body_hit.has("position"):
		print("      terrain at y=", snappedf(world_hit["position"].y, 0.01),
			", capsule top at y=", snappedf(body_hit["position"].y, 0.01))

	print("")
	print("TEST COLLISION LAYERS ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
	return true


func phase_is_unstarted() -> bool:
	return player == null


func _masked_ray(from: Vector3, to: Vector3, mask: int) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	return q


func _collision_objects(node: Node) -> Array:
	var found: Array = []
	if node is CollisionObject3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_collision_objects(child))
	return found
