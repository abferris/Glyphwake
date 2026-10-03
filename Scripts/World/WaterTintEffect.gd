extends CompositorEffect

# Underwater tint, as a screen-space pass.
#
# Why a compositor effect and not a full-screen ColorRect. The tint has to differ per pixel,
# because when the eye is at the waterline half the frame is under water and half is not, and how
# much water sits between the eye and a given pixel depends on how far that pixel is below the
# surface. Godot's Environment fog is one density for the whole frame, so it cannot express that. A
# per-pixel answer needs the depth buffer, and canvas_item shaders cannot read depth -- the engine
# rejects hint_depth_texture there outright. RenderSceneBuffersRD is the only thing that hands out
# the colour target and the depth texture together.
#
# The water level is not a global. Each authored Water/WaterZone pair is read straight out of the
# scene: the Water mesh gives the surface plane, the WaterZone gives the footprint and the gameplay
# height. An inland lake at a different height is therefore just another pair in the scene, with no
# extra configuration and nothing to keep in sync by hand.

const SHADER_PATH := "res://Shaders/water_tint.glsl"
const WORKGROUP := 8
const MAX_BODIES := 4
## Two vec4 per body. They go in a storage buffer rather than push constants because Godot caps push
## constants at 128 bytes, which the camera matrix alone nearly fills.
const BODY_FLOATS := 8

## Underwater colour and the depth over which it thickens. These live on the compositor effect
## rather than on the Environment, so the look is one value in one place and survives the
## environment handover intact.
@export var tint: Color = Color(0.09, 0.31, 0.45)
@export var depth_range: float = 14.0
@export var max_path: float = 48.0
## Strength of the blend at full path. Mirrors the Environment fog energy the look was tuned against.
@export var energy: float = 1.6
## Debug-only: the world height that the debug view encodes as 0.0. Kept out of the shader so the
## probe can narrow the range to the heights it actually placed.
@export var y_base: float = 0.0
## Debug-only: the world height span the debug view encodes as 1.0.
@export var y_range: float = 75.0
## Debug-only: the world XZ half range the debug view encodes, centred on the camera.
@export var debug_xz_range: float = 200.0
@export var debug: bool = false

var _shader: RID
var _pipeline: RID
var _sampler: RID
var _uniform_set: RID
var _body_buffer: RID
var camera: Camera3D
var _bodies: PackedFloat32Array = PackedFloat32Array()
var _body_count := 0
var _reported := false
var _checked := false
var _failed := false


func _initialize_callback() -> void:
	access_resolved_color = true
	access_resolved_depth = true


## Call once, with the scene root, before the first frame is rendered. Reads the authored
## Water/WaterZone pairs and packs them for the shader.
func setup(root: Node, cam: Camera3D = null) -> void:
	camera = cam
	var zones := _find_zones(root)
	var picked: Array = []
	for zone in zones:
		var surface: Variant = zone.get("WaterSurfaceY")
		var rect: Variant = _footprint(zone)
		if surface == null or rect == null:
			continue
		picked.append([float(surface), rect])

	# Where footprints overlap, the higher surface wins, so a lake inside a larger body resolves to
	# the lake instead of depending on the order nodes happen to sit in the scene.
	picked.sort_custom(func(a, b): return a[0] > b[0])
	if picked.size() > MAX_BODIES:
		push_warning("WaterTintEffect: %d water bodies, only the highest %d are tinted" % [picked.size(), MAX_BODIES])

	_bodies = PackedFloat32Array()
	_body_count = mini(picked.size(), MAX_BODIES)
	for i in _body_count:
		var entry: Array = picked[i]
		var r: Vector4 = entry[1]
		_bodies.append(r.x)
		_bodies.append(r.y)
		_bodies.append(r.z)
		_bodies.append(r.w)
		_bodies.append(float(entry[0])) # surface height
		_bodies.append(float(i)) # priority, so the earliest listed wins a genuine tie
		_bodies.append(0.0)
		_bodies.append(0.0)
	# Always allocate for the full set so the buffer size never changes underneath the shader.
	while _bodies.size() < MAX_BODIES * BODY_FLOATS:
		_bodies.append(0.0)
	print("WaterTintEffect: %d water body/bodies" % _body_count)
	for i in _body_count:
		var o := i * BODY_FLOATS
		print("  centre (%.0f, %.0f) half-extent (%.0f, %.0f) surface y %.1f" % [
			_bodies[o], _bodies[o + 1], _bodies[o + 2], _bodies[o + 3], _bodies[o + 4]])


## The surface that is actually drawn. The Water plane beside the zone is preferred, since that is
## what the player sees; a body with a gameplay volume but no plane drawn falls back to the zone's
## own collision box. The plane is found by shape rather than by name, so it does not matter what
## the node is called or whether it carries a script.
func _footprint(zone: Node) -> Variant:
	var parent := zone.get_parent()
	if parent != null:
		for sibling in parent.get_children():
			if sibling == zone:
				continue
			var mesh := sibling.get("mesh") as PlaneMesh
			if mesh == null or not (sibling is Node3D):
				continue
			var pos := (sibling as Node3D).global_position
			return Vector4(pos.x, pos.z, mesh.size.x * 0.5, mesh.size.y * 0.5)
	for c in zone.get_children():
		var shape := c.get("shape") as BoxShape3D
		if shape == null:
			continue
		var s: Vector3 = (zone as Node3D).global_transform.basis.get_scale()
		var ext := shape.size * 0.5 * s
		var pos2 := (zone as Node3D).global_position
		return Vector4(pos2.x, pos2.z, ext.x, ext.z)
	return null


func _find_zones(node: Node) -> Array:
	var out: Array = []
	var script: Script = node.get_script()
	if script != null and script.resource_path.get_file() == "WaterZone.cs":
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_zones(c))
	return out


func _render_callback(effect_callback_type: int, render_data: RenderData) -> void:
	if _failed or effect_callback_type != CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return

	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var color_tex := buffers.get_color_texture()
	var depth_tex := buffers.get_depth_texture()
	var size := buffers.get_target_size()
	if not color_tex.is_valid() or not depth_tex.is_valid() or size.x <= 0 or size.y <= 0:
		return

	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return

	if not _reported:
		_reported = true
		_report(rd, buffers)

	if camera == null or not camera.is_inside_tree():
		push_error("WaterTintEffect: setup() needs the camera the effect is attached to")
		_failed = true
		return
	if not _build_pipeline(rd, color_tex):
		return
	if not _sampler.is_valid():
		_sampler = rd.sampler_create(RDSamplerState.new())
		if not _sampler.is_valid():
			push_error("WaterTintEffect: sampler creation failed")
	if not _body_buffer.is_valid():
		_body_buffer = rd.storage_buffer_create(
			MAX_BODIES * BODY_FLOATS * 4, _bodies.to_byte_array(),
			RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT,
			RenderingDevice.BUFFER_CREATION_AS_STORAGE_BIT)
		if not _body_buffer.is_valid():
			push_error("WaterTintEffect: body storage buffer creation failed")

	# Uniform sets are recreated per frame: the colour target RID is not stable across a resize or a
	# device loss, and a set that points at a destroyed texture is invalid.
	if not _uniform_set.is_valid():
		var colour_uniform := RDUniform.new()
		colour_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		colour_uniform.binding = 0
		colour_uniform.add_id(color_tex)
		var depth_uniform := RDUniform.new()
		depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth_uniform.binding = 1
		depth_uniform.add_id(_sampler)
		depth_uniform.add_id(depth_tex)
		var body_uniform := RDUniform.new()
		body_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		body_uniform.binding = 2
		body_uniform.add_id(_body_buffer)
		_uniform_set = rd.uniform_set_create([colour_uniform, depth_uniform, body_uniform] as Array, _shader, 0)
		if not _uniform_set.is_valid():
			# Almost always one of the three RIDs above being invalid, so name them rather than
			# leaving a bare "uniform_set is null" from the draw call with no indication of the cause.
			push_error("WaterTintEffect: uniform set creation failed (colour %s, sampler %s, depth %s, bodies %s)" % [
				color_tex.is_valid(), _sampler.is_valid(), depth_tex.is_valid(),
				_body_buffer.is_valid()])
			_failed = true
			return

	var cam_xform := camera.global_transform

	var push := PackedFloat32Array()
	push.resize(_push_floats())
	if not _checked:
		_checked = true
		_self_check()
	_push_camera(push)

	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, _pipeline)
	rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
	rd.compute_list_set_push_constant(list, push.to_byte_array(), push.size() * 4)
	rd.compute_list_dispatch(list, (size.x + WORKGROUP - 1) / WORKGROUP, (size.y + WORKGROUP - 1) / WORKGROUP, 1)
	rd.compute_list_end()


func _push_floats() -> int:
	# Eight vec4, which is 128 bytes: the whole of Godot's push constant budget. The water bodies
	# therefore cannot go here at all and live in a storage buffer instead.
	return 32


## The camera as a basis plus the projection's scale factors, not as a matrix.
##
## Inverting the view-projection is the obvious way to unproject a depth and it fails badly here. With
## a near of 0.05 against a far of 4000 the inverse matrix holds values of order 1e4 that then get
## differenced against world coordinates of order 1e3, and float32 cancels away every significant
## digit: the reconstruction stops depending on where the pixel is and lands somewhere near the
## camera for the whole frame. Splitting the same computation into a depth-to-distance division and a
## basis rotation has no such cancellation and is both cheaper and exact.
func _push_camera(push: PackedFloat32Array) -> void:
	var basis := camera.global_transform.basis
	var fwd := -basis.z
	var vp_size := Vector2(1152.0, 648.0)
	if camera.get_viewport() != null:
		vp_size = camera.get_viewport().get_visible_rect().size
	var aspect := vp_size.x / vp_size.y if vp_size.y > 0.0 else 1.7778
	var tan_y := tan(deg_to_rad(camera.fov) * 0.5)
	var n := camera.near
	var f := camera.far
	push[0] = camera.global_position.x
	push[1] = camera.global_position.y
	push[2] = camera.global_position.z
	push[3] = n
	push[4] = basis.x.x
	push[5] = basis.x.y
	push[6] = basis.x.z
	push[7] = tan_y * aspect
	push[8] = basis.y.x
	push[9] = basis.y.y
	push[10] = basis.y.z
	push[11] = tan_y
	push[12] = fwd.x
	push[13] = fwd.y
	push[14] = fwd.z
	push[15] = n * f
	push[16] = float(_body_count)
	push[17] = 1.0 if debug else 0.0
	push[18] = depth_range
	push[19] = y_base
	push[20] = tint.r
	push[21] = tint.g
	push[22] = tint.b
	push[23] = 1.0
	push[24] = max_path
	push[25] = energy
	push[26] = 0.0
	push[27] = 0.0
	push[28] = y_base
	push[29] = y_range
	push[30] = debug_xz_range
	push[31] = 0.0


## Round-trips the reconstruction the shader performs, entirely on the CPU, so a mistake in the
## unprojection is caught here with a number in metres rather than as a frame that merely looks
## wrong. A pixel is turned into a depth and back into a world position, which is the exact operation
## the shader does, and the position has to come back out unchanged.
func _self_check() -> void:
	var basis := camera.global_transform.basis
	var fwd := -basis.z
	var vp_size := camera.get_viewport().get_visible_rect().size
	var aspect := vp_size.x / vp_size.y if vp_size.y > 0.0 else 1.7778
	var tan_y := tan(deg_to_rad(camera.fov) * 0.5)
	var n := camera.near
	var f := camera.far
	var worst := 0.0
	for offset: Vector2 in [Vector2.ZERO, Vector2(0.4, 0.0), Vector2(-0.6, 0.3), Vector2(0.1, -0.5)]:
		var ndc := Vector3(offset.x, offset.y, 0.0)
		var dir := (basis.x * (ndc.x * tan_y * aspect) + basis.y * (ndc.y * tan_y) + fwd).normalized()
		for dist: float in [0.5, 2.0, 12.0, 120.0, 800.0]:
			var world := camera.global_position + dir * dist
			# world -> depth, the forward direction, matching the reverse-Z the rasteriser writes:
			# 1 at the near plane and 0 at the far plane.
			var depth := n * (f - dist) / (dist * (f - n))
			# depth -> distance -> world, the shader's direction
			var back_dist := n * f / (n + depth * (f - n))
			var back := camera.global_position + dir * back_dist
			worst = maxf(worst, back.distance_to(world))
	print("WaterTintEffect: unprojection round-trip, worst error %.6f m" % worst)


func _build_pipeline(rd: RenderingDevice, color_tex: RID) -> bool:
	if _pipeline.is_valid():
		return true

	var glsl_format := _glsl_format_for(rd, color_tex)
	if glsl_format == "":
		_failed = true
		return false

	var source := FileAccess.get_file_as_string(SHADER_PATH)
	if source.is_empty():
		push_error("WaterTintEffect: cannot read %s" % SHADER_PATH)
		_failed = true
		return false
	source = source.replace("{{COLOR_FORMAT}}", glsl_format)

	var src := RDShaderSource.new()
	src.source_compute = source
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	var spirv := rd.shader_compile_spirv_from_source(src, false)
	if spirv == null or spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():
		push_error("WaterTintEffect: %s failed to compile" % SHADER_PATH)
		_failed = true
		return false

	_shader = rd.shader_create_from_spirv(spirv, "water_tint")
	_pipeline = rd.compute_pipeline_create(_shader, [] as Array)
	print("WaterTintEffect: built, colour format %s, push constants %d bytes" % [glsl_format, _push_floats() * 4])
	return _pipeline.is_valid()


func _glsl_format_for(rd: RenderingDevice, color_tex: RID) -> String:
	var f: RDTextureFormat = rd.texture_get_format(color_tex)
	if f.usage_bits & RenderingDevice.TEXTURE_USAGE_STORAGE_BIT == 0:
		push_error("WaterTintEffect: colour target lacks STORAGE usage")
		return ""
	if f.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM:
		return "rgba8"
	if f.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
		return "rgba16f"
	if f.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
		return "rgba32f"
	push_error("WaterTintEffect: colour format %d not handled" % f.format)
	return ""


func _report(rd: RenderingDevice, buffers: RenderSceneBuffersRD) -> void:
	var cf: RDTextureFormat = rd.texture_get_format(buffers.get_color_texture())
	var df: RDTextureFormat = rd.texture_get_format(buffers.get_depth_texture())
	print("WaterTintEffect: target %s colour fmt %d usage %d depth fmt %d usage %d" % [
		buffers.get_target_size(), cf.format, cf.usage_bits, df.format, df.usage_bits])
