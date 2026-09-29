using Godot;

public partial class CameraController : Camera3D
{
	[Export] public float MouseSensitivity = 0.15f;
	[Export] public float MinPitch = -85f;
	[Export] public float MaxPitch = 85f;
	[Export] public float MinPitchInWater = -90f;
	[Export] public float MaxPitchInWater = 90f;
	[Export] public float FieldOfView = 70f;
	[Export] public bool CaptureMouseOnStart = true;
	[Export] public float SwimCameraLift = 0.8f;
	[Export] public float SwimLiftSpeed = 6f;
	[Export] public float EyeOffset = 0.08f;
	[Export] public float FaceReach = 0.35f;

	// Underwater look. The world environment is duplicated at runtime and swapped onto this
	// camera only while the eye is under water, so the tint exists below the surface and
	// nowhere else. The colour is the water surface's own albedo colour, so what you see from
	// under the water is the same water you were looking at from above.
	[Export] public Color UnderwaterTint = new Color(0.09f, 0.31f, 0.45f);
	// The world already has 0.45 blue aerial fog, and looking forward and down the underwater
	// ceiling is edge on and does nothing, so the haze is the only thing carrying the tint in that
	// view. These are the density just under the surface and at UnderwaterDepthRange, scaled by the
	// submersion filter. They are deliberately not blended up from the world's own value: rebasing
	// onto the world density was tried and hazes the entire above-water look, which is not wanted,
	// so the density is `full * _submersion` and the haze is instead made strong enough to carry
	// the tint on its own.
	//
	// The current pair is 0.06/0.4, retuned by hand from 0.9/2.2, so the submerged haze is now
	// *lighter* than the world's 0.45 air fog rather than denser. The earlier reasoning was that it
	// had to be denser, or submerging would reduce the fog and the seafloor would stop looking like
	// it is under anything. That reasoning is NOT confirmed for this pair and is still open, and
	// tools/test_underwater_filter.gd still requires > 0.5 and therefore fails against it. See
	// docs/future/CURRENT_TODO.md.
	[Export] public float UnderwaterFogNear = 0.06f;
	[Export] public float UnderwaterFogDeep = .4f;
	[Export] public float UnderwaterDepthRange = 14f;
	// The surface albedo is a dark blue, so the fog needs lifting to stay readable. This scales
	// the tint's brightness without touching its hue, which is why the tint is divided by it
	// before being handed to the environment: Godot multiplies fog colour by fog energy, so
	// feeding the surface colour in directly would render the haze brighter and paler than the
	// water above. UnderwaterFogEnergy stays a pure brightness knob over the surface colour.
	[Export] public float UnderwaterFogEnergy = 1.6f;
	[Export] public float UnderwaterSkyAffect = 0.15f;
	// How deep the eye has to be before the tint comes in, and how far above the surface it has to
	// be before the tint lets go again, both in metres. The gap between the two is the dead zone
	// that stops treading water, where the eye bobs through the waterline, from pulsing the tint.
	//
	// These are deliberately small. The view changes character the instant the eye dips under: the
	// blue surface above stops being what is on screen and the seafloor takes over, and the tint is
	// the only thing reconciling the two. Spreading the fade over a long stretch of depth leaves a
	// stretch of unfiltered deep water on every crossing, which reads as a flash, so the tint is
	// instead latched early and eased in quickly.
	[Export] public float SubmersionOn = 0.05f;
	[Export] public float SubmersionOff = 0.25f;
	// How fast the tint is eased in and out once the latch flips, in units per second.
	//
	// Deliberately quick, but not instant. The tint is 0 on the frame above the waterline, so one
	// frame after the eye crosses it lands at SubmersionFadeSpeed / 60, and driving this high enough
	// to land at 1.0 immediately removes the ramp at the cost of a visible snap and fails the
	// gradual-fade check in tools/test_underwater_filter.gd. Measured at 60/s, fog density barely
	// moves the forward-and-down view at all (bluestness 270 -> 273 across the whole shallow band),
	// so the ramp does not look like the cause of the flash and the default stays gradual until that
	// is actually pinned down. See docs/future/CURRENT_TODO.md.
	[Export] public float SubmersionFadeSpeed = 20f;

	// Temporary view toggle: first person is the default, ViewToggleKey swaps to the
	// over-the-shoulder rig behind and leaves the rest of the camera rig untouched.
	[Export] public bool FirstPerson = true;
	[Export] public Key ViewToggleKey = Key.F1;
	[Export] public float ThirdPersonDistance = 2.4f;
	[Export] public float ThirdPersonHeight = 0.45f;
	[Export] public float ThirdPersonClipMargin = 0.2f;

	private Node3D _body;
	private PlayerController _player;
	private Skeleton3D _skeleton;
	private int _headBone = -1;
	private float _yaw;
	private float _pitch;
	private float _currentLift;
	private bool _debugOn;
	private FileAccess _debugFile;
	private Environment _underwaterEnv;
	private bool _submerged;
	private bool _tintEngaged;
	private float _submersion;

	/// True while the camera is actually carrying the underwater filter. Exposed because
	/// Environment itself cannot be read back from a script probe on a C# Camera3D, and this is
	/// the state the dive probe and the tests need to see.
	public bool UnderwaterFilterApplied => _underwaterEnv != null && Environment == _underwaterEnv;

	/// The current filter strength, 0 clear and 1 full underwater tint. Continuous, unlike
	/// IsUnderwater, so the filter can be faded rather than switched. Read by the dive probe and
	/// the tests to check the transition has no step in it.
	public float Submersion => _submersion;

	/// The fog density the camera actually wrote to its environment last frame. Exposed because
	/// Environment cannot be read back reliably from a script probe on a C# Camera3D, and this is
	/// the value the tests need to check.
	public float UnderwaterFogDensity => _underwaterEnv?.FogDensity ?? -1f;

	/// 0 or 1: whether the tint is engaged. Latched with a dead zone rather than read straight off
	/// the eye depth, so treading water, which bobs the eye through the waterline, cannot pulse the
	/// tint on and off. Read by the dive probe and the tests.
	public float SubmersionBlend
	{
		get
		{
			if (_player == null || !_player.IsSwimming)
				return 0f;
			return _tintEngaged ? 1f : 0f;
		}
	}

	public override void _Ready()
	{
		Node node = GetParent();
		while (node != null && node is not CharacterBody3D)
			node = node.GetParent();
		_body = node as Node3D;
		_player = node as PlayerController;

		Node worldNode = GetParent();
		while (worldNode != null && worldNode.Name != "World")
			worldNode = worldNode.GetParent();
		if (worldNode != null)
		{
			var worldEnvironment = worldNode.GetNodeOrNull<WorldEnvironment>("WorldEnvironment");
			if (worldEnvironment?.Environment != null)
			{
				_underwaterEnv = worldEnvironment.Environment.Duplicate() as Environment;
				_underwaterEnv.FogEnabled = true;
				_underwaterEnv.FogLightColor = UnderwaterTint / Mathf.Max(UnderwaterFogEnergy, 0.01f);
				_underwaterEnv.FogLightEnergy = UnderwaterFogEnergy;
				_underwaterEnv.FogSkyAffect = UnderwaterSkyAffect;
				_underwaterEnv.FogAerialPerspective = 0f;
			}
		}

		if (_body != null)
		{
			_skeleton = _body.GetNodeOrNull<Skeleton3D>("Visual/Skeleton3D");
			if (_skeleton != null)
				_headBone = _skeleton.FindBone("Head");
			_yaw = _body.Rotation.Y;
		}

		Fov = FieldOfView;
		// The rig has a single camera: it stays current in both view modes, since the mode only
		// decides where the camera sits. Tying Current to the mode leaves third person with no
		// current camera at all.
		Current = true;
		if (CaptureMouseOnStart)
			Input.MouseMode = Input.MouseModeEnum.Captured;
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;
		if (_player != null)
			_pitch = ClampPitch(_pitch);
		bool surfaceSwim = _player != null && _player.IsSwimming && !_player.IsUnderwater && !_player.IsWading;

		float pitchDownDeg = Mathf.RadToDeg(-_pitch);
		float lookDown = Mathf.Clamp((pitchDownDeg - 10f) / 15f, 0f, 1f);
		float targetLift = surfaceSwim ? SwimCameraLift * (1f - lookDown) : 0f;

		// Always eased, including when looking down while treading. This used to snap straight to
		// the target whenever the target was below the current lift, which put the eye 0.8 m lower
		// in a single frame the moment the view was pitched down far enough. Diving means looking
		// down, so that teleport fired on the way in and the way out, dropping the eye deep enough
		// to be fully underwater while the tint was still fading up: a stretch of clear, untinted
		// deep water on every single crossing. Easing it costs 0.8 / SwimLiftSpeed, about 0.13 s.
		_currentLift = Mathf.MoveToward(_currentLift, targetLift, SwimLiftSpeed * dt);

		float bodyPitch = _player != null ? _player.BodyPitch : 0f;
		if (_headBone >= 0 && _body != null)
		{
			_body.Rotation = new Vector3(bodyPitch, _yaw, 0f);

			Transform3D bone = _skeleton.GlobalTransform * _skeleton.GetBoneGlobalPose(_headBone);
			Transform3D bodyT = _body.GlobalTransform;
			Vector3 forward = -bodyT.Basis.Z;
			Vector3 up = bodyT.Basis.Y;
			Vector3 eye = bone.Origin + up * (EyeOffset + _currentLift);

			if (FirstPerson)
			{
				GlobalPosition = eye + forward * FaceReach;
			}
			else
			{
				Vector3 wanted = eye - forward * ThirdPersonDistance + Vector3.Up * ThirdPersonHeight;
				GlobalPosition = AvoidGeometry(bone.Origin, wanted);
			}
		}
		else if (FirstPerson)
		{
			Position = new Vector3(0f, _currentLift, -FaceReach);
		}
		else
		{
			Position = new Vector3(0f, _currentLift + ThirdPersonHeight, ThirdPersonDistance);
		}
	
		if (_headBone >= 0 && _body != null)
			Rotation = new Vector3(_pitch - bodyPitch, 0f, 0f);
		else
			Rotation = new Vector3(_pitch, _yaw, 0f);

		UpdateUnderwaterLook();

		if (_debugOn && _debugFile != null && _player != null)
		{
			float min = ClampPitch(-Mathf.Pi);
			float max = ClampPitch(Mathf.Pi);
			float headY = _headBone >= 0 && _skeleton != null
				? (_skeleton.GlobalTransform * _skeleton.GetBoneGlobalPose(_headBone)).Origin.Y
				: float.NaN;
			_debugFile.StoreLine(string.Format(
				"t={0:0.00} swim={1} under={2} wade={3} camMin={4:0.0} camMax={5:0.0} pitch={6:0.00} bodyPitch={7:0.00} eyeY={8:0.00} headY={9:0.00}",
				Time.GetTicksMsec() / 1000f,
				_player.IsSwimming, _player.IsUnderwater, _player.IsWading,
				Mathf.RadToDeg(min), Mathf.RadToDeg(max), Mathf.RadToDeg(_pitch),
				Mathf.RadToDeg(_player.BodyPitch), GlobalPosition.Y, headY));
		}
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		if (@event is InputEventKey key && key.Pressed && !key.Echo)
		{
			if (key.PhysicalKeycode == Key.F2)
			{
				_debugOn = !_debugOn;
				if (_debugFile != null)
				{
					_debugFile.Flush();
					_debugFile.Close();
					_debugFile = null;
				}
				if (_debugOn)
					_debugFile = FileAccess.Open("user://swim_debug.txt", FileAccess.ModeFlags.Write);
				return;
			}

			if (key.PhysicalKeycode == Key.Escape)
			{
				Input.MouseMode = Input.MouseMode == Input.MouseModeEnum.Captured
					? Input.MouseModeEnum.Visible
					: Input.MouseModeEnum.Captured;
				return;
			}

			if (key.PhysicalKeycode == ViewToggleKey)
			{
				FirstPerson = !FirstPerson;
				return;
			}
		}

		if (@event is InputEventMouseMotion motion && Input.MouseMode == Input.MouseModeEnum.Captured)
		{
			_yaw -= Mathf.DegToRad(motion.Relative.X * MouseSensitivity);
			_pitch -= Mathf.DegToRad(motion.Relative.Y * MouseSensitivity);
			_pitch = ClampPitch(_pitch);
		}
	}

	// Below the waterline the camera carries the duplicated environment with fog switched on,
	// which is what tints and hazes the world. The density is scaled by how far the camera is
	// below the surface, so depth is readable: the deeper you are, the more the surface above
	// and everything else fades into the tint.
	//
	// The filter used to be swapped on and off as a hard boolean on IsUnderwater, which put a
	// one frame hole in it on the way through the surface: the eye crosses the line, the
	// environment is cleared, and the tint only appears once the swap lands. Going through it
	// repeatedly, or bobbing on the spot while treading, made that hole flicker. It is faded
	// now, and the environment is left on the camera with its density taken to zero instead of
	// being detached, so there is no frame in which the camera has no filter at all.
	//
	// Fading it off the raw eye depth was not enough on its own. Both the depth term and this
	// time term start at nothing, so they multiply: the tint was still almost clear a good way
	// under, by which point the view had already swapped from the blue surface to the seafloor.
	// That left a fraction of a second of unfiltered water on every crossing in both directions,
	// which is the same complaint as before wearing a different cause. So the tint is latched on
	// early and eased in fast, and the depth gradient below carries the rest.
	private void UpdateUnderwaterLook()
	{
		if (_underwaterEnv == null)
			return;

		float eyeDepth = _player != null ? _player.WaterSurfaceY - GlobalPosition.Y : 0f;
		if (_tintEngaged)
		{
			// Positive eyeDepth is below the surface, so letting go means rising clear of
			// SubmersionOff above it, not merely reaching the waterline.
			if (eyeDepth < -Mathf.Max(SubmersionOff, 0f))
				_tintEngaged = false;
		}
		else if (eyeDepth > Mathf.Max(SubmersionOn, 0f))
		{
			_tintEngaged = true;
		}

		float target = SubmersionBlend;
		// MoveToward rather than an exponential so the fade is symmetric and cannot overshoot,
		// and so it is still converging if the eye is moving faster than the fade.
		_submersion = Mathf.MoveToward(_submersion, target, SubmersionFadeSpeed * (float)GetProcessDeltaTime());
		if (Mathf.Abs(_submersion - target) < 0.0005f)
			_submersion = target;

		// The environment stays assigned rather than being nulled out, and the density is scaled by
		// the tint so it is zero above the surface and the water haze only below it.
		//
		// Zero above water is deliberate and must stay. The world's own environment has 0.45 of blue
		// aerial fog in it, and the camera carrying its own environment at zero density is what keeps
		// that out of the above-water look; blending up from the world's value instead puts a blue
		// haze over everything above the waterline, which is not wanted.
		if (Environment != _underwaterEnv)
			Environment = _underwaterEnv;

		float depth = Mathf.Max(0f, eyeDepth);
		float t = Mathf.Clamp(depth / Mathf.Max(UnderwaterDepthRange, 0.01f), 0f, 1f);
		// The haze has to be strong enough to carry the tint on its own, because the view that most
		// needs it is looking forward and down, where the ceiling mesh is edge on and contributes
		// nothing. The densities here are the accepted 0.9 to 2.2; the intermediate 0.06 to 0.19 pair
		// that was in this file for a while barely registered in that view and read as untinted.
		float full = Mathf.Lerp(UnderwaterFogNear, UnderwaterFogDeep, t);
		_underwaterEnv.FogDensity = full * _submersion;
		_submerged = _submersion > 0.5f;
	}

	private float ClampPitch(float pitch)
	{
		bool inWater = _player != null && _player.IsSwimming && !_player.IsWading;
		float min = Mathf.DegToRad(inWater ? MinPitchInWater : MinPitch);
		float max = Mathf.DegToRad(inWater ? MaxPitchInWater : MaxPitch);
		return Mathf.Clamp(pitch, min, max);
	}

	// Pulls the camera in when the third person boom would end up inside terrain, so walking
	// into a slope does not put the view through the ground.
	private Vector3 AvoidGeometry(Vector3 from, Vector3 to)
	{
		Vector3 delta = to - from;
		float distance = delta.Length();
		if (distance < 0.001f)
			return to;

		PhysicsDirectSpaceState3D space = GetWorld3D().DirectSpaceState;
		PhysicsRayQueryParameters3D query = PhysicsRayQueryParameters3D.Create(from, to);
		if (_body is CollisionObject3D self)
			query.Exclude = new Godot.Collections.Array<Rid> { self.GetRid() };
		Godot.Collections.Dictionary hit = space.IntersectRay(query);
		if (hit.Count == 0)
			return to;

		float hitDistance = from.DistanceTo((Vector3)hit["position"]) - ThirdPersonClipMargin;
		return from + delta / distance * Mathf.Max(hitDistance, 0.1f);
	}

	public float LookPitch
	{
		get => _pitch;
		set => _pitch = ClampPitch(value);
	}

	// DebugChaseCamera borrows the viewport. Only one Camera3D can be current, so whoever takes
	// it has to tell this one to stand down, and this one has to take it back on the way out or
	// the viewport goes black.
	public void SetViewportHeld(bool held) => Current = !held;
}
