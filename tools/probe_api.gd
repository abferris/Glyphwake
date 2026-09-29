extends SceneTree

var world: Node3D
var cam: Camera3D
var phase := 0
var n := 0

func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)

func _physics_process(_d: float) -> bool:
	n += 1
	if n < 8:
		return false
	if cam == null:
		cam = world.get_node_or_null("Player/Head/Camera3D") as Camera3D
		if cam == null:
			print("no camera")
			return true
		print("camera pos ", cam.global_position, "  basis.z ", -cam.global_transform.basis.z)
		print("player pos ", (world.get_node_or_null("Player") as Node3D).global_position)
		var space := world.get_world_3d().direct_space_state
		for target in [Vector3(500,200,-1439), Vector3(500,200,0), Vector3(0,200,0), cam.global_position]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(target, target + Vector3(0,-500,0)))
			print("down from ", target, " -> ", "MISS" if hit.is_empty() else str(hit["position"]) + "  collider " + str(hit.get("collider")))
		print("--- straight down from the camera, 2000m ---")
		var c := cam.global_position
		var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(c, c + Vector3(0,-2000,0)))
		print("  ", "MISS" if h2.is_empty() else str(h2["position"]))
		print("--- colliders in the world ---")
		_count(world, 0)
		print("--- physics objects from the tree ---")
		for p in world.find_children("*", "CollisionObject3D", true, false):
			print("  ", p.get_path(), "  enabled_layer ", (p as CollisionObject3D).collision_layer)
		return true
	return false

func _count(n: Node, d: int) -> void:
	if d > 3:
		return
	if n is CollisionObject3D or String(n.get_class()) in ["Terrain3D", "MeshInstance3D", "StaticBody3D"]:
		print("  ".repeat(d), n.name, "  (", n.get_class(), ")")
	for c in n.get_children():
		_count(c, d + 1)
