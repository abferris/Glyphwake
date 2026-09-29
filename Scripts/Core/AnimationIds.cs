using Godot;

namespace Glyphwake.Core;

/// Animation clip names, in one place.
///
/// The clip names were previously string literals scattered through the movement code, and
/// the directional logic then did `Contains("Backward")` and `Replace("Left", "Right")` on
/// them: renaming a clip in the AnimationLibrary silently broke locomotion, and nothing
/// reported it. Naming them here means the set of clips this character can play is a list
/// somebody can read. When the AnimationTree lands, these become state names instead and the
/// string surgery goes away with them.
public static class AnimationIds
{
    public const string Idle = "Idle";
    public const string Jump = "Jumping Up";

    public const string Walk = "Walk";
    public const string Run = "Run";

    public const string Tread = "Swim Tread";
    public const string SwimLoop = "Swimming Loop";

    public const string BackwardSuffix = "Backward";
    public const string ForwardSuffix = "Forward";
    public const string LeftSuffix = "Left";
    public const string RightSuffix = "Right";

    public const string WalkDiagonalForwardRight = "Walk Diagonal Forward Right";
}
