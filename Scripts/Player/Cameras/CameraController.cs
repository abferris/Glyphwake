using Godot;
using Glyphwake.Core;

namespace Glyphwake.Player;

/// The head camera: where the player is looking, and what the world looks like through it.
///
/// The dependency runs one way: this camera registers itself as the body's
/// <see cref="ILookSource"/> and publishes a pitch; the body reads that and nothing else. Two-way
/// reach is what lets a pitch feedback loop form -- swimming pitches the body down, which drops
/// the head, which switches off the lift, which drops the eye further.
public partial class CameraController : Camera3D, ILookSource
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
	[Export] public float SubmersionOn = 0.05f;
	[Export] public float SubmersionOff = 0.25f;
	// How fast the tint is eased in and out once the latch flips, in units per second.
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
	private PlayerRig _rig;
	private float _yaw;
	private float _pitch;
	private float _currentLift;
	private bool _debugOn;
	private FileAccess _debugFile;
	private Environment _underwaterEnv;
	private bool _tintEngaged;
	private float _submersion;

	/// The player's rig, resolved on first use rather than in _Ready.
	///
	/// Godot readies children before parents, so this camera's _Ready runs *before* the
	/// PlayerController's, and the rig does not exist yet at that point. Touching it here
	/// would build it early and measure the head bone before the skeleton has settled, which
	/// is exactly the measurement the rig is supposed to make. Resolving on first use defers
	/// it to the first _Process, by which point the controller has built it as normal.
	private PlayerRig Rig
	{
		get
		{
			if (_rig == null && _player != null)
				_rig = _player.Rig;
			return _rig;
		}
	}

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

	/// Where this camera is looking, in radians. The body reads this and nothing else, so the two
	/// cannot steer each other: this camera decides where it looks, and the body decides what to do
	/// with that.
	public float LookPitch
	{
		get => _pitch;
		set => _pitch = ClampPitch(value);
	}

	public override void _Ready()
	{
		Node node = GetParent();
		while (node != null && node is not CharacterBody3D)
			node = node.GetParent();
		_body = node as Node3D;
		_player = node as PlayerController;

		if (_player != null)
		{
			// One-way handoff: the body learns where the camera is looking, and never has to
			// know what class the camera is. The rig is deliberately not touched here -- see
			// the Rig property for why it waits until first use.
			_player.LookSource = this;
		}

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
			_yaw = _body.Rotation.Y;

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
		bool atSurface = _player != null && _player.State.IsAtOrAboveSurface;

		float pitchDownDeg = Mathf.RadToDeg(-_pitch);
		float lookDown = Mathf.Clamp((pitchDownDeg - 10f) / 15f, 0f, 1f);
		float targetLift = atSurface ? SwimCameraLift * (1f - lookDown) : 0f;

		// Always eased, including when looking down while treading. Snapping to the target whenever the
		// target is below the current lift drops the eye 0.8 m in a single frame, and diving means
		// looking down, so it would fire on the way in and the way out and leave a stretch of clear,
		// untinted deep water on every crossing. Easing costs 0.8 / SwimLiftSpeed, about 0.13 s.
		_currentLift = Mathf.MoveToward(_currentLift, targetLift, SwimLiftSpeed * dt);

		float bodyPitch = _player != null ? _player.BodyPitch : 0f;
		PlayerRig rig = Rig;
		if (rig != null && rig.HasHeadBone && _body != null)
		{
			_body.Rotation = new Vector3(bodyPitch, _yaw, 0f);

			Transform3D bone = rig.Skeleton.GlobalTransform * rig.Skeleton.GetBoneGlobalPose(rig.HeadBone);
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

			Rotation = new Vector3(_pitch - bodyPitch, 0f, 0f);
		}
		else if (_body != null)
		{
			if (FirstPerson)
			{
				Position = new Vector3(0f, _currentLift, -FaceReach);
			}
			else
			{
				Position = new Vector3(0f, _currentLift + ThirdPersonHeight, ThirdPersonDistance);
			}
			Rotation = new Vector3(_pitch, _yaw, 0f);
		}

		UpdateUnderwaterLook();

		if (_debugOn && _debugFile != null && _player != null)
		{
			float min = ClampPitch(-Mathf.Pi);
			float max = ClampPitch(Mathf.Pi);
			float headY = rig != null && rig.HasHeadBone
				? (rig.Skeleton.GlobalTransform * rig.Skeleton.GetBoneGlobalPose(rig.HeadBone)).Origin.Y
				: float.NaN;
			_debugFile.StoreLine(string.Format(
				"t={0:0.00} swim={1} under={2} wade={3} mode={4} camMin={5:0.0} camMax={6:0.0} pitch={7:0.00} bodyPitch={8:0.00} eyeY={9:0.00} headY={10:0.00}",
				Time.GetTicksMsec() / 1000f,
				_player.IsSwimming, _player.IsUnderwater, _player.IsWading, _player.Mode,
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
	// The environment stays assigned rather than being nulled out, and the density is taken to
	// zero above the surface, so there is never a frame in which the camera has no filter at
	// all. Swapping the filter on and off as a hard boolean instead would leave a one-frame hole at
	// the surface: the eye crosses the line, the environment is cleared, and the tint only appears
	// once the swap lands.
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

		if (Environment != _underwaterEnv)
			Environment = _underwaterEnv;

		float depth = Mathf.Max(0f, eyeDepth);
		float t = Mathf.Clamp(depth / Mathf.Max(UnderwaterDepthRange, 0.01f), 0f, 1f);
		float full = Mathf.Lerp(UnderwaterFogNear, UnderwaterFogDeep, t);
		_underwaterEnv.FogDensity = full * _submersion;
	}

	private float ClampPitch(float pitch)
	{
		bool inWater = _player != null && _player.State.IsSwimmingFreely;
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
		query.CollisionMask = CollisionLayers.CameraBoomMask;
		if (_body is CollisionObject3D self)
			query.Exclude = new Godot.Collections.Array<Rid> { self.GetRid() };
		Godot.Collections.Dictionary hit = space.IntersectRay(query);
		if (hit.Count == 0)
			return to;

		float hitDistance = from.DistanceTo((Vector3)hit["position"]) - ThirdPersonClipMargin;
		return from + delta / distance * Mathf.Max(hitDistance, 0.1f);
	}

	// DebugChaseCamera borrows the viewport. Only one Camera3D can be current, so whoever takes
	// it has to tell this one to stand down, and this one has to take it back on the way out or
	// the viewport goes black.
	public void SetViewportHeld(bool held) => Current = !held;
}
