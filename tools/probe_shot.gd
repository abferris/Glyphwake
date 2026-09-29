extends SceneTree

# Scratch probe: renders real frames and saves PNGs, so visual work (underwater tint, the
# surface seen from below) can be checked without eyeballing a running game. Uses the real
# renderer, so it must run WITHOUT --headless. Output goes to tools/tmp_shots/.
#
# Every pose is rendered twice in a row, with the underside mesh visible and then hidden, so the
# pair differs only by the surface: diffing them shows exactly what the surface contributes from
# below, and confirms it contributes nothing from above the water.

const OUT := "res://tools/tmp_shots/"

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var under: MeshInstance3D
var frames := 0
var plan: Array = []
var index := 0
var state := "apply"  # apply -> settle -> lid -> plain -> next
var name := ""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	plan = [
		# deep water, looking up through the window
		{"pos": Vector3(-750, 74.0, -1500), "pitch": 0.42, "name": "1_under_looking_up"},
		# same spot, aimed past the critical angle at the mirrored lid
		{"pos": Vector3(-750, 74.0, -1500), "pitch": 1.15, "name": "2_under_mirror_lid"},
		# just under the surface: the lid is closer, brighter and less fogged
		{"pos": Vector3(-750, 79.3, -1500), "pitch": 1.05, "name": "3_under_shallow"},
		# deep and level: tint on the world, no lid overhead
		{"pos": Vector3(-750, 70.0, -1500), "pitch": 0.0, "name": "4_under_level"},
		# above the surface, to confirm that view is unchanged
		{"pos": Vector3(-750, 82.0, -1500), "pitch": -0.5, "name": "5_above_water"},
	]
	var ps := load("res://Scenes/World.tscn") as PackedScene
	world = ps.instantiate()
	root.call_deferred("add_child", world)


func _process(_delta: float) -> bool:
	frames += 1

	if frames > 900:
		print("WATCHDOG: probe never finished (index %d state %s)" % [index, state])
		quit(1)
		return true

	# The scene is added deferred, so keep asking until the nodes are actually there.
	if player == null:
		var terrain := world.get_node_or_null("Terrain3D") if world else null
		player = world.get_node_or_null("Player") if world else null
		camera = world.get_node_or_null("Player/Head/Camera3D") if world else null
		under = world.get_node_or_null("Water/SurfaceFromBelow") if world else null
		if not player or not camera or not under:
			return false
		if terrain:
			terrain.set_camera(camera)
		# do not grab the cursor while the probe window is up
		Input.mouse_mode = Input.MouseMode.MOUSE_MODE_VISIBLE
		return false

	if index >= plan.size():
		print("shots written to ", ProjectSettings.globalize_path(OUT))
		quit(0)
		return true

	var step: Dictionary = plan[index]
	# The float pulls the body while it settles, so hold the pose every frame.
	player.global_position = step["pos"]
	camera.LookPitch = step["pitch"]

	match state:
		"apply":
			name = String(step["name"])
			under.visible = true
			state = "settle"
		"settle":
			# let the camera placement, body pitch and fog density converge, then draw with the lid
			if frames % 6 == 0:
				state = "lid"
		"lid":
			_shoot("_lid.png")
			state = "plain"
		"plain":
			# hidden: the surface is back face culled, so this frame has no surface at all
			under.visible = false
			state = "plain_wait"
		"plain_wait":
			if frames % 2 == 0:
				_shoot("_nol.png")
				index += 1
				state = "apply"
	return false


func _shot_name(suffix: String) -> String:
	return OUT + name + suffix


func _shoot(suffix: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png(_shot_name(suffix))
	var env := camera.environment
	print("saved ", name + suffix, " err=", err,
		" eye=", snappedf(camera.global_position.y, 0.01),
		" under=", player.IsUnderwater,
		" fog=", snappedf(env.fog_density, 0.001) if env else 0.0)
