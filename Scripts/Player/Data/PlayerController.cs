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
    [Export] public float MaxFallSpeed = -100f;

    // The share of the air jump's steering: how far the held input swings the horizontal
    // velocity on a mid-air jump, without gaining or losing speed. Steering is a redirect of
    // an existing arc, not air control from a standstill -- no held input means no redirect,
    // and starting horizontal motion mid-air is the open feel question (see WORKLOG-10-02).
    [Export(PropertyHint.Range, "0,1,0.05")] public float AirJumpRedirect = 0.5f;

    [Export] public float SwimSpeed = 3f;
    [Export] public float SurfaceSwimSpeed = 5f;
    [Export] public float SwimAcceleration = 8f;
    // How far below the head bone the waterline sits while treading. The float settles the body at
    // surface + SurfaceHeadHeight - RestHeadHeight, so this is exactly the gap between the head
    // bone and the water. The shoulder bone rides 0.115 m below the head bone in the tread pose,
    // so the shoulder is SurfaceHeadHeight - 0.115 clear of the water: 0.18 measured with the
    // shoulder still 6.5 cm out, which read as treading at the armpits, and 0.06 puts the water
    // above both shoulder joints -- shoulders, chest, hips and arms under, neck at the waterline,
    // head out.
    [Export] public float SurfaceHeadHeight = 0.06f;
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
    [Export(PropertyHint.Range, "0.5,1,0.01")] public float WadeHandoverDepth = 0.92f;
    [Export] public float WadeDepth = 2f;
    // How far a swimmer will climb a submerged step without walking it. The float parks the
    // feet a fixed depth under the waterline, so the treading feet are already WadeStepUpHeight
    // above the floor of water WadeDepth calls wadeable: any step inside this height is by
    // construction shallower than the body can tread in, which is what makes it safe to climb
    // one and then hand over to walking. Anything taller is a wall, not a ledge.
    [Export] public float WadeStepUpHeight = 0.75f;
    // Downward speed, in m/s, above which a body over water is still a fall rather than a swim.
    // Measured, not guessed: a 20 m drop is doing 19 m/s as its feet cross the waterline and
    // still 6.8 m/s a tenth of a second later, when the body is already fully submerged. A
    // deliberate dive tops out at MaxSwimVerticalSpeed = 4, so this sits clear of it.
    [Export] public float PlungeSpeed = 6f;
    [Export(PropertyHint.Range, "0.1,1,0.05")] public float WadeMinSpeedFactor = 0.5f;
    [Export(PropertyHint.Range, "0.25,4,0.05")] public float WadeDragExponent = 1.5f;

    // Walking uphill. The steepest ground the body can stand on at all, which Godot decides from
    // FloorMaxAngle and which everything else here is measured against: up to SlopeFullSpeedDeg
    // costs nothing, and between there and this the speed falls to SlopeMinSpeedFactor. Past it
    // the ground is a wall and no amount of speed factor gets a body up it.
    [Export(PropertyHint.Range, "1,89,1")] public float SlopeMaxAngleDeg = 60f;
    [Export(PropertyHint.Range, "0,45,1")] public float SlopeFullSpeedDeg = 35f;
    [Export(PropertyHint.Range, "0.1,1,0.05")] public float SlopeMinSpeedFactor = 0.45f;

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
    private LocomotionGraph _graph;
    private PlayerAnimator _animator;

    private Vector3 _horizontalVelocity = Vector3.Zero;
    private Vector3 _impulseVelocity = Vector3.Zero;
    private Vector3 _swimVelocity = Vector3.Zero;
    private float _verticalVelocity;
    private bool _jumpHeld;
    private int _airJumpsUsed;
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
    public bool IsPlunging => _state.IsPlunging;
    public bool IsOverShallowFloor => _state.IsOverShallowFloor;
    public float GroundY => _state.GroundY;
    public float WaterSurfaceY => _state.WaterSurfaceY;
    public float WadeSubmersion => _state.WadeSubmersion;

    /// The animation state the character is playing, as a clip name, and how fast it is
    /// playing it. Read by the GDScript tests: the AnimationTree does not populate
    /// AnimationPlayer.current_animation or speed_scale once it is driving, so these are the
    /// only honest way for a tool to ask what the character is doing.
    public string AnimationState => _animator?.CurrentState ?? "";
    public float AnimationSpeed => _animator?.PlaybackSpeed ?? 1f;

    /// The player's techniques: what turns points in a <see cref="Glyphwake.Glyphs.TechniqueGlyphData"/>
    /// into capability. Resolved by path in _Ready like the rig's nodes; a body without one
    /// simply has no techniques.
    public PlayerTechniques Techniques { get; private set; }

    private const string TechniquesNodePath = "Techniques";

    public Vector2 SwimLeanDeg => new Vector2(_leanPitch, _leanRoll);
    public float LeanPitchRad => _leanPitch;
    public float LeanRollRad => _leanRoll;
    public float BodyPitch => _bodyPitch;

    public override void _Ready()
    {
        // From here on, what the body can stand on is a tuned number rather than Godot's 45 deg
        // default, so the slope bands below have something to be measured against.
        FloorMaxAngle = Mathf.DegToRad(SlopeMaxAngleDeg);

        _rig = new PlayerRig(this);

        Techniques = GetNodeOrNull<PlayerTechniques>(TechniquesNodePath);

        _graph = new LocomotionGraph(_rig.Anim);
        _animator = new PlayerAnimator(_graph);

        _state.SubmergedThreshold = SubmergedThreshold;
        _state.SurfaceHysteresis = SurfaceHysteresis;
        _state.FloatEngageDepth = FloatEngageDepth;
        _state.WadeHandoverDepth = WadeHandoverDepth;
        _state.WadeDepth = WadeDepth;
        _state.PlungeSpeed = PlungeSpeed;

        SyncAnimatorTuning();
        BuildAnimationGraph();
    }

    /// Assembles the AnimationTree from the clips the movement code can actually reach.
    ///
    /// The tree is built in code rather than authored in the scene on purpose: it is 16 states
    /// and 240 transitions, which is a uniform "any state can reach any other" rule and nothing
    /// a person would maintain by hand in the AnimationTree dock.
    private void BuildAnimationGraph()
    {
        if (_rig.AnimTree == null)
            return;

        GraphClip[] clips = new GraphClip[AnimationIds.ReachableClips.Length];
        for (int i = 0; i < clips.Length; i++)
            clips[i] = new GraphClip(AnimationIds.ReachableClips[i]);

        _graph.Build(_rig.AnimTree, clips, AnimBlend, TreadBlend, AnimationIds.Tread);
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
        WadeStepUp();
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
        _state.WadeHandoverDepth = WadeHandoverDepth;
        _state.WadeDepth = WadeDepth;
        _state.PlungeSpeed = PlungeSpeed;

        _state.Update(
            new SubmersionProbe(
                _state.WaterSurfaceY,
                GlobalPosition.Y,
                GlobalPosition.Y - _rig.RestHeight,
                EyePosition().Y,
                _rig.RestHeight,
                _rig.RestHeadHeight,
                IsOnFloor(),
                _verticalVelocity),
            // Only cast when in water. Out of it, nothing below reads this, and a character
            // walking on dry land should not pay for a raycast every physics step.
            _state.InWater ? GroundHeightUnder(GlobalPosition) : float.NegativeInfinity);
    }

    /// Climbs a submerged step instead of treading against it.
    ///
    /// A swimmer heading for the bank meets the step with its feet still at the treading depth,
    /// below the top of anything shallower than it, so the body stops dead and treads there
    /// forever: the water is wadeable, but nothing ever puts the body on the floor that would make
    /// it wading. This lifts the body over -- but only over a step low enough that its top is
    /// shallower than the body was already floating in (<see cref="WadeStepUpHeight"/>), so the
    /// handover afterwards is the ordinary one. It is a lift rather than a swept test, so it can
    /// clip the lip of the step, which is cheaper and not visible while the body is in the water.
    ///
    /// The rise it acts on was sampled before the move, so the settle can gate on the same number.
    private void WadeStepUp()
    {
        if (_state.Mode != LocomotionMode.SurfaceSwimming || !IsOnWall())
            return;

        if (_wadeStepUpRise <= 0.01f || _wadeStepUpRise > WadeStepUpHeight)
            return;

        GlobalPosition += Vector3.Up * _wadeStepUpRise;
    }

    /// How far the floor a stride ahead of the body sits above its feet, or negative infinity when
    /// there is no floor there or the body is not heading anywhere.
    ///
    /// Sampled once a frame and read by both WadeStepUp and the shallow-floor settle, because the
    /// two decisions hang off it and have to agree: the lift will only take a step this size, and
    /// the settle may only stand the surface float down when there is a step of this size to hand
    /// over to. Asked separately they can disagree, and the failure is a bank too steep for
    /// either -- the settle stands the float down over shallow floor the body cannot reach, and it
    /// sinks under water it should have been treading on.
    ///
    /// Measured before SimulateSwim uses it, so both see one number for the frame. Mode is
    /// SurfaceSwimming only while IsUnderwater is false, which is the branch that samples it, so
    /// the value is not stale by the time WadeStepUp reads it after the move.
    private void SampleWadeStepUpRise()
    {
        _wadeStepUpRise = float.NegativeInfinity;

        Vector2 wish = new(_horizontalVelocity.X, _horizontalVelocity.Z);
        if (wish.LengthSquared() < 0.01f)
            return;

        Vector3 ahead = GlobalPosition + new Vector3(wish.X, 0f, wish.Y).Normalized() * WadeStepUpProbe;
        float floorY = GroundHeightUnder(ahead);
        if (float.IsNegativeInfinity(floorY))
            return;

        _wadeStepUpRise = floorY - (GlobalPosition.Y - _rig.RestHeight);
    }

    /// Distance ahead of the body the step is looked for in. It has to clear the capsule radius,
    /// because the floor sampled at the body itself is the floor it is already standing over, and
    /// it is half of what decides what counts as climbable: WadeStepUpHeight over this is the
    /// steepest gradient a stride can take.
    [Export(PropertyHint.Range, "0.5,3,0.1")] public float WadeStepUpProbe = 1f;

    private float _wadeStepUpRise = float.NegativeInfinity;

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
        // motion is preserved while the lean itself does not displace the head (which would otherwise
        // swing it under the waterline).
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
            float speed = (running ? SprintSpeed : MoveSpeed) * speedFactor * SlopeSpeedFactor(direction);
            _horizontalVelocity = _horizontalVelocity.MoveToward(direction * speed, Acceleration * dt);
        }

        // The downward stick is a contact aid -- it is what keeps a body standing still from
        // drifting off a bump -- but it is also a real velocity, and only its share along the
        // floor does any work. On a steep face that share cancels the climb outright: 2 m/s of it
        // down a 60 degree face is 1.73 m/s downhill, against a character only asked for 2.25
        // uphill, so the body stands there and slides instead of walking up. Input already presses
        // the body into the floor, so the stick is only needed when there is none.
        if (groundedNow)
            _verticalVelocity = direction.LengthSquared() > 0.0001f ? 0f : -2f;

        // Landing hands the mid-air jump chain back: the counter resets on any grounded frame,
        // so a technique that buys several air jumps chains until the points run out of them,
        // and the ground jump starts a fresh one.
        if (groundedNow)
        {
            _airJumpsUsed = 0;
            if (Input.IsPhysicalKeyPressed(Key.Space) && !_jumpHeld)
                _verticalVelocity = Mathf.Sqrt(JumpHeight * -2f * Gravity);
        }

        // The technique fires on the same edge the ground jump does -- a press, not a hold.
        // TryAirJump is the atomic check-pay-compute: out of jumps or out of mana means
        // nothing happens and nothing was spent.
        if (!groundedNow && Input.IsPhysicalKeyPressed(Key.Space) && !_jumpHeld && Techniques != null)
        {
            float airJumpHeight = Techniques.TryAirJump(_airJumpsUsed, JumpHeight);
            if (airJumpHeight > 0f)
            {
                _verticalVelocity = Mathf.Sqrt(airJumpHeight * -2f * Gravity);
                RedirectAirJump(input);
                _airJumpsUsed++;
            }
        }

        _jumpHeld = Input.IsPhysicalKeyPressed(Key.Space);

        _verticalVelocity += Gravity * dt;
        _verticalVelocity = Mathf.Max(_verticalVelocity, MaxFallSpeed);

        Velocity = _horizontalVelocity + _impulseVelocity + Vector3.Up * _verticalVelocity;
    }

    /// Swings the horizontal velocity toward the held input on a mid-air jump, keeping its
    /// speed: a redirect of the existing arc, not a push and not a brake. No held input means
    /// no redirect, and no horizontal speed means nothing to steer -- starting motion from a
    /// standstill mid-air is air control, which is the open feel question, not this.
    private void RedirectAirJump(Vector2 input)
    {
        Vector3 direction = GlobalTransform.Basis.X * input.X - GlobalTransform.Basis.Z * input.Y;
        if (direction.LengthSquared() < 0.0001f)
            return;

        float speed = _horizontalVelocity.Length();
        if (speed < 0.0001f)
            return;

        Vector3 swung = _horizontalVelocity.Lerp(direction * speed, AirJumpRedirect);
        _horizontalVelocity = swung.Normalized() * speed;
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
            SampleWadeStepUpRise();

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
                // the tuned treading equilibrium (head SurfaceHeadHeight above the waterline,
                // since targetY = surface + SurfaceHeadHeight - HeadLocalY) is untouched.
                float targetY = _state.WaterSurfaceY + SurfaceHeadHeight - _rig.HeadLocalY;
                float displacement = targetY - GlobalPosition.Y;
                float band = Mathf.Max(0.01f, 1f - FloatEngageDepth);
                float engage = Mathf.Clamp((_state.WadeSubmersion - FloatEngageDepth) / band, 0f, 1f);
                if (displacement >= 0f)
                    engage = 1f;

                // You float in water you cannot touch the bottom of, and stand in water you can. The float parks
                // the feet a fixed depth under the waterline, so over any shallower shelf the feet
                // sit below its top edge: the body cannot climb it, and because treading keeps the
                // feet past WadeHandoverDepth, AtSwimDepth holds the swim look and the state never
                // reaches wading either. The visible result is a body pressed against a submerged
                // step, treading, in water it is standing-depth in.
                //
                // So where the floor under the body is shallow enough to wade in, the float gets out
                // of the way and lets it land there, handing over through the ordinary wading path
                // -- OnFloor, submersion under WadeHandoverDepth, ground clips. The descent stays at
                // swim speed rather than the fall limit, because crossing a shallow spot is a swim
                // down, not a drop, and the floor arrives well before free fall would.
                //
                // Shallow floor on its own is not enough to stand the float down: it is only a
                // handover if there is somewhere to hand over to. WadeStepUpRise is the measurement
                // the lift acts on, so this waits for a step the body could actually take -- a bank
                // too steep to climb is shallow floor with nothing behind it, and standing the float
                // down over it sinks the body out of sight under water it was treading on a moment
                // before.
                bool overShallowFloor = _state.IsOverShallowFloor
                    && !float.IsNegativeInfinity(_state.GroundY)
                    && _wadeStepUpRise <= WadeStepUpHeight;
                if (overShallowFloor)
                    engage = 0f;

                float floatAccel = displacement * SurfaceSpring - _verticalVelocity * SurfaceDamping;
                float accel = Mathf.Lerp(Gravity, floatAccel, engage);
                float fallLimit = overShallowFloor
                    ? -MaxSwimVerticalSpeed
                    : Mathf.Lerp(MaxFallSpeed, -MaxSwimVerticalSpeed, engage);
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
        query.CollisionMask = CollisionLayers.GroundProbeMask;
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

    /// The share of the requested speed a body gets walking uphill on the floor it is standing on.
    ///
    /// Flat, and anything up to SlopeFullSpeedDeg, costs nothing. From there the factor falls
    /// linearly to SlopeMinSpeedFactor as the floor approaches SlopeMaxAngleDeg, which is the point
    /// where the ground stops being a floor at all and starts being a wall -- so the slowest this
    /// gets is still a body that can get up it, just not at a run.
    ///
    /// The floor normal carries the slope's direction with it, so which way is downhill falls out of
    /// the same vector rather than needing the body's facing: the normal's horizontal part points
    /// down the fall line, and walking with it is downhill. Only uphill is penalised, because that
    /// is the direction the factor was asked for; downhill is left exactly as it was, and what
    /// stops a body going fast down a steep face is the same physics that stops it going up.
    private float SlopeSpeedFactor(Vector3 direction)
    {
        if (!IsOnFloor())
            return 1f;

        Vector3 normal = GetFloorNormal();
        float slope = Mathf.RadToDeg(Mathf.Acos(Mathf.Clamp(normal.Dot(Vector3.Up), -1f, 1f)));
        if (slope <= SlopeFullSpeedDeg)
            return 1f;

        Vector2 fallLine = new Vector2(normal.X, normal.Z);
        if (fallLine.LengthSquared() < 0.0001f)
            return 1f;

        if (direction.X * fallLine.X + direction.Z * fallLine.Y > 0f)
            return 1f;

        float t = Mathf.Clamp((slope - SlopeFullSpeedDeg) / Mathf.Max(1f, SlopeMaxAngleDeg - SlopeFullSpeedDeg), 0f, 1f);
        return Mathf.Lerp(1f, SlopeMinSpeedFactor, t);
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
