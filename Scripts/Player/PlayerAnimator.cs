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

    /// The state the character is playing, as a clip name. The AnimationTree reports the same
    /// strings, so this is what the GDScript tests assert against.
    public string CurrentState => _graph.CurrentState;

    /// How fast the current state is playing, as a multiple of real time. Negative when the
    /// character is walking backwards. This replaces reading AnimationPlayer.speed_scale, which
    /// is always 1 once a tree is driving the player.
    public float PlaybackSpeed { get; private set; } = 1f;

    private readonly LocomotionGraph _graph;
    private readonly float _jumpClipLength;

    private float _swimStrokeSpeed = 1f;
    private float _jumpScale = 1f;

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

        public Frame(
            LocomotionMode mode,
            float speed,
            float horizontalSpeed,
            Vector2 input,
            bool onFloor,
            float verticalVelocity)
        {
            Mode = mode;
            Speed = speed;
            HorizontalSpeed = horizontalSpeed;
            Input = input;
            OnFloor = onFloor;
            VerticalVelocity = verticalVelocity;
        }
    }

    /// Scales the jump clip so one authored jump covers whatever arc the current jump
    /// produces. A fixed-length clip on a variable-height jump either lands early or loops
    /// visibly before touchdown.
    private float PredictAirTime(in Frame frame, float bodyY, float groundY, float restHeight, float gravity)
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
        else if (frame.Speed < IdleSpeed)
        {
            state = AnimationIds.Idle;
        }
        else
        {
            bool running = frame.Speed >= WalkRunThreshold;
            bool reversed;
            state = AnimationIds.ClipFor(
                running ? AnimationIds.Run : AnimationIds.Walk,
                AnimationIds.DirectionFrom(frame.Input),
                out reversed);
            scale = running
                ? Mathf.Clamp(frame.Speed / RunAnimSpeed, MinAnimScale, MaxAnimScale)
                : Mathf.Clamp(frame.Speed / WalkAnimSpeed, MinAnimScale, MaxAnimScale);

            // The graph plays a state backwards by giving it a negative time scale. Which
            // states that applies to is decided here, not in the graph, so the reversal stays
            // with the rest of the clip choice.
            if (reversed)
                scale = -scale;
        }

        PlaybackSpeed = scale;
        _graph.TravelTo(state, scale);
    }
}
