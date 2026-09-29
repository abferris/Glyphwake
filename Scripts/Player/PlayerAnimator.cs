using System;
using Godot;
using Glyphwake.Core;

namespace Glyphwake.Player;

/// Decides which clip the character plays and how fast, from the movement state and the
/// current input. Split out of <see cref="PlayerController"/> so that the locomotion rules
/// and the animation rules can be read, and changed, independently: everything here is a pure
/// function of the inputs below plus the previous clip, and nothing here moves the character.
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

    /// The clip currently playing, for tests and for the future AnimationTree.
    public string CurrentClip => _clip;

    private readonly AnimationPlayer _anim;

    private string _clip = "";
    private float _clipOffset = -1f;
    private float _swimStrokeSpeed = 1f;
    private float _jumpScale = 1f;
    private float _jumpClipLength;

    public PlayerAnimator(AnimationPlayer anim)
    {
        _anim = anim;
        if (_anim == null)
            return;

        Animation jump = _anim.GetAnimation(AnimationIds.Jump);
        if (jump != null)
            _jumpClipLength = (float)jump.Length;
    }

    /// Everything the choice of clip depends on, gathered by the caller in one place.
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
        if (_anim == null)
            return;

        string clip;
        float scale = 1f;
        bool reversed = false;
        float offset = 0f;

        LocomotionMode mode = frame.Mode;
        bool swimming = mode is LocomotionMode.SurfaceSwimming or LocomotionMode.UnderwaterSwimming;

        if (swimming)
        {
            bool treading = mode == LocomotionMode.SurfaceSwimming
                && frame.HorizontalSpeed < TreadSpeedThreshold;
            if (treading)
            {
                clip = AnimationIds.Tread;
                _swimStrokeSpeed = 1f;
                scale = 1f;
            }
            else
            {
                clip = AnimationIds.SwimLoop;
                float activity = Mathf.Clamp(frame.Input.Length(), 0f, 1f);
                float target = Mathf.Lerp(1f, SwimVigorousSpeed, activity);
                _swimStrokeSpeed = Mathf.MoveToward(_swimStrokeSpeed, target, SwimStrokeBlend * dt);
                scale = _swimStrokeSpeed;
            }
        }
        else if (!frame.OnFloor)
        {
            clip = AnimationIds.Jump;
            if (clip != _clip)
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
            clip = AnimationIds.Idle;
        }
        else
        {
            bool running = frame.Speed >= WalkRunThreshold;
            clip = DirectionalClip(running ? AnimationIds.Run : AnimationIds.Walk, frame.Input);
            reversed = clip.Contains(AnimationIds.BackwardSuffix);
            if (reversed)
            {
                clip = clip.Replace(AnimationIds.BackwardSuffix, AnimationIds.ForwardSuffix);
                if (clip.Contains(AnimationIds.LeftSuffix))
                    clip = clip.Replace(AnimationIds.LeftSuffix, AnimationIds.RightSuffix);
                else if (clip.Contains(AnimationIds.RightSuffix))
                    clip = clip.Replace(AnimationIds.RightSuffix, AnimationIds.LeftSuffix);
            }
            else if (!running && clip == AnimationIds.WalkDiagonalForwardRight)
            {
                Animation anim = _anim.GetAnimation(clip);
                if (anim != null)
                    offset = (float)anim.Length * 0.5f;
            }
            scale = running
                ? Mathf.Clamp(frame.Speed / RunAnimSpeed, MinAnimScale, MaxAnimScale)
                : Mathf.Clamp(frame.Speed / WalkAnimSpeed, MinAnimScale, MaxAnimScale);
        }

        _anim.SpeedScale = reversed ? -scale : scale;
        if (clip == _clip && offset == _clipOffset)
            return;

        // prone swim <-> upright tread is a large pose change, so give it a longer blend
        float blend = clip == AnimationIds.Tread || _clip == AnimationIds.Tread ? TreadBlend : AnimBlend;
        _clip = clip;
        _clipOffset = offset;
        _anim.Play(clip, blend);
        if (offset > 0f)
            _anim.Seek(offset, true);
    }

    private static string DirectionalClip(string gait, Vector2 input)
    {
        bool forward = input.Y > 0.5f;
        bool backward = input.Y < -0.5f;
        bool left = input.X < -0.5f;
        bool right = input.X > 0.5f;

        if (forward && left)
            return gait + " Diagonal Forward Left";
        if (forward && right)
            return gait + " Diagonal Forward Right";
        if (backward && left)
            return gait + " Diagonal Backward Left";
        if (backward && right)
            return gait + " Diagonal Backward Right";
        if (forward)
            return gait + " Forward";
        if (backward)
            return gait + " Backward";
        if (left)
            return gait + " Strafe Left";
        if (right)
            return gait + " Strafe Right";
        return gait;
    }
}
