extends SceneTree

## Underwater filter seamlessness: breaking the surface must not flash.
##
## Swapping the filter onto the camera as a hard boolean on IsUnderwater leaves a frame with no
## filter in it: the eye crosses the waterline, the environment gets cleared, and the tint only
## lands once the swap does. Treading on the spot makes it worse, because the float nudges the eye
## across the threshold repeatedly and every crossing would be a full pop of the tint on and off.
##
## The filter is faded now, and the environment is left on the camera with its density taken to
## zero instead of being detached. This walks the eye down through the surface at a swimming pace
## and back up again, and checks the three things that keep the flash out:
##
##   - it cannot change faster than SubmersionFadeSpeed, so a step can never appear
##   - it never drops out once the eye is properly under, so it cannot flicker
##   - the environment is still attached while submerged, so there is no frame without a filter
##   - the swim lift is eased rather than teleported when the view is pitched down to dive
##
## The rate check is against measured elapsed time rather than a frame count, so it holds at any
## frame rate instead of assuming 60 Hz.

const SURFACE_Y := 80.0
const START_Y := 84.0
# Slow enough that the fade gets sampled properly rather than jumped over in one frame.
const STEP := 0.02
const TOLERANCE := 0.05
# The pitch sweep that would teleport the eye if the lift snapped, and how far the swim lift is
# allowed to move it per frame on top of the measured interval.
const LIFT_SWEEP := 24
const LIFT_RISE := 45
const LIFT_TOLERANCE := 0.02

var world: Node3D
var player: CharacterBody3D
var cam: Camera3D
var zone: Area3D
var checks := 0
var failures := 0
var phase := 0
var settle := 0
var rows: Array = []
var last_usec := 0
var walking := false
var failed := false
var worst_jump := 0.0
var worst_jump_at := 0.0
var hole_ticks := 0
var partial := 0
var flicker := 0
var closest_depth := 99.0
var closest_blend := -1.0
var ticks := 0
var target_y := 0.0
var _saved_engage := 0.0
var lift_ticks := 0
var prev_eye := 0.0
var last_lift_usec := 0
var worst_lift_jump := 0.0
var lift_failed := false
var lift_reported := false
var above_fog := -1.0
var min_under_fog := 1e9
var max_under_fog := -1.0


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	world = (load("res://Scenes/World.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", world)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks > 4000:
		_fail("the walk never finished (phase %d, eye %.2f)" % [phase, cam.global_position.y if cam else -1.0])
		_finish()
		return true

	if phase == 0:
		# the world is added deferred, so nothing may be read off it until it is in the tree
		if not world.is_inside_tree() or world.get_node_or_null("Player") == null:
			return false
		player = world.get_node_or_null("Player")
		cam = world.get_node_or_null("Player/Head/Camera3D")
		zone = world.get_node_or_null("WaterZone")
		if player == null or cam == null or zone == null:
			_fail("player, camera or WaterZone missing from the world")
			_finish()
			return true
		if absf(zone.WaterSurfaceY - SURFACE_Y) > 0.01:
			_fail("the test is written against a water surface at %.1f" % SURFACE_Y)
			_finish()
			return true
		# The surface float springs the body back to the waterline, which pins the eye on the
		# threshold and will not let it be walked down at a slow, even pace. Pushing the float
		# engagement depth out of reach turns it off for the duration so the eye can be driven
		# down at a walking pace, which is what puts samples inside the fade. Nothing here cares
		# about the swim pose.
		_saved_engage = player.FloatEngageDepth
		player.FloatEngageDepth = 5.0
		# inside the zone (55..105) but with the eye clear of the water, so the filter starts off
		player.global_position = Vector3(-750.0, START_Y, -1500.0)
		target_y = START_Y
		phase = 1
		return false

	settle += 1
	if settle < 10:
		return false

	if phase == 1:
		# down through the surface and on until the filter is at full strength. Written as an
		# absolute height each tick so gravity between writes cannot make the walk uneven.
		target_y -= STEP
		player.global_position.y = target_y
		_sample()
		if cam.global_position.y < SURFACE_Y - cam.SubmersionOn - 0.5:
			phase = 2
			walking = false
			settle = 0
		return false

	if phase == 2:
		# back up through it the same way, to catch the filter dropping out on the way too
		target_y += STEP
		player.global_position.y = target_y
		_sample()
		if cam.global_position.y > SURFACE_Y + 0.5:
			phase = 3
			settle = 0
			# park the eye above the water and let the swim lift take hold, so the pitch sweep
			# below is measuring the lift rather than the walk
			target_y = SURFACE_Y + 1.0
			player.global_position.y = target_y
			prev_eye = cam.global_position.y
			last_lift_usec = 0
		return false

	if phase == 3:
		# Let the swim lift rise all the way first. The snap only fired when the lift was already
		# up and the target dropped below it, so sweeping the pitch from an already lowered lift
		# cannot catch it: the lift has to reach SwimCameraLift while the eye is clear of the
		# water, and only then does the view go down.
		player.global_position.y = target_y
		cam.LookPitch = 0.0
		lift_ticks += 1
		if lift_ticks > LIFT_RISE:
			phase = 4
			lift_ticks = 0
			prev_eye = cam.global_position.y
			last_lift_usec = 0
		return false

	if phase == 4:
		# Hold the eye above the water and sweep the view down past DiveLookDownDeg. Diving means
		# looking down, and hard-assigning the lift the moment the target drops would put the eye a
		# whole SwimCameraLift lower in one frame: straight past the surface and deep enough to be
		# fully underwater, while the tint was still fading up from nothing. That is the flash, and
		# it lands on every crossing because the swim lift reaches zero at exactly the angle the
		# dive engages at.
		player.global_position.y = target_y
		# flick the view down the way a player does, rather than easing it: the target lift has to
		# go from the full SwimCameraLift to nothing between one frame and the next
		cam.LookPitch = 0.0 if lift_ticks == 1 else -0.7
		var now := Time.get_ticks_usec()
		if last_lift_usec > 0 and lift_ticks > 1:
			var dt := float(now - last_lift_usec) / 1000000.0
			var jump := absf(cam.global_position.y - prev_eye)
			# the lift is meant to be eased at SwimLiftSpeed, so anything faster than that is a
			# teleport and is exactly the bug
			var allowed: float = cam.SwimLiftSpeed * dt + LIFT_TOLERANCE
			if jump > allowed:
				lift_failed = true
				if not lift_reported:
					lift_reported = true
					print("  FAIL the eye jumped %.3f m in %.4f s while looking down, more than the %.1f/s lift allows" % [jump, dt, cam.SwimLiftSpeed])
			if jump > worst_lift_jump:
				worst_lift_jump = jump
		last_lift_usec = now
		prev_eye = cam.global_position.y
		lift_ticks += 1
		if lift_ticks > LIFT_SWEEP:
			phase = 5
		return false

	_finish()
	return true


func _sample() -> void:
	var now := Time.get_ticks_usec()
	var blend: float = cam.Submersion
	var depth: float = zone.WaterSurfaceY - cam.global_position.y
	if now > 0 and last_usec > 0:
		var dt := float(now - last_usec) / 1000000.0
		var allowed: float = cam.SubmersionFadeSpeed * dt + TOLERANCE
		var jump: float = absf(blend - rows[-1]["blend"]) if not rows.is_empty() else 0.0
		if jump > worst_jump:
			worst_jump = jump
			worst_jump_at = rows[-1]["t"] if not rows.is_empty() else 0
		# a jump past what the fade rate can produce in the time between samples is a step
		if jump > allowed:
			_fail("the filter stepped %.3f in %.4f s at t=%d, more than the %.1f/s fade allows" % [jump, dt, rows[-1]["t"], cam.SubmersionFadeSpeed])
	last_usec = now
	rows.append({"t": rows.size(), "blend": blend, "depth": depth})

	# The old code could only ever produce 0 or 1, so a sample that lands strictly between them
	# is proof the filter is a fade and not a switch. That is the regression this test exists for.
	if blend > 0.05 and blend < 0.95 and depth > 0.0:
		partial += 1

	# Flicker is the filter going back down while the eye is still going down. Lagging behind the
	# eye is fine and expected; reversing is not.
	if not rows.is_empty():
		var pd: float = rows[-1]["depth"]
		var pb: float = rows[-1]["blend"]
		if depth > pd + 0.01 and blend < pb - 0.02:
			flicker += 1

	if absf(depth) < closest_depth:
		closest_depth = absf(depth)
		closest_blend = blend

	# the environment must never be detached while there is water above the eye, because detaching
	# it is precisely what left a frame with no filter in it
	if depth > 0.0 and not cam.UnderwaterFilterApplied:
		hole_ticks += 1

	# The fog density *is* the tint, so track it directly. Above the surface it has to be exactly
	# zero: the world's own environment carries 0.45 of blue aerial fog, and the camera carrying
	# its own environment at zero density is the only reason that never shows up above water. Any
	# blending up from the world's value puts a blue haze over the whole above-water look.
	var fog: float = cam.UnderwaterFogDensity
	# only once the filter has fully cleared, since part way through the fade the density is meant
	# to be somewhere between clear and full
	if blend < 0.001:
		above_fog = fog
	if depth > 0.15 and blend > 0.9:
		min_under_fog = minf(min_under_fog, fog)
		max_under_fog = maxf(max_under_fog, fog)


func _fail(msg: String) -> void:
	if not failed:
		failed = true
		print("  FAIL %s" % msg)


func _finish() -> void:
	print("== underwater filter")
	if _saved_engage > 0.0:
		player.FloatEngageDepth = _saved_engage
	var peak := 0.0
	for r in rows:
		peak = maxf(peak, r["blend"])
	check("filter is continuous, never steps", not failed,
		"(worst single sample jump %.3f)" % worst_jump)
	check("filter reaches full strength underwater", peak > 0.98, "(peak %.3f)" % peak)
	check("filter is off at the waterline", closest_blend >= 0.0 and closest_blend < 0.05,
		"(%.3f at %.3f m from the surface)" % [closest_blend, closest_depth])
	check("filter fades through intermediate values on the way down", partial > 0,
		"(%d samples between 0.05 and 0.95; a switch can only give 0 or 1)" % partial)
	check("filter does not flicker back down while descending", flicker == 0,
		"(%d reversals)" % flicker)
	check("environment stays attached, so no frame has no filter", hole_ticks == 0,
		"(%d detached frames)" % hole_ticks)
	check("the swim lift is eased, not teleported, when looking down to dive", not lift_failed,
		"(worst single frame eye jump %.3f m over a %.1f m lift)" % [worst_lift_jump, cam.SwimCameraLift])
	check("above water there is no haze at all, so the world's own fog never shows through",
		above_fog >= 0.0 and above_fog < 0.001,
		"(fog %.4f with the filter cleared)" % above_fog)
	check("the water haze is strong enough to carry the tint by itself",
		min_under_fog < 1e8 and min_under_fog > 0.5,
		"(lowest %.3f at full tint, highest %.3f)" % [min_under_fog, max_under_fog])
	print("== %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
