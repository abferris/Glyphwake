extends SceneTree

## Walking uphill: full speed to a threshold, slower above it, a wall above that.
##
## Three bands, and all three limits are read off the player rather than written here, because all
## three move with tuning: slopes up to SlopeFullSpeedDeg at full speed, from there down to
## SlopeMinSpeedFactor at SlopeMaxAngleDeg, and past SlopeMaxAngleDeg not walkable at all. The
## speed that is measured is the body's own velocity along the slope, because that is what the
## player feels -- climbing a 50 deg face moves you less far along the ground per second, and
## reading the horizontal component would flatter every steep case.
##
## Ramps are built on dry land, so nothing here goes near the water and the wading speed factor
## cannot be mistaken for the slope one. The body is placed on the face itself rather than at its
## foot, which keeps the ramp from being a step to climb onto first and leaves the measurement
## about the slope rather than about the transition.

const SCAN := 60
const RAMP_WIDTH := 20.0
const RAMP_THICK := 2.0
const RAMP_RUN := 16.0     # horizontal metres of slope
const START_ALONG := 4.0   # where on the face the body starts, measured from the foot
const SETTLE_TICKS := 30
const MEASURE_TICKS := 90
const FOOT_OFFSET := 0.889  # capsule bottom below the player origin

## The bands, each expressed against the tuned limit it is testing rather than as a number.
const BANDS := [
	{"deg": 0.0, "kind": "flat"},
	{"deg": 35.0, "kind": "flat"},      # replaces SlopeFullSpeedDeg at run time
	{"deg": 47.5, "kind": "slow"},
	{"deg": 57.5, "kind": "slow"},
	{"deg": 66.0, "kind": "wall"},      # replaces SlopeMaxAngleDeg at run time
]

var world: Node3D
var player: CharacterBody3D
var zone: Area3D
var camera: Camera3D
var ramp: StaticBody3D
var ticks := 0
var phase := 0
var phase_start := 0
var scenario := 0
var origin := Vector3.ZERO
var dry_ground := 0.0
var move_key := 0
var dir := Vector3.ZERO
var held := 0
var band_deg := 0.0
var band_kind := ""
var along := Vector3.ZERO   # unit vector pointing up the face, horizontal
var speed_sum := 0.0
var speed_n := 0
var rows := []
var failed := false


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	ev.echo = false
	Input.parse_input_event(ev)


func hold(code: int) -> void:
	if held == code:
		return
	if held != 0:
		_key(held, false)
	held = code
	if code != 0:
		_key(code, true)


## Which movement key walks toward a world direction. Ground movement steers off the body, whose
## yaw is settled at spawn, so the key that reads as "that way" from there can be picked; unlike
## swimming there is no private camera yaw in the way.
func key_for(want: Vector3) -> int:
	var local := player.global_transform.basis.inverse() * want
	if absf(local.z) >= absf(local.x):
		return KEY_W if local.z < 0.0 else KEY_S
	return KEY_D if local.x > 0.0 else KEY_A


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 4:
		return false

	if phase == 0:
		if ticks < 20:
			return false
		player = world.get_node_or_null("Player")
		zone = world.get_node_or_null("WaterZone")
		camera = world.get_node_or_null("Player/Head/Camera3D")
		if not _scan():
			printerr("FAIL: nowhere dry to build a ramp on")
			quit(1)
			return true
		phase = 1
		phase_start = ticks
		return false

	if phase == 1:
		if ticks - phase_start < 4:
			return false
		band_deg = BANDS[scenario]["deg"]
		band_kind = BANDS[scenario]["kind"]
		match band_kind:
			"flat":
				if scenario == 1:
					band_deg = player.SlopeFullSpeedDeg
			"wall":
				band_deg = player.SlopeMaxAngleDeg + 6.0
		_build(band_deg)
		phase = 2
		phase_start = ticks
		return false

	# Settle on the face before measuring, so the first samples are not the body dropping onto it.
	if phase == 2:
		if ticks - phase_start < SETTLE_TICKS:
			return false
		# The face is measured back off the collision that was built, not assumed: the speed
		# bands are about the angle the body is actually standing on. A shape added this tick is
		# not in the space yet, so this runs one tick on rather than inside _build.
		var ss := player.get_world_3d().direct_space_state
		for t in [START_ALONG, START_ALONG + 2.0, START_ALONG + 4.0]:
			var at := Vector3(origin.x, dry_ground, origin.z) + dir * float(t)
			var hy := ground_at(ss, at.x, at.z)
			if not is_nan(hy):
				print("   ", snappedf(float(t), 0.01), "m along: ground=", snappedf(hy, 0.01))
		speed_sum = 0.0
		speed_n = 0
		rows.clear()
		phase = 3
		phase_start = ticks
		hold(move_key)
		return false

	if phase == 3:
		var step: int = ticks - phase_start
		rows.append({
			"step": step,
			"y": player.global_position.y,
			"along": Vector2(player.velocity.x, player.velocity.z).dot(Vector2(along.x, along.z)),
			"floor": player.is_on_floor(),
			"clip": String(player.AnimationState).strip_edges(),
		})
		if step > 10:
			speed_sum += float(rows[rows.size() - 1]["along"])
			speed_n += 1
		if step > MEASURE_TICKS:
			hold(0)
			_report()
			scenario += 1
			if scenario >= BANDS.size():
				print("TEST SLOPE SPEED ", "FAILED" if failed else "OK")
				quit(1 if failed else 0)
				return true
			phase = 1
			phase_start = ticks
			return false
		return false

	return false


## A ramp whose top face rises along dir at the given angle. The foot sits on the ground at the
## dry spot and the face runs RAMP_RUN metres back from there.
func _build(deg: float) -> void:
	if ramp:
		ramp.queue_free()
		ramp = null
	var a := deg_to_rad(deg)
	var axis := Vector3.UP.cross(dir).normalized()
	var normal := Vector3.UP.rotated(axis, -a)
	var slope_len := RAMP_RUN / cos(a)

	var foot := Vector3(origin.x, dry_ground, origin.z)
	var top_mid := foot + dir * (RAMP_RUN * 0.5) + Vector3.UP * (RAMP_RUN * 0.5 * tan(a))

	ramp = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RAMP_WIDTH, RAMP_THICK, slope_len)
	shape.shape = box
	ramp.add_child(shape)
	world.add_child(ramp)
	ramp.global_transform = Transform3D(Basis(axis, -a), top_mid - normal * (RAMP_THICK * 0.5))

	# Put the body on the face, a little clear of it, pointing up it.
	var on_face := foot + dir * START_ALONG + Vector3.UP * (START_ALONG * tan(a) + 1.2)
	player.global_position = on_face
	var face_dir := (dir + Vector3.UP * tan(a)).normalized()
	player.look_at(player.global_position + face_dir, Vector3.UP)
	along = Vector3(dir.x, 0.0, dir.z).normalized()
	move_key = key_for(dir)
	print("band ", scenario, " ", band_kind, " ", snappedf(band_deg, 0.01), "deg rise over 1m=",
		snappedf(tan(a), 0.01), " key=", move_key)

func _report() -> void:
	var speed := speed_sum / float(speed_n)
	var last: Dictionary = rows[rows.size() - 1]
	var gain := float(last["y"]) - float(rows[0]["y"])
	print("   speed=", snappedf(speed, 0.01), " m/s  climbed=", snappedf(gain, 0.01),
		" m  floor=", last["floor"], " clip=\"", last["clip"], "\"")

	if band_kind == "flat":
		var want: float = player.MoveSpeed
		if speed < want * 0.9:
			printerr("FAIL: ", snappedf(band_deg, 0.01), "deg should be full speed, got ",
				snappedf(speed, 0.01), " of ", snappedf(want, 0.01))
			failed = true
		return

	if band_kind == "slow":
		var floor_speed: float = player.MoveSpeed * player.SlopeMinSpeedFactor
		if speed >= player.MoveSpeed * 0.9:
			printerr("FAIL: ", snappedf(band_deg, 0.01), "deg is past SlopeFullSpeedDeg ",
				snappedf(player.SlopeFullSpeedDeg, 0.01), " but still moved at ", snappedf(speed, 0.01))
			failed = true
		if speed < floor_speed * 0.9:
			printerr("FAIL: ", snappedf(band_deg, 0.01), "deg moved at ", snappedf(speed, 0.01),
				", under the ", snappedf(floor_speed, 0.01), " floor SlopeMinSpeedFactor implies")
			failed = true
		if gain <= 0.0:
			printerr("FAIL: ", snappedf(band_deg, 0.01), "deg is inside SlopeMaxAngleDeg ",
				snappedf(player.SlopeMaxAngleDeg, 0.01), " but climbed ", snappedf(gain, 0.01), " m")
			failed = true
		return

	# Past SlopeMaxAngleDeg the ground is a wall, and the body must not get up it at all.
	if gain > 0.5:
		printerr("FAIL: climbed ", snappedf(gain, 0.01), " m up a ", snappedf(band_deg, 0.01),
			" deg face, which is past SlopeMaxAngleDeg ", snappedf(player.SlopeMaxAngleDeg, 0.01))
		failed = true


func ground_at(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, zone.WaterSurfaceY + 200, z), Vector3(x, zone.WaterSurfaceY - 200, z))
	q.exclude = [player.get_rid()]
	var hit := ss.intersect_ray(q)
	return hit["position"].y if hit.has("position") else NAN


## Dry land with room around it for a ramp: the ground has to be well clear of the water, and
## flat for long enough in both directions that the ramp is not buried in a hillside.
func _scan() -> bool:
	var ss := player.get_world_3d().direct_space_state
	var surface: float = zone.WaterSurfaceY
	player.global_position = Vector3(0, 400, 0)
	for z in range(-2000, 2000, SCAN):
		for x in range(-2000, 2000, SCAN):
			var hy := ground_at(ss, x, z)
			if is_nan(hy) or hy < surface + 2.0:
				continue
			for d in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				var flat := true
				for t in [START_ALONG, START_ALONG + 4.0, START_ALONG + 8.0, START_ALONG + 12.0, START_ALONG + RAMP_RUN]:
					var at := Vector3(x + d.x * float(t), 0.0, z + d.z * float(t))
					var ah := ground_at(ss, at.x, at.z)
					if is_nan(ah) or absf(ah - hy) > 1.5:
						flat = false
						break
				if not flat:
					continue
				origin = Vector3(x, 0.0, z)
				dry_ground = hy
				dir = d
				print("dry at ", origin, " ground=", snappedf(hy, 0.01),
					" (", snappedf(hy - surface, 0.01), "m above water) dir=", dir)
				return true
	return false