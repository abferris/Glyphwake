using System;
using Godot;
using Glyphwake.Core;

namespace Glyphwake.Player;

/// Decides which state the character's AnimationTree should be in, and how fast, from the
/// movement state and the current input.
///
/// This is policy only. It does not know how a state machine works, and it holds no reference
/// to a node: <see cref="LocomotionGraph"/> owns the tree and this tells it where to go. The
/// two are split so the rules below can be read, and changed, without an animation graph in
/// sight -- and so the graph can be replaced without touching the rules.
public sealed class PlayerAnimator
{
    // Not exported: this is a plain class, not a node, so the inspector cannot reach it. The
    // owning controller keeps the exported copies as the single place a designer tunes these
    // and pushes them in through SyncTuning.
    public float IdleSpeed = 0.2f;
    public float WalkRunThreshold = 6f;
    public float WalkAnimSpeed = 2.5f;
    public float RunAnimSpeed = 6f;
    public float MinAnimScale = 0.6f;
    public float MaxAnimScale = 1.6f;
    public float AnimBlend = 0.15f;
    public float SwimVigorousSpeed = 2.2f;
    public float SwimStrokeBlend = 4f;
    public float TreadSpeedThreshold = 0.6f;
    public float TreadBlend = 0.3f;
    public float MinJumpScale = 0.5f;
    public float MaxJumpScale = 1.5f;

    /// The gait phase a jump at or past counts as jumping off the right foot. Measured off the
    /// walk cycle rather than guessed: the left foot is forward for roughly the first half of
    /// the stride (0.03-0.52 of the walk cycle, 0-0.45 of the run), so a single boundary sits
    /// within a hair of both. Tunable by eye; the boundary is the only thing to move.
    public float GaitLeadPhase = 0.5f;

    /// The state the character is playing, as a clip name. The AnimationTree reports the same
    /// strings, so this is what the GDScript tests assert against.
    public string CurrentState => _graph.CurrentState;

    /// How fast the current state is playing, as a multiple of real time. Negative when the
    /// character is walking backwards. This replaces reading AnimationPlayer.speed_scale, which
    /// is always 1 once a tree is driving the player.
    public float PlaybackSpeed { get; private set; } = 1f;

    /// Where the current state has played to, as a fraction of its length, wrapped into 0..1.
    /// This is the gait phase: read back from the tree rather than accumulated by hand, so the
    /// phase and the visible stride cannot disagree. Meaningless while a non-gait clip plays,
    /// which is why <see cref="LeadFootLeft"/> only reads it when a stride is on the floor.
    public float GaitPhase
    {
        get
        {
            float len = _graph.PlayLength;
            if (len < 0.01f)
                return 0f;
            return Mathf.Wrap(_graph.PlayPosition, 0f, len) / len;
        }
    }

    /// Which foot leads the stride on the floor, from <see cref="GaitPhase"/>. The gait is what
    /// decides -- a jump off the leading foot should continue the stride the walk cycle is
    /// actually in. Outside a gait (idle, swim, airborne) there is no stride to read, so this
    /// reports the left foot, which is also what a first step with no gait behind it uses.
    /// A gait played backwards runs its cycle backwards, so the boundary flips with it.
    public bool LeadFootLeft()
    {
        if (!_gaitPlaying)
            return true;
        return _gaitReversed ? GaitPhase >= GaitLeadPhase : GaitPhase < GaitLeadPhase;
    }

    private readonly LocomotionGraph _graph;
    private readonly float _jumpClipLength;

    private float _swimStrokeSpeed = 1f;
    private float _jumpScale = 1f;
    private MoveDirection _lastDirection = MoveDirection.None;
    private bool _gaitPlaying;
    private bool _gaitReversed;

    public PlayerAnimator(LocomotionGraph graph)
    {
        _graph = graph;
        _jumpClipLength = (float)graph.ClipLength(AnimationIds.Jump);
    }

    /// Everything the choice of state depends on, gathered by the caller in one place.
    public readonly struct Frame
    {
        /// Current locomotion mode. Decides between the swim clips and the ground clips.
        public readonly LocomotionMode Mode;

        /// Horizontal ground speed, plus any decaying impulse still in flight. This is the
        /// speed that drives the walk/run choice and the gait scaling.
        public readonly float Speed;

        /// Horizontal velocity on its own, with the impulse left out. Treading is judged on
        /// this rather than on <see cref="Speed"/>: a knockback is not swimming, so a character
        /// being pushed along by an impulse is still treading water, not stroking.
        public readonly float HorizontalSpeed;

        /// Raw move input, which picks the directional clip and the stroke vigour.
        public readonly Vector2 Input;

        public readonly bool OnFloor;

        /// Vertical velocity, used to scale the jump clip to the arc the character is
        /// actually on.
        public readonly float VerticalVelocity;

        /// The direction the current jump was fired in, latched by the caller on the jump and
        /// cleared on any grounded frame. It no longer picks the clip -- every jump plays the
        /// forward family -- but None still means the airborne pose is not a jump look: a fall
        /// off a ledge keeps the bare clip. This is fed in every frame rather than read by this
        /// class, so the latch stays with the caller that owns it.
        public readonly MoveDirection JumpDirection;

        /// Which foot the latched jump leads with. Only read when
        /// <see cref="JumpDirection"/> is set, which is also the only way it gets latched.
        public readonly bool JumpLeadsLeft;

        public Frame(
            LocomotionMode mode,
            float speed,
            float horizontalSpeed,
            Vector2 input,
            bool onFloor,
            float verticalVelocity,
            MoveDirection jumpDirection = MoveDirection.None,
            bool jumpLeadsLeft = true)
        {
            Mode = mode;
            Speed = speed;
            HorizontalSpeed = horizontalSpeed;
            Input = input;
            OnFloor = onFloor;
            VerticalVelocity = verticalVelocity;
            JumpDirection = jumpDirection;
            JumpLeadsLeft = jumpLeadsLeft;
        }
    }

    /// Scales the jump clip so one authored jump covers whatever arc the current jump
    /// produces. A fixed-length clip on a variable-height jump either lands early or loops
    /// visibly before touchdown. Public rather than private because the air-step cast scales
    /// its clip to the same arc for exactly the same reason.
    public float PredictAirTime(in Frame frame, float bodyY, float groundY, float restHeight, float gravity)
    {
        if (float.IsNegativeInfinity(groundY))
            return 1f;

        float g = -gravity;
        if (g <= 0.01f)
            return 1f;

        float height = Mathf.Max(0f, bodyY - (groundY + restHeight));
        float v = frame.VerticalVelocity;
        return (v + Mathf.Sqrt(v * v + 2f * g * height)) / g;
    }

    public void Update(
        in Frame frame,
        float dt,
        float bodyY,
        float restHeight,
        float gravity,
        Func<float> groundHeightUnder)
    {
        if (!_graph.IsValid)
            return;

        string state;
        float scale = 1f;

        LocomotionMode mode = frame.Mode;
        bool swimming = mode is LocomotionMode.SurfaceSwimming or LocomotionMode.UnderwaterSwimming;

        if (swimming)
        {
            _gaitPlaying = false;
            bool treading = mode == LocomotionMode.SurfaceSwimming
                && frame.HorizontalSpeed < TreadSpeedThreshold;
            if (treading)
            {
                state = AnimationIds.Tread;
                _swimStrokeSpeed = 1f;
                scale = 1f;
            }
            else
            {
                state = AnimationIds.SwimLoop;
                float activity = Mathf.Clamp(frame.Input.Length(), 0f, 1f);
                float target = Mathf.Lerp(1f, SwimVigorousSpeed, activity);
                _swimStrokeSpeed = Mathf.MoveToward(_swimStrokeSpeed, target, SwimStrokeBlend * dt);
                scale = _swimStrokeSpeed;
            }
        }
        else if (!frame.OnFloor)
        {
            // The jump look is the forward clip for every direction: the direction the jump was
            // fired in is shown as a tilt of the body instead (the caller's jump tilt), because
            // the directional clips read as marching rather than as a jump. The lead foot is
            // still the one latched by the caller on the jump, so the clip agrees with the
            // stride that launched it, and a fall off a ledge -- no jump, no latch -- keeps the
            // bare clip through the descent.
            if (frame.JumpDirection != MoveDirection.None)
            {
                state = AnimationIds.JumpClipFor(frame.JumpLeadsLeft);
                if (state != _graph.CurrentState)
                {
                    float clipLength = (float)_graph.ClipLength(state);
                    float airTime = PredictAirTime(frame, bodyY, groundHeightUnder(), restHeight, gravity);
                    _jumpScale = clipLength > 0.01f && airTime > 0.05f
                        ? Mathf.Clamp(clipLength / airTime, MinJumpScale, MaxJumpScale)
                        : 1f;
                }
                scale = _jumpScale;
            }
            else
            {
                state = AnimationIds.Jump;
                if (state != _graph.CurrentState)
                {
                    float airTime = PredictAirTime(frame, bodyY, groundHeightUnder(), restHeight, gravity);
                    _jumpScale = _jumpClipLength > 0.01f && airTime > 0.05f
                        ? Mathf.Clamp(_jumpClipLength / airTime, MinJumpScale, MaxJumpScale)
                        : 1f;
                }
                scale = _jumpScale;
            }
        }
        else if (frame.Speed < IdleSpeed)
        {
            state = AnimationIds.Idle;
            _lastDirection = MoveDirection.None;
            _gaitPlaying = false;
        }
        else
        {
            bool running = frame.Speed >= WalkRunThreshold;
            MoveDirection direction = AnimationIds.DirectionFrom(frame.Input);

            // The keys letting go mid-stride resolve to no direction while the body is still
            // moving. Selecting the bare gait clip there read as a twitch twice -- once onto
            // the bare clip and once onto Idle -- instead of finishing the step, so the gait
            // already playing is held until the deceleration brings Idle in. A knockback with
            // no gait to hold still falls through to the bare clip, as before.
            if (direction == MoveDirection.None)
                direction = _lastDirection;
            else
                _lastDirection = direction;

            bool reversed;
            state = AnimationIds.ClipFor(
                running ? AnimationIds.Run : AnimationIds.Walk,
                direction,
                out reversed);
            scale = running
                ? Mathf.Clamp(frame.Speed / RunAnimSpeed, MinAnimScale, MaxAnimScale)
                : Mathf.Clamp(frame.Speed / WalkAnimSpeed, MinAnimScale, MaxAnimScale);

            // The graph plays a state backwards by giving it a negative time scale. Which
            // states that applies to is decided here, not in the graph, so the reversal stays
            // with the rest of the clip choice.
            if (reversed)
                scale = -scale;

            // A gait is on the floor, so the gait phase is live and -- when the cycle runs
            // backwards -- mirrored. Recorded here rather than re-derived by the lead-foot
            // read, so the two cannot disagree about what the stride is doing.
            _gaitPlaying = true;
            _gaitReversed = reversed;
        }

        PlaybackSpeed = scale;
        _graph.TravelTo(state, scale);
    }
}
