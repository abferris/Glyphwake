extends SceneTree

# Underwater look: the per camera environment tint that CameraController swaps in while the eye
# is under water, plus the water surface's underside mesh. Rendering itself cannot be judged from
# a headless run, so this checks the wiring and the numbers: the tint only exists below the
# waterline, it uses the water zone's shade, it gets denser with depth, and the above water
# surface is left exactly as it was.

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var zone: Area3D
var water: MeshInstance3D
var under: MeshInstance3D
var world_env: Environment
var frames := 0
var started := false
var phase := 0
var settle := 0
var shallow_density := -1.0
var deep_density := -1.0
var checks := 0
var failures := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 4:
		terrain_setup()
		return false
	if frames > 1500:
		print("WATCHDOG: test never reached its end (phase %d)" % phase)
		quit(1)
		return true
	if not started:
		return false

	# Deep first, then shallow, then head above water inside the zone. Every sample waits for a
	# few physics ticks after the teleport, because IsUnderwater is only re-evaluated there and
	# the float drifts the body in the meantime.
	match phase:
		1:
			player.global_position = Vector3(-750, 70.0, -1500)
			phase = 2
			settle = 0
		2:
			settle += 1
			if settle < 6:
				return false
			if deep_density < 0.0:
				surface_checks()
				deep_density = sample_density()
				check("deep eye is under water", player.IsUnderwater, "(depth %.2f m)" % (zone.WaterSurfaceY - camera.global_position.y))
				var env := camera.environment
				check("camera has an environment while submerged", env != null)
				if env:
					check("tint fog is enabled", env.fog_enabled)
					check("rendered fog colour matches the surface colour",
						(env.fog_light_color * env.fog_light_energy).is_equal_approx(camera.UnderwaterTint),
						"(rendered %s, surface %s)" % [env.fog_light_color * env.fog_light_energy, camera.UnderwaterTint])
					check("tint is not the world environment", env != world_env)
					check("fog energy is the export", is_equal_approx(env.fog_light_energy, camera.UnderwaterFogEnergy),
						"(%.2f)" % env.fog_light_energy)
					check("sky keeps some clarity", env.fog_sky_affect < 0.5, "(%.2f)" % env.fog_sky_affect)
					check("aerial perspective off", is_zero_approx(env.fog_aerial_perspective))
			player.global_position = Vector3(-750, 77.5, -1500)
			phase = 3
			settle = 0
		3:
			settle += 1
			if settle < 6:
				return false
			if shallow_density < 0.0:
				shallow_density = sample_density()
				check("shallow eye is under water", player.IsUnderwater, "(depth %.2f m)" % (zone.WaterSurfaceY - camera.global_position.y))
				check("deeper water is hazier", deep_density > shallow_density,
					"(deep %.4f > shallow %.4f)" % [deep_density, shallow_density])
				check("fog is bounded", deep_density <= camera.UnderwaterFogDeep + 0.0001,
					"(deep %.4f <= %.4f)" % [deep_density, camera.UnderwaterFogDeep])
			player.global_position = Vector3(-750, 85.0, -1500)
			phase = 4
			settle = 0
		4:
			settle += 1
			# long enough for the fade to finish clearing: at SubmersionFadeSpeed it takes about a
			# tenth of a second to come all the way back down, which is the point of fading at all
			if settle < 30:
				return false
			check("still swimming in the zone", player.IsSwimming)
			check("head is out of the water", not player.IsUnderwater, "(eye %.2f)" % camera.global_position.y)
			# The filter is gone above water because its strength is zero, not because the
			# environment was detached. Detaching it is what put a one frame hole in the tint on
			# the way through the surface, so the check is on the effect and not the mechanism.
			check("tint is off above water", camera.Submersion < 0.01,
				"(strength %.4f)" % camera.Submersion)
			finish()
	return false


func terrain_setup() -> void:
	# Start the run before any of the checks, so a failure inside them cannot leave the test
	# spinning forever.
	phase = 1
	started = true

	var terrain := world.get_node_or_null("Terrain3D")
	player = world.get_node_or_null("Player")
	camera = world.get_node_or_null("Player/Head/Camera3D")
	zone = world.get_node_or_null("WaterZone")
	water = world.get_node_or_null("Water")
	under = water.get_node_or_null("SurfaceFromBelow") if water else null
	world_env = (world.get_node_or_null("WorldEnvironment") as WorldEnvironment).environment
	if terrain and camera:
		terrain.set_camera(camera)

	player.global_position = Vector3(-750, 70.0, -1500)


func surface_checks() -> void:
	print("== water surface setup")
	var top := water.material_override as ShaderMaterial
	var topcode := String(top.shader.code) if top != null and top.shader != null else ""
	check("above water surface uses the water shader", top != null and top.shader != null
		and String(top.shader.resource_path) == "res://Shaders/water_from_above.gdshader",
		"(%s)" % (top.shader.resource_path if top != null and top.shader != null else "none"))
	# The underside mesh draws back faces, so the top surface has to keep drawing front faces or
	# the water vanishes when you look down at it.
	check("above water surface keeps back face culling", topcode.contains("cull_back"), "(cull_back)")

	# What the surface is for now: how much of the scene survives the water depends on the angle
	# and on how much water the ray crossed, so these guard the three pieces that produce that
	# instead of the single flat alpha this replaced.
	check("surface visibility is angle driven", topcode.contains("pow(1.0 - facing, fresnel_power)"),
		"(fresnel on the view angle)")
	check("surface visibility is depth driven",
		topcode.contains("hint_depth_texture") and topcode.contains("exp(-extinction * path)"),
		"(scene depth, beer-lambert)")
	check("grazing rays cross more water", topcode.contains("column / ray_cos"),
		"(path length grows towards the horizon)")

	# The point of all three: not a flat sheet. The old surface was a constant 0.72 everywhere, and
	# that is the one thing that must not come back.
	var shallow := float(top.get_shader_parameter("shallow_opacity")) if top != null else -1.0
	check("surface is not a flat sheet of alpha", shallow >= 0.0 and shallow < 0.5,
		"(shallow_opacity %.2f, replaced a flat 0.72)" % shallow)

	# The tint is meant to be the same water the player saw from above, so the two colours are
	# tied together on purpose and this keeps them tied.
	var tint: Color = camera.UnderwaterTint
	var surface := top.get_shader_parameter("shallow_color") as Color if top != null else Color(0, 0, 0, 0)
	check("tint matches the water surface colour",
		is_equal_approx(tint.r, surface.r) and is_equal_approx(tint.g, surface.g) and is_equal_approx(tint.b, surface.b),
		"(tint %s vs surface %s)" % [tint, surface])

	check("underside mesh exists", under != null)
	if under:
		var mat := under.material_override as ShaderMaterial
		check("underside uses the water shader", mat != null and mat.shader != null
			and String(mat.shader.resource_path) == "res://Shaders/water_from_below.gdshader",
			"(%s)" % (mat.shader.resource_path if mat and mat.shader else "none"))
		check("underside is coincident with the surface", under.mesh == water.mesh and under.transform == Transform3D.IDENTITY)
		if mat and mat.shader:
			var code: String = mat.shader.code
			check("shader only draws the underside", code.contains("cull_front"))
			# A split on the critical angle puts a hard-edged circle overhead, which reads as a
			# spotlight or a hole rather than as water, so the ramp has to span the whole dome.
			check("ceiling is graded with no critical-angle split",
				code.contains("smoothstep(0.0, 1.0, facing)") and not code.contains("critical_degrees"),
				"(%s)" % ("split removed" if not code.contains("critical_degrees") else "critical_degrees still declared"))
			# From below, straight up is the lit side and the grazing angles reflect the dim water.
			var win: Color = mat.get_shader_parameter("window_color")
			var mir: Color = mat.get_shader_parameter("mirror_color")
			check("window is brighter than the mirror", luma(win) > luma(mir),
				"(window %.3f vs mirror %.3f)" % [luma(win), luma(mir)])
			check("window and mirror are close enough not to form a disc", luma(win) < luma(mir) * 1.8,
				"(ratio %.2f)" % (luma(win) / maxf(luma(mir), 0.0001)))
			print("  shader parsed, %d bytes" % code.length())

	print("== underwater tint")
	print("  tint=%s near=%.3f deep=%.3f range=%.1f" % [camera.UnderwaterTint, camera.UnderwaterFogNear, camera.UnderwaterFogDeep, camera.UnderwaterDepthRange])


func sample_density() -> float:
	var env := camera.environment
	return env.fog_density if env else -1.0


func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func finish() -> void:
	print("== camera ownership")
	check("camera stays current in first person", camera.current)
	print("== %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("TEST UNDERWATER LOOK OK")
	else:
		print("TEST UNDERWATER LOOK FAILED")
	quit(0 if failures == 0 else 1)
