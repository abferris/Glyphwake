using Godot;

namespace Glyphwake.Core;

/// The eight directions movement input can resolve to.
public enum MoveDirection
{
    None,
    Forward,
    Backward,
    Left,
    Right,
    ForwardLeft,
    ForwardRight,
    BackwardLeft,
    BackwardRight,
}

/// The character animation clips, and which of them this character can actually reach.
///
/// The direction table below is an explicit mapping rather than string surgery over clip names,
/// so the clip a given direction resolves to can be read off directly. Keep the names in sync
/// with the AnimationLibrary: a name that is not in the library still builds a state, and that
/// state plays nothing -- only the tests and <see cref="Glyphwake.Player.LocomotionGraph"/> say so.
public static class AnimationIds
{
    public const string Idle = "Idle";
    public const string Jump = "Jumping Up";

    public const string Walk = "Walk";
    public const string Run = "Run";

    public const string Tread = "Swim Tread";
    public const string SwimLoop = "Swimming Loop";

    public const string Forward = "Forward";
    public const string StrafeLeft = "Strafe Left";
    public const string StrafeRight = "Strafe Right";
    public const string DiagonalForwardLeft = "Diagonal Forward Left";
    public const string DiagonalForwardRight = "Diagonal Forward Right";

    public const string WalkDiagonalForwardRight = Walk + " " + DiagonalForwardRight;

    /// The five Backward clips in the library are not in this set, and that is deliberate
    /// rather than an oversight. Walking backwards plays the *forward* clip in reverse with
    /// left and right swapped; switching to the authored Backward clips changes how it looks,
    /// which is a call to make by eye.
    public const bool BackwardClipsUsed = false;

    /// Which clip plays for a gait in a given direction.
    ///
    /// Backward directions return the forward clip and set <paramref name="reversed"/>, because
    /// the time scale that runs a clip backwards is the same mechanism that scales the jump to
    /// the arc it actually flies.
    public static string ClipFor(string gait, MoveDirection direction, out bool reversed)
    {
        reversed = direction is MoveDirection.Backward
            or MoveDirection.BackwardLeft
            or MoveDirection.BackwardRight;

        switch (direction)
        {
            case MoveDirection.Forward:
            case MoveDirection.Backward:
                return gait + " " + Forward;
            case MoveDirection.Left:
                return gait + " " + StrafeLeft;
            case MoveDirection.Right:
                return gait + " " + StrafeRight;
            case MoveDirection.ForwardLeft:
                return gait + " " + DiagonalForwardLeft;
            case MoveDirection.ForwardRight:
                return gait + " " + DiagonalForwardRight;
            // Walking back-left faces forward-right, and the other way round, because the clip
            // is being played backwards.
            case MoveDirection.BackwardLeft:
                return gait + " " + DiagonalForwardRight;
            case MoveDirection.BackwardRight:
                return gait + " " + DiagonalForwardLeft;
            default:
                return gait;
        }
    }

    /// Resolves raw move input to a direction. The thresholds are the same dead zones the old
    /// direction logic used, which are deliberately wider than a digital stick: a diagonal only
    /// reads as one when the input is committed to both axes.
    public static MoveDirection DirectionFrom(Vector2 input)
    {
        bool forward = input.Y > 0.5f;
        bool backward = input.Y < -0.5f;
        bool left = input.X < -0.5f;
        bool right = input.X > 0.5f;

        if (forward && left)
            return MoveDirection.ForwardLeft;
        if (forward && right)
            return MoveDirection.ForwardRight;
        if (backward && left)
            return MoveDirection.BackwardLeft;
        if (backward && right)
            return MoveDirection.BackwardRight;
        if (forward)
            return MoveDirection.Forward;
        if (backward)
            return MoveDirection.Backward;
        if (left)
            return MoveDirection.Left;
        if (right)
            return MoveDirection.Right;
        return MoveDirection.None;
    }

    /// Every clip this character can end up playing, in the order the graph lays them out.
    ///
    /// This is the list the AnimationTree is built from, so it is deliberately the *reachable*
    /// set rather than everything in the library: the six ground clips per gait come from
    /// <see cref="ClipFor"/>, and Sitting, Yelling and the Backward clips are absent because
    /// nothing selects them. Building the tree from this list means a state cannot exist for a
    /// clip the movement code cannot ask for.
    public static readonly string[] ReachableClips =
    {
        Idle,
        Jump,
        Tread,
        SwimLoop,
        Walk,
        Walk + " " + Forward,
        Walk + " " + StrafeLeft,
        Walk + " " + StrafeRight,
        Walk + " " + DiagonalForwardLeft,
        WalkDiagonalForwardRight,
        Run,
        Run + " " + Forward,
        Run + " " + StrafeLeft,
        Run + " " + StrafeRight,
        Run + " " + DiagonalForwardLeft,
        Run + " " + DiagonalForwardRight,
    };
}
