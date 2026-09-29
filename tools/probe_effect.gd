extends SceneTree

# Scratch probe, not production. Stage B for the water tint: check that the screen-space pass
# reconstructs world positions correctly, before any tinting is trusted.
#
# Ground truth here is an analytic ray/box intersection, not a physics raycast. Physics turns out to
# be unusable as a reference in this scene: the world is built from Terrain3D, which does not appear
# in the tree as a CollisionObject3D, and a ray fired from inside the player hits the player first, so
# every raycast either misses or reports the wrong body. Flat plates whose height is known exactly
# give positions that cannot be wrong.
#
# Samples are taken at world points projected back to the screen, so the expected height is exactly
# the point's own height rather than the result of a search for what a ray happens to hit. Each point
# is also confirmed to be the nearest surface along its own ray, so an occluded or off-surface sample
# is dropped instead of being counted as a reconstruction failure.
#
# The shader encodes world Y into red across a known 100 m range. Tonemapping is forced to linear so
# that the only transform between the shader and the readback is sRGB encoding, which is exactly
# invertible, and the probe recovers the height in metres and reports the error in metres.

const WORLD := "res://Scenes/World.tscn"
const SURFACE_Y := 80.0
const Y_BASE := 55.0
const Y_RANGE := 75.0
const XZ_RANGE := 200.0
const TOLERANCE := 0.5

# Plates straddling the waterline, so one frame proves the reconstruction on both sides of it. dist is
# along the camera's flattened forward axis, side is a world X offset, top is the absolute world Y of
# the top face.
# The three footprints are laid out to be disjoint in XZ, which matters more than it looks: when they
# overlapped, a sample aimed at one plate was silently occluded by another, and the probe then measured
# the occluder's height while reporting it as a reconstruction error. Small and well separated also
# keeps each plate's screen footprint to a patch of solid interior at 640x360, away from silhouette
# edges where depth belongs to something else.
const PLATE_SPECS := [
	{"dist": 30.0, "side": -34.0, "top": 96.0},
	{"dist": 46.0, "side": 40.0, "top": 68.0},
	{"dist": 64.0, "side": -6.0, "top": 116.0},
]
const PLATE_HALF := 10.0
const PLATE_THICK := 3.0

enum Phase {WARMUP, AIMING, SETTLING, TINTING, DONE}

var world: Node3D
var stage: Node3D
var debug_depth_range := 14.0
var cam: Camera3D
var effect: CompositorEffect
var samples: Array = []
var plate_centres: Array[Vector3] = []
var plate_half: Array[Vector3] = []
var plate_top: Array[float] = []
var aim: Transform3D
var phase := Phase.WARMUP
var frames := 0


func _initialize() -> void:
	world = (load(WORLD) as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _process(_d: float) -> bool:
	if phase == Phase.DONE:
		return true
	frames += 1
	match phase:
		Phase.WARMUP:
			if frames >= 14:
				_start()
		Phase.AIMING:
			cam.global_transform = aim
			cam.make_current()
			if frames >= 12:
				_collect_samples()
				phase = Phase.SETTLING
				frames = 0
		Phase.SETTLING:
			cam.global_transform = aim
			cam.make_current()
			if frames >= 12:
				_compare_debug()
				# Straight on into the real path, same frame layout, so the tint can be checked against
				# the very same sample points the reconstruction was just validated on.
				effect.debug = false
				effect.depth_range = debug_depth_range
				phase = Phase.TINTING
				frames = 0
		Phase.TINTING:
			cam.global_transform = aim
			cam.make_current()
			if frames >= 12:
				_compare_tint()
				phase = Phase.DONE
				return true
	return false


func _start() -> void:
	# The value read back from the window has been through the display transform, so it is only
	# invertible if that transform is known. Linear tonemapping and unity exposure leave sRGB as the
	# only step, and sRGB is exactly invertible.
	var env := world.find_children("*", "WorldEnvironment", true, false)
	if env.is_empty():
		print("FAIL: no WorldEnvironment found")
		phase = Phase.DONE
		return
	var wenv := env[0] as WorldEnvironment
	wenv.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	wenv.environment.tonemap_exposure = 1.0
	wenv.environment.adjustment_enabled = false
	wenv.environment.glow_enabled = false
	wenv.environment.ssao_enabled = false

	# Every piece of real geometry is hidden, but nothing is freed. The Water and WaterZone nodes the
	# effect reads its water level from have to stay in the tree, and the lighting has to stay or the
	# plates render black.
	#
	# This is not cosmetic. The real world is a landscape, and its shoreline sits about 29 m from the
	# probe's viewpoint, which is nearer than the underwater plate. Samples aimed at that plate were
	# being decided by the shore instead, so the probe faithfully reconstructed the shore and reported
	# 30 m errors against geometry that was never visible. A reference measurement cannot share its
	# scene with the thing it is measuring.
	#
	# Hiding is by property presence rather than by VisualInstance3D, because Terrain3D is not one and
	# a class-filtered search leaves the shoreline drawing, which is indistinguishable from a broken
	# reconstruction. Lights and cameras are kept: one for visibility of the plates, the other so the
	# probe's own camera stays the only candidate for the viewport.
	var hidden := 0
	var kinds := {}
	for n in world.find_children("*", "", true, false):
		if n is Light3D or n is Camera3D:
			continue
		if "visible" in n:
			n.set("visible", false)
			hidden += 1
			var k := n.get_class()
			kinds[k] = int(kinds.get(k, 0)) + 1
	print("  hid %d real nodes so they cannot occlude the reference plates: %s" % [hidden, kinds])

	# The probe's own stage, holding the camera and the reference plates.
	# Parented synchronously, not deferred: a node outside the tree has no global transform, so
	# assigning the camera's aim here would silently write to a local basis and leave it at the origin.
	stage = Node3D.new()
	stage.name = "ProbeStage"
	root.add_child(stage)

	# A water plane at the real surface height, so the debug pass sees the same body it will see in
	# play. It does not write depth, so it cannot take a sample's depth away from the plate behind it.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000.0, 2000.0)
	water.mesh = plane
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.3, 0.5, 0.4)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Rendering without contributing to depth is the whole point: a transparent surface that still wrote
	# depth would become the nearest thing in the frame and every underwater sample would measure it.
	wmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	water.material_override = wmat
	stage.add_child(water)
	water.global_position = Vector3(500.0, SURFACE_Y, -1500.0)

	# A camera of the probe's own, not the player's. The player's camera hangs off a CharacterBody3D,
	# and the body reasserts its transform on the camera every step, so an aim written in _process is
	# gone again by the time the frame renders: the shader then reconstructs from one viewpoint while
	# the samples are projected from another, which looks exactly like a broken shader.
	var probe_cam := Camera3D.new()
	probe_cam.fov = 70.0
	stage.add_child(probe_cam)
	aim = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-30.0), deg_to_rad(15.0), 0.0)),
		Vector3(500.0, 120.0, -1500.0))
	probe_cam.global_transform = aim
	probe_cam.make_current()
	cam = probe_cam

	effect = load("res://Scripts/World/WaterTintEffect.gd").new()
	effect.debug = true
	effect.y_base = Y_BASE
	# The debug view needs its own vertical span, but depth_range is the tint's own parameter, not the
	# probe's. Borrowing it for the debug encoding and forgetting to give it back leaves the tint
	# running at a third of its strength, which reads as a weak effect rather than as a wrong number.
	debug_depth_range = effect.depth_range
	effect.depth_range = Y_RANGE
	var compositor := Compositor.new()
	compositor.compositor_effects = [effect]
	cam.compositor = compositor
	effect.setup(world, cam)

	# Nothing else may take the viewport.
	for other in world.find_children("*", "Camera3D", true, false):
		if other == cam:
			continue
		(other as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(other as Camera3D).current = false
	cam.make_current()

	# Plates are placed along the camera's own forward axis rather than at guessed world coordinates,
	# so they are guaranteed to be in frame whatever the yaw. Horizontal component only: the spec top
	# is an absolute world Y, and adding a pitched forward vector to it would land them far higher.
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	plate_centres = []
	for p in PLATE_SPECS:
		var half := Vector3(PLATE_HALF, PLATE_THICK, PLATE_HALF)
		var centre: Vector3 = cam.global_position + fwd * float(p["dist"]) + Vector3(float(p["side"]), 0.0, 0.0)
		centre.y = float(p["top"]) - half.y
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = half * 2.0
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.2, 0.2)
		mi.material_override = mat
		stage.add_child(mi)
		# Must be after add_child: a global transform is meaningless outside the tree.
		mi.global_position = centre
		plate_centres.append(centre)
		plate_half.append(half)
		plate_top.append(float(p["top"]))
		print("  plate top %.0f -> world %s" % [p["top"], centre])
	print("  camera %s fov %.0f forward %s" % [cam.global_position, cam.fov, fwd])
	phase = Phase.AIMING
	frames = 0


func _collect_samples() -> void:
	var vp := root.get_viewport().get_visible_rect().size
	samples = []
	for i in plate_centres.size():
		var centre: Vector3 = plate_centres[i]
		var half: Vector3 = plate_half[i]
		var top: float = plate_top[i]
		for gx in 3:
			for gz in 3:
				var world_p := centre + Vector3(
					lerpf(-0.6, 0.6, float(gx)) * half.x, 0.0, lerpf(-0.6, 0.6, float(gz)) * half.z)
				world_p.y = top
				var sp := cam.unproject_position(world_p)
				if sp.x < 2.0 or sp.y < 2.0 or sp.x >= vp.x - 2.0 or sp.y >= vp.y - 2.0:
					continue
				# Only keep a sample whose own point is the nearest surface along its ray. Checking this
				# against the sampled plate alone is not enough: a neighbouring plate in front of it
				# decides the depth instead, and the comparison then measures the occluder's height
				# while blaming the reconstruction.
				var from := cam.project_ray_origin(sp)
				var dir := cam.project_ray_normal(sp)
				var t_point := (world_p - from).dot(dir)
				var t_nearest := -1.0
				for j in plate_centres.size():
					var t_j := _ray_aabb(from, dir, plate_centres[j], plate_half[j])
					if t_j >= 0.0 and (t_nearest < 0.0 or t_j < t_nearest):
						t_nearest = t_j
				if t_nearest < 0.0 or absf(t_nearest - t_point) > 0.5:
					continue
				samples.append({"screen": sp, "y": top, "world": world_p, "plate": i})
	print("  visible rect %s, valid samples %d of %d" % [vp, samples.size(), plate_centres.size() * 9])
	print("  probe thinks camera is at %s" % cam.global_position)


func _ray_aabb(origin: Vector3, dir: Vector3, center: Vector3, half: Vector3) -> float:
	var tmin := -1.0e20
	var tmax := 1.0e20
	for axis in 3:
		var o := origin[axis]
		var d := dir[axis]
		if absf(d) < 1.0e-8:
			if o < center[axis] - half[axis] or o > center[axis] + half[axis]:
				return -1.0
			continue
		var t1 := (center[axis] - half[axis] - o) / d
		var t2 := (center[axis] + half[axis] - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmax < 0.0:
		return -1.0
	return maxf(tmin, 0.0)


func _srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


func _compare_tint() -> void:
	# The reconstruction being exact says nothing about the tint, so the same sample points are read
	# again with the real pass enabled. What matters is the split: a sample aimed below the surface
	# has to come back tinted, and one aimed above it must come back untouched. A tint that is uniform
	# is exactly as wrong as no tint at all, so the two groups are compared against each other rather
	# than against a fixed colour.
	var vp := root.get_viewport().get_visible_rect().size
	var img := root.get_texture().get_image()
	if img == null:
		print("FAIL: no image back from the window")
		quit(1)
		return
	var under := 0
	var above := 0
	var under_sum := 0.0
	var above_sum := 0.0
	print("=== tint applied per pixel ===")
	for s in samples:
		var sp: Vector2 = s["screen"]
		var px := Vector2i(int(sp.x / vp.x * img.get_width()), int(sp.y / vp.y * img.get_height()))
		if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
			continue
		var c := img.get_pixel(px.x, px.y)
		var lin := Color(_srgb_to_linear(c.r), _srgb_to_linear(c.g), _srgb_to_linear(c.b))
		var blueness := lin.b - lin.r
		var submerged: bool = float(s["y"]) < SURFACE_Y
		if submerged:
			under += 1
			under_sum += blueness
		else:
			above += 1
			above_sum += blueness
		print("  world y %6.1f  %-9s  rgb (%.3f, %.3f, %.3f)  b-r %+.4f" % [
			s["y"], "SUBMERGED" if submerged else "above", lin.r, lin.g, lin.b, blueness])
	var under_avg := under_sum / float(under) if under > 0 else 0.0
	var above_avg := above_sum / float(above) if above > 0 else 0.0
	print("  samples below the surface: %d, average b-r %+.4f" % [under, under_avg])
	print("  samples above the surface: %d, average b-r %+.4f" % [above, above_avg])
	if under == 0 or above == 0:
		print("  VERDICT: no split to judge, the sample set is one-sided")
	elif under_avg > above_avg + 0.05:
		print("  VERDICT: the tint follows the waterline, submerged pixels are bluer than dry ones")
	else:
		print("  VERDICT: the tint does not follow the waterline")
	quit()


func _compare_debug() -> void:
	var vp := root.get_viewport().get_visible_rect().size
	var img := root.get_texture().get_image()
	if img == null:
		print("FAIL: no image back from the window")
		quit(1)
		return
	var within := 0
	var on_plate := 0
	var on_target := 0
	var worst := 0.0
	var checked := 0
	print("=== reconstructed height vs known plate height ===")
	print("     screen                    got     err    xz        got xz          want xz")
	for s in samples:
		var sp: Vector2 = s["screen"]
		# The viewport and the 3D render target are different sizes here (1152x648 vs 640x360), so a
		# viewport-space point has to be mapped into image space before being read, or the wrong pixel
		# gets compared.
		var px := Vector2i(int(sp.x / vp.x * img.get_width()), int(sp.y / vp.y * img.get_height()))
		if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
			continue
		var c := img.get_pixel(px.x, px.y)
		checked += 1
		# The shader encodes (y, x, z) as numbers in the first three channels, so each is recovered
		# exactly rather than judged by eye. Alpha confirms the intended pixel was the one read.
		var t := _srgb_to_linear(c.r)
		var got := t * Y_RANGE + Y_BASE
		# The shader encodes these as (x - cam.x) / range + 0.5, so inverting is a subtraction of the
		# half offset followed by a single multiply by the range. The height is encoded without the
		# half offset, which is why it recovered correctly while these did not.
		var got_x := (_srgb_to_linear(c.g) - 0.5) * XZ_RANGE + cam.global_position.x
		var got_z := (_srgb_to_linear(c.b) - 0.5) * XZ_RANGE + cam.global_position.z
		var err := got - float(s["y"])
		# The reconstructed X and Z have to land on the plate the sample was aimed at. A height-only
		# comparison cannot tell that apart from a correct reconstruction that happened to pick up a
		# neighbouring surface at a similar height, which is precisely how the earlier version of this
		# probe reported two samples as 25 m errors that were really occlusion.
		var want: Vector3 = s["world"]
		var xz_off := Vector2(got_x - want.x, got_z - want.z).length()
		var plate: int = s["plate"]
		var inside := absf(got_x - plate_centres[plate].x) <= PLATE_HALF * 1.6 \
			and absf(got_z - plate_centres[plate].z) <= PLATE_HALF * 1.6
		if inside:
			on_plate += 1
		worst = maxf(worst, absf(err))
		var want_gx := sp.x / vp.x
		var want_gy := sp.y / vp.y
		# Kept in the printout: it is the raw value the alpha channel came back as, which is how the
		# fact that alpha is not sRGB-encoded was established in the first place.
		# Alignment is judged from the reconstructed X and Z: agreeing with the aimed-at point to well
		# under a metre already proves the right pixel was read, and the alpha channel does not survive
		# the backbuffer read reliably enough to be worth depending on.
		var on_target_px := xz_off <= 3.0
		if on_target_px:
			on_target += 1
		if absf(err) <= TOLERANCE and inside and xz_off <= 3.0:
			within += 1
		var flag := ""
		if not inside:
			flag = "  OFF-PLATE (occluded or misread)"
		elif not on_target_px:
			flag = "  XZ OFF BY %.1f m" % xz_off
		print("  (%5.3f, %5.3f)  y %7.2f  %+6.2f  xz %6.2f  (%7.1f,%7.1f)  want (%7.1f,%7.1f)  a %.3f%s" % [
			want_gx, want_gy, got, err, xz_off, got_x, got_z, want.x, want.z, c.a, flag])
	print("  samples checked: %d" % checked)
	print("  within %.1f m:    %d / %d" % [TOLERANCE, within, checked])
	print("  worst error:     %.2f m" % worst)
	print("  on-plate:        %d / %d" % [on_plate, checked])
	print("  on-target xz:    %d / %d" % [on_target, checked])
	if checked == 0:
		print("  VERDICT: no valid reference samples, the probe is aimed wrong")
	elif within == checked and on_target == checked:
		print("  VERDICT: reconstruction matches the known geometry everywhere sampled")
	elif within > checked / 2:
		print("  VERDICT: mostly right, some samples disagree, see above")
	else:
		print("  VERDICT: reconstruction is wrong")
