using Godot;

namespace Glyphwake.Glyphs;

/// One entry in a cast animation's variant table: a key naming one directional variant, and
/// the clip in the cast scene that plays it.
///
/// One <see cref="GlyphCastAnimation.Clip"/> cannot express a cast animation with directional
/// variants -- an air step that steps off the left foot is a different clip from the same step
/// off the right -- so a glyph that varies lists the variants here and keeps <see cref="GlyphCastAnimation.Clip"/>
/// as the fallback. Keys are hand-typed strings in a .tres, which is why
/// <see cref="GlyphCastAnimation.Validate"/> checks every variant clip against the scene rather
/// than trusting the names: a typo would otherwise surface as a variant that silently plays the
/// fallback pose instead of the one that was authored.
///
/// The keys are the closed vocabulary below. A key is the direction family plus the lead foot
/// (a_forward_l = stepping forward, left foot leading), lower case because they are authored
/// more often than they are read in code.
[GlobalClass]
public partial class GlyphCastVariant : Resource
{
    public const string ForwardL = "forward_l";
    public const string ForwardR = "forward_r";
    public const string DiagonalL = "diagonal_l";
    public const string DiagonalR = "diagonal_r";
    public const string StrafeL = "strafe_l";
    public const string StrafeR = "strafe_r";
    public const string BackwardL = "backward_l";
    public const string BackwardR = "backward_r";

    /// The key this variant answers.
    [Export] public StringName Key;

    /// The clip in the cast scene's AnimationPlayer that plays for this key.
    [Export] public StringName Clip;

    /// The variant key for a cast in a direction off a given foot, using the same folding the
    /// gait clips do: diagonals fold into the nearest family, which keeps the vocabulary at
    /// eight keys instead of one per input. Since 10-06 the jump and air-step casts no longer
    /// use this -- they play the forward variant for every direction and the body tilts instead
    /// (PlayerController's jump tilt) -- but the vocabulary stays for casts that genuinely need
    /// a direction, e.g. a spell aimed by the cast itself.
    public static StringName KeyFor(Core.MoveDirection direction, bool leadsLeft)
    {
        string family;
        switch (direction)
        {
            case Core.MoveDirection.ForwardLeft:
            case Core.MoveDirection.ForwardRight:
                family = "diagonal";
                break;
            case Core.MoveDirection.Left:
            case Core.MoveDirection.Right:
                family = "strafe";
                break;
            case Core.MoveDirection.Backward:
            case Core.MoveDirection.BackwardLeft:
            case Core.MoveDirection.BackwardRight:
                family = "backward";
                break;
            default:
                family = "forward";
                break;
        }
        return family + (leadsLeft ? "_l" : "_r");
    }
}
