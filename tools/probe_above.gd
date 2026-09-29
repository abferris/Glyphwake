extends SceneTree

# Scratch probe: does the above-water surface get clearer looking down and murkier at a grazing
# angle, and fade gradually with depth? Renders real frames (no --headless) and measures
# transmission from a saturated red marker hung in the water column: a red-minus-blue signal
# survives the water in proportion to how clear it is, and is independent of how bright the water
# itself is, so it separates "bottom visible" from "water opaque" without eyeballing anything.
#
# The deep spot is found by raycast rather than hard coded, because the sea floor here runs from
# ankle deep to over 20 m and a guessed spot puts the marker inside a hill.

const SURFACE_Y := 80.0
const CAM_ABOVE := 12.0
const ANGLES := [85.0, 55.0, 30.0, 15.0]  # degrees below horizontal

var world: Node3D
var view: SubViewport
var cam: Camera3D
var water: MeshInstance3D
var marker: MeshInstance3D
var frames := 0
var stage := 0
var cases: Array = []
var ci := 0
var phase := 0
var results: Array = []
var pending := 0.0
var spot := Vector2.ZERO
var floor_y := 0.0
var depths: Array = []


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames > 3000:
		print("WATCHDOG: probe never finished")
		quit(1)
		return true

	if stage == 0:
		if frames < 6:
			return false
		world.get_node_or_null("Player").free()
		if not _find_deep():
			quit(1)
			return true
		depths = [1.5, round((SURFACE_Y - floor_y) * 0.4 * 10.0) / 10.0, round((SURFACE_Y - floor_y) * 0.75 * 10.0) / 10.0]
		water = world.get_node_or_null("Water")
		marker = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 2.0, 2.0)
		marker.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.1, 0.02)
		marker.material_override = mat
		world.add_child(marker)
		# An explicit SubViewport with UPDATE_ALWAYS: the root window only presents frames when it
		# is actually on screen, and a hidden window returns a stale image, which silently measures
		# the wrong frame rather than failing.
		view = SubViewport.new()
		view.size = Vector2i(320, 180)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.own_world_3d = false
		root.add_child(view)
		cam = Camera3D.new()
		cam.far = 4000.0
		view.add_child(cam)
		cam.make_current()
		print("deep spot %s floor %.2f (%.1f m deep), depths %s" % [spot, floor_y, SURFACE_Y - floor_y, depths])
		for d in depths:
			for a in ANGLES:
				cases.append({"depth": d, "angle": a})
		stage = 1
		return false

	var c: Dictionary = cases[ci]
	var depth: float = c["depth"]
	var ang: float = c["angle"]
	# pose is set once per case: if it is reset every frame the rendered frame and the
	# unprojection disagree, because one of them lags a frame behind the transform
	if phase == 0:
		var pose := _clear_pose(depth, ang)
		marker.global_position = pose[0]
		cam.global_position = pose[1]
		cam.look_at(pose[0], Vector3.UP)
	water.visible = phase < 2

	if phase == 1 or phase == 3:
		var img := view.get_texture().get_image()
		var sig: Variant = _signal(img, cam.unproject_position(marker.global_position))
		if sig == null:
			print("  marker off screen at depth %.1f angle %.1f" % [depth, ang])
			ci += 1
			phase = 0
			if ci >= cases.size():
				_report()
				return true
			return false
		if phase == 1:
			pending = sig
			phase = 2
			return false
		results.append({"depth": depth, "angle": ang, "wet": pending, "dry": sig})
		ci += 1
		phase = 0
		if ci >= cases.size():
			_report()
			return true
		return false
	phase += 1
	return false


# Terrain3D's visual mesh is finer than the collision the raycast sees, so a marker can be
# "underwater with a clear raycast" and still be buried in the rendered hill. Requiring the line of
# sight to be clear is not enough either, so the floor is also required to be well under the marker
# and the marker is checked to actually land on the sampled pixel band.
func _clear_pose(depth: float, ang: float) -> Array:
	var sp := world.get_world_3d().direct_space_state
	var horiz: float = (CAM_ABOVE + depth) / max(tan(deg_to_rad(ang)), 0.02)
	for ring in 26:
		for a in 10:
			var th := TAU * float(a) / 10.0
			var x := spot.x + cos(th) * float(ring) * 9.0
			var z := spot.y + sin(th) * float(ring) * 9.0
			var mark := Vector3(x, SURFACE_Y - depth, z)
			var cam_pos := Vector3(x - horiz, SURFACE_Y + CAM_ABOVE, z)
			var fl: Dictionary = sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, SURFACE_Y + 2.0, z), Vector3(x, SURFACE_Y - 300.0, z)))
			if fl.is_empty() or (fl["position"] as Vector3).y > mark.y - 1.5:
				continue
			var lo: Dictionary = sp.intersect_ray(PhysicsRayQueryParameters3D.create(cam_pos, mark))
			if not lo.is_empty() and (lo["position"] as Vector3).distance_to(cam_pos) < horiz * 1.9:
				continue
			return [mark, cam_pos]
	return [Vector3(spot.x, SURFACE_Y - depth, spot.y), Vector3(spot.x - horiz, SURFACE_Y + CAM_ABOVE, spot.y)]


func _find_deep() -> bool:
	var space := world.get_world_3d().direct_space_state
	var best := 0.0
	for xi in 70:
		for zi in 70:
			var x := lerpf(-900.0, 1400.0, float(xi) / 69.0)
			var z := lerpf(-2400.0, -500.0, float(zi) / 69.0)
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, SURFACE_Y + 2.0, z), Vector3(x, SURFACE_Y - 300.0, z))
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				continue
			var d: float = SURFACE_Y - (hit["position"] as Vector3).y
			if d > best:
				best = d
				spot = Vector2(x, z)
				floor_y = (hit["position"] as Vector3).y
	print("raycast deepest = %.2f m at %s" % [best, spot])
	return best > 12.0


# average a small box so one pixel of noise cannot decide the result
func _signal(img: Image, p: Vector2) -> Variant:
	if int(p.x) < 3 or int(p.y) < 3 or int(p.x) >= img.get_width() - 3 or int(p.y) >= img.get_height() - 3:
		return null
	var acc := 0.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := img.get_pixel(int(p.x) + dx, int(p.y) + dy)
			acc += float(c.r - c.b)
	return acc / 25.0


func _report() -> void:
	print("== transmission (1.0 = marker fully visible through the water)")
	print("  depth  angle     dry sig     wet sig   transmission")
	for r in results:
		var d: float = r["dry"]
		var t: float = r["wet"] / d if absf(d) > 0.0001 else 0.0
		print("  %5.1f  %5.1f  %10.5f  %10.5f   %7.3f" % [r["depth"], r["angle"], d, r["wet"], t])
	quit()
