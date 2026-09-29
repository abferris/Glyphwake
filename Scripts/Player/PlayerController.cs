using Godot;
using Glyphwake.Core;

namespace Glyphwake.Player;

/// The character body. It reads input, integrates velocity, moves, and poses the visual.
/// Two concerns are deliberately not here: what the character is doing in the world belongs
/// to <see cref="LocomotionState"/>, and what it is made of -- nodes, bones, capsule -- belongs
/// to <see cref="PlayerRig"/>. Which clip to play belongs to <see cref="PlayerAnimator"/>.
public partial class PlayerController : CharacterBody3D
{
    [Export] public float MoveSpeed = 5f;
    [Export] public float SprintSpeed = 8f;
    [Export] public float Acceleration = 12f;
    [Export] public float JumpHeight = 1.5f;
    [Export] public float Gravity = -9.81f;
    [Export] public float ImpulseDecay = 4f;
    [Export] public float MaxFallSpeed = -20f;

    [Export] public float SwimSpeed = 3f;
    [Export] public float SurfaceSwimSpeed = 5f;
    [Export] public float SwimAcceleration = 8f;
    [Export] public float SurfaceHeadHeight = 0f;
    [Export] public float SurfaceHeadBob = 0.05f;
    [Export] public float DiveDelay = 0.25f;
    [Export] public float DiveLookDownDeg = 25f;
    [Export] public float SurfaceSpring = 10f;
    [Export] public float SurfaceDamping = 6f;
    [Export] public float MaxSwimVerticalSpeed = 4f;

    // Authored here because the scene is where a designer tunes them, but consumed by the
    // state owner, which is what actually reads them.
    [Export] public float SubmergedThreshold = 0.15f;
    [Export] public float SurfaceHysteresis = 0.1f;
    [Export(PropertyHint.Range, "0,1,0.05")] public float FloatEngageDepth = 0.7f;
    [Export] public float WadeDepth = 2f;
    [Export(PropertyHint.Range, "0.1,1,0.05")] public float WadeMinSpeedFactor = 0.5f;
    [Export(PropertyHint.Range, "0.25,4,0.05")] public float WadeDragExponent = 1.5f;
    [Export] public float CameraFloorClearance = 0.4f;

    [Export] public float MaxSwimForwardPitchDeg = 40f;
    [Export] public float MaxSwimStrafeRollDeg = 45f;
    [Export] public float SwimLeanSpeed = 60f;
    [Export] public float BodyPitchSpeed = 360f;

    [Export] public float IdleSpeed = 0.2f;
    [Export] public float WalkRunThreshold = 6f;
    [Export] public float WalkAnimSpeed = 2.5f;
    [Export] public float RunAnimSpeed = 6f;
    [Export] public float MinAnimScale = 0.6f;
    [Export] public float MaxAnimScale = 1.6f;
    [Export] public float AnimBlend = 0.15f;
    [Export] public float SwimVigorousSpeed = 2.2f;
    [Export] public float SwimStrokeBlend = 4f;
    [Export] public float TreadSpeedThreshold = 0.6f;
    [Export] public float TreadBlend = 0.3f;
    [Export] public float MinJumpScale = 0.5f;
    [Export] public float MaxJumpScale = 1.5f;

    private readonly LocomotionState _state = new();

    private PlayerRig _rig;
    private PlayerAnimator _animator;

    private Vector3 _horizontalVelocity = Vector3.Zero;
    private Vector3 _impulseVelocity = Vector3.Zero;
    private Vector3 _swimVelocity = Vector3.Zero;
    private float _verticalVelocity;
    private bool _jumpHeld;
    private float _diveCharge;
    private float _leanRoll;
    private float _leanPitch;
    private float _bodyPitch;

    public PlayerRig Rig => _rig;
    public LocomotionMode Mode => _state.Mode;
    public LocomotionState State => _state;

    public bool IsGrounded => IsOnFloor();

    /// Overrides the body pitch target with the camera's look pitch when the camera reports
    /// one. Set by the camera in _Ready; a rig with no camera simply keeps the body level.
    public ILookSource LookSource { get; set; }

    // Read by the water tests and by anything that wants a yes/no without caring which of the
    // swimming states it is. Derived from the mode rather than stored beside it.
    public bool IsSwimming => _state.InWater;
    public bool IsUnderwater => _state.IsUnderwater;
    public bool IsWading => _state.IsWading;
    public float WaterSurfaceY => _state.WaterSurfaceY;
    public float WadeSubmersion => _state.WadeSubmersion;

    public Vector2 SwimLeanDeg => new Vector2(_leanPitch, _leanRoll);
    public float LeanPitchRad => _leanPitch;
    public float LeanRollRad => _leanRoll;
    public float BodyPitch => _bodyPitch;

    public override void _Ready()
    {
        _rig = new PlayerRig(this);
        _animator = new PlayerAnimator(_rig.Anim);

        _state.SubmergedThreshold = SubmergedThreshold;
        _state.SurfaceHysteresis = SurfaceHysteresis;
        _state.FloatEngageDepth = FloatEngageDepth;
        _state.WadeDepth = WadeDepth;

        SyncAnimatorTuning();
    }

    private void SyncAnimatorTuning()
    {
        _animator.IdleSpeed = IdleSpeed;
        _animator.WalkRunThreshold = WalkRunThreshold;
        _animator.WalkAnimSpeed = WalkAnimSpeed;
        _animator.RunAnimSpeed = RunAnimSpeed;
        _animator.MinAnimScale = MinAnimScale;
        _animator.MaxAnimScale = MaxAnimScale;
        _animator.AnimBlend = AnimBlend;
        _animator.SwimVigorousSpeed = SwimVigorousSpeed;
        _animator.SwimStrokeBlend = SwimStrokeBlend;
        _animator.TreadSpeedThreshold = TreadSpeedThreshold;
        _animator.TreadBlend = TreadBlend;
        _animator.MinJumpScale = MinJumpScale;
        _animator.MaxJumpScale = MaxJumpScale;
    }

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;
        Vector2 input = ReadMoveInput();

        _impulseVelocity = _impulseVelocity.MoveToward(Vector3.Zero, ImpulseDecay * dt);

        UpdateState();

        switch (_state.Mode)
        {
            case LocomotionMode.Wading:
                SimulateGround(input, dt, WadeSpeedFactor());
                break;
            case LocomotionMode.Grounded:
            case LocomotionMode.Airborne:
                SimulateGround(input, dt, 1f);
                break;
            default:
                SimulateSwim(input, dt);
                break;
        }

        MoveAndSlide();
        UpdateBodyPitch(dt);
        UpdateLean(input, dt);
        _animator.Update(
            new PlayerAnimator.Frame(
                _state.Mode,
                _horizontalVelocity.Length() + _impulseVelocity.Length(),
                _horizontalVelocity.Length(),
                input,
                IsOnFloor(),
                _verticalVelocity),
            dt,
            GlobalPosition.Y,
            _rig.RestHeight,
            Gravity,
            GroundHeightUnderBody);
    }

    /// The animator only needs the ground height on the frame it switches to the jump clip, so
    /// it asks for it through this rather than being handed a raycast it would throw away on
    /// every other frame.
    private float GroundHeightUnderBody() => GroundHeightUnder(GlobalPosition);

    private void UpdateState()
    {
        // Kept live rather than copied at _Ready so a tool that retunes these at runtime --
        // which the water tests do -- takes effect immediately.
        _state.SubmergedThreshold = SubmergedThreshold;
        _state.SurfaceHysteresis = SurfaceHysteresis;
        _state.FloatEngageDepth = FloatEngageDepth;
        _state.WadeDepth = WadeDepth;

        _state.Update(
            new SubmersionProbe(
                _state.WaterSurfaceY,
                GlobalPosition.Y,
                GlobalPosition.Y - _rig.RestHeight,
                EyePosition().Y,
                _rig.RestHeight,
                _rig.RestHeadHeight,
                IsOnFloor()),
            // Only cast when in water. Out of it, nothing below reads this, and a character
            // walking on dry land should not pay for a raycast every physics step.
            _state.InWater ? GroundHeightUnder(GlobalPosition) : float.NegativeInfinity);
    }

    private void UpdateBodyPitch(float dt)
    {
        float target = 0f;
        if (_state.Mode == LocomotionMode.UnderwaterSwimming && LookSource != null)
            target = LookSource.LookPitch - Mathf.DegToRad(90f);
        _bodyPitch = Mathf.MoveToward(_bodyPitch, target, Mathf.DegToRad(BodyPitchSpeed) * dt);
    }

    private void UpdateLean(Vector2 input, float dt)
    {
        float targetRoll = 0f;
        float targetPitch = 0f;
        if (_state.IsSurfaceSwimming)
        {
            targetRoll = input.X * MaxSwimStrafeRollDeg;
            targetPitch = Mathf.Clamp(input.Y, 0f, 1f) * MaxSwimForwardPitchDeg;
        }
        _leanRoll = Mathf.MoveToward(_leanRoll, targetRoll, SwimLeanSpeed * dt);
        _leanPitch = Mathf.MoveToward(_leanPitch, targetPitch, SwimLeanSpeed * dt);
        if (!_rig.HasVisual)
            return;

        _rig.Visual.Rotation = new Vector3(Mathf.DegToRad(_leanPitch), Mathf.Pi, Mathf.DegToRad(_leanRoll));

        if (!_state.IsSurfaceSwimming || !_rig.HasHeadBone)
        {
            _rig.Visual.Position = _rig.VisualRestPosition;
            return;
        }

        // Pivot the surface-swim lean around the head so the head leads and the body angles
        // behind it. The pivot is the head bone's *animated* position, so the clip's own head
        // motion is preserved while the lean itself no longer displaces the head (which used
        // to swing it under the waterline).
        //
        // The vertical component is pinned to a fixed player-space anchor rather than to the
        // previous frame's height. Pinning to the previous frame only re-anchors, so the clip's
        // integrated head bob still leaked through and the float spring -- which runs a frame
        // earlier -- could only cancel it late, leaving the head swinging around the waterline.
        // Pinning the height lets the visual absorb the stroke's bob, so the head holds a
        // steady height above the water while the hips and feet take the bob.
        Skeleton3D skeleton = _rig.Skeleton;
        Vector3 headPose = skeleton.GetBoneGlobalPose(_rig.HeadBone).Origin;
        Vector3 headInVisual = skeleton.Transform * headPose;
        Vector3 headInPlayer = GlobalTransform.AffineInverse() * (skeleton.GlobalTransform * headPose);
        Vector3 anchor = headInPlayer;
        anchor.Y = _rig.HeadLocalY + Mathf.Clamp(headInPlayer.Y - _rig.HeadLocalY, -SurfaceHeadBob, SurfaceHeadBob);
        _rig.Visual.Position = anchor - _rig.Visual.Basis * headInVisual;
    }

    private static Vector2 ReadMoveInput()
    {
        float x = (Input.IsPhysicalKeyPressed(Key.D) ? 1f : 0f) - (Input.IsPhysicalKeyPressed(Key.A) ? 1f : 0f);
        float z = (Input.IsPhysicalKeyPressed(Key.W) ? 1f : 0f) - (Input.IsPhysicalKeyPressed(Key.S) ? 1f : 0f);
        return new Vector2(x, z);
    }

    private void SimulateGround(Vector2 input, float dt, float speedFactor)
    {
        Vector3 forward = -GlobalTransform.Basis.Z;
        Vector3 right = GlobalTransform.Basis.X;
        Vector3 direction = right * input.X + forward * input.Y;
        if (direction.LengthSquared() > 0.0001f)
            direction = direction.Normalized();

        bool groundedNow = IsOnFloor();

        if (groundedNow)
        {
            bool running = Input.IsPhysicalKeyPressed(Key.Shift);
            float speed = (running ? SprintSpeed : MoveSpeed) * speedFactor;
            _horizontalVelocity = _horizontalVelocity.MoveToward(direction * speed, Acceleration * dt);
        }

        if (groundedNow)
            _verticalVelocity = -2f;

        if (groundedNow && Input.IsPhysicalKeyPressed(Key.Space) && !_jumpHeld)
            _verticalVelocity = Mathf.Sqrt(JumpHeight * -2f * Gravity);

        _jumpHeld = Input.IsPhysicalKeyPressed(Key.Space);

        _verticalVelocity += Gravity * dt;
        _verticalVelocity = Mathf.Max(_verticalVelocity, MaxFallSpeed);

        Velocity = _horizontalVelocity + _impulseVelocity + Vector3.Up * _verticalVelocity;
    }

    private void SimulateSwim(Vector2 input, float dt)
    {
        Camera3D camera = _rig.Camera;
        Vector3 camForward = camera != null ? -camera.GlobalTransform.Basis.Z : -GlobalTransform.Basis.Z;
        Vector3 camRight = camera != null ? camera.GlobalTransform.Basis.X : GlobalTransform.Basis.X;

        if (!_state.IsUnderwater)
        {
            Vector3 fwdH = new Vector3(camForward.X, 0f, camForward.Z).Normalized();
            Vector3 rightH = new Vector3(camRight.X, 0f, camRight.Z).Normalized();
            Vector3 dirH = rightH * input.X + fwdH * input.Y;
            if (dirH.LengthSquared() > 1f)
                dirH = dirH.Normalized();

            _horizontalVelocity = _horizontalVelocity.MoveToward(dirH * SurfaceSwimSpeed, SwimAcceleration * dt);

            bool diveHold = input.Y > 0f && camForward.Y < -Mathf.Sin(Mathf.DegToRad(DiveLookDownDeg));
            if (diveHold)
                _diveCharge += dt;
            else
                _diveCharge = 0f;

            if (_diveCharge >= DiveDelay)
            {
                float diveSpeed = Mathf.Min(SwimSpeed, -camForward.Y * SwimSpeed * 3f);
                _verticalVelocity = Mathf.MoveToward(_verticalVelocity, -diveSpeed, SwimAcceleration * dt);
            }
            else
            {
                // A plunge is not a swim. The float only blends in once the body is mostly
                // under -- FloatEngageDepth of the feet-to-head span, i.e. the treading-water
                // depth -- and the fall limit opens up again to MaxFallSpeed while it is not,
                // so jumping in keeps falling instead of being caught at the waterline. Once
                // the body is at or below the float target the spring takes over outright, so
                // the tuned treading equilibrium (head on the waterline, since
                // targetY = surface + SurfaceHeadHeight - HeadLocalY) is untouched.
                float targetY = _state.WaterSurfaceY + SurfaceHeadHeight - _rig.HeadLocalY;
                float displacement = targetY - GlobalPosition.Y;
                float band = Mathf.Max(0.01f, 1f - FloatEngageDepth);
                float engage = Mathf.Clamp((_state.WadeSubmersion - FloatEngageDepth) / band, 0f, 1f);
                if (displacement >= 0f)
                    engage = 1f;

                float floatAccel = displacement * SurfaceSpring - _verticalVelocity * SurfaceDamping;
                float accel = Mathf.Lerp(Gravity, floatAccel, engage);
                float fallLimit = Mathf.Lerp(MaxFallSpeed, -MaxSwimVerticalSpeed, engage);
                _verticalVelocity = Mathf.Clamp(_verticalVelocity + accel * dt, fallLimit, MaxSwimVerticalSpeed);
            }

            _swimVelocity = Vector3.Zero;
            Velocity = _horizontalVelocity + Vector3.Up * _verticalVelocity;
        }
        else
        {
            Vector3 dir = camRight * input.X + camForward * input.Y;
            if (dir.LengthSquared() > 1f)
                dir = dir.Normalized();

            _swimVelocity = _swimVelocity.MoveToward(dir * SwimSpeed, SwimAcceleration * dt);
            _swimVelocity.Y = Mathf.Clamp(_swimVelocity.Y, -MaxSwimVerticalSpeed, MaxSwimVerticalSpeed);

            _verticalVelocity = 0f;
            _horizontalVelocity = Vector3.Zero;
            _diveCharge = 0f;

            Velocity = _swimVelocity + _impulseVelocity;
        }

        KeepCameraAboveGround();
    }

    private void KeepCameraAboveGround()
    {
        Vector3 eye = EyePosition();
        float groundY = GroundHeightUnder(eye);
        if (float.IsNegativeInfinity(groundY))
            return;

        float minY = groundY + CameraFloorClearance;
        if (eye.Y < minY)
            GlobalPosition += Vector3.Up * (minY - eye.Y);
    }

    private float GroundHeightUnder(Vector3 position)
    {
        PhysicsDirectSpaceState3D space = GetWorld3D().DirectSpaceState;
        Vector3 origin = position + Vector3.Up * 3f;
        PhysicsRayQueryParameters3D query = PhysicsRayQueryParameters3D.Create(origin, origin + Vector3.Down * 100f);
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };
        Godot.Collections.Dictionary hit = space.IntersectRay(query);
        if (hit.Count == 0)
            return float.NegativeInfinity;
        return ((Vector3)hit["position"]).Y;
    }

    private Vector3 EyePosition()
    {
        if (_rig.Camera != null)
            return _rig.Camera.GlobalPosition;
        if (_rig.Head != null)
            return _rig.Head.GlobalPosition;
        return GlobalPosition + Vector3.Up * 1.6f;
    }

    private float WadeSpeedFactor()
    {
        return Mathf.Lerp(1f, WadeMinSpeedFactor, Mathf.Pow(_state.WadeSubmersion, WadeDragExponent));
    }

    public void EnterWater(float surfaceY)
    {
        bool wasInWater = _state.InWater;
        _state.EnterWater(surfaceY);
        if (wasInWater)
            return;

        _swimVelocity = Vector3.Zero;
        _impulseVelocity = Vector3.Zero;
        _diveCharge = 0f;
        // The fall speed is left alone on purpose: a plunge is a fall until the float engages
        // (see SimulateSwim), so clamping here would kill the drop at the waterline.
    }

    public void ExitWater()
    {
        if (!_state.InWater)
            return;

        _state.ExitWater();
        _swimVelocity = Vector3.Zero;
        _diveCharge = 0f;
        if (_verticalVelocity < 0f)
            _verticalVelocity = 0f;
    }

    public void AddImpulse(Vector3 impulse)
    {
        _impulseVelocity += impulse;
    }

    public void Jump(float height)
    {
        _verticalVelocity = Mathf.Sqrt(height * -2f * Gravity);
    }
}
