using Godot;

namespace Glyphwake.Glyphs;

/// One scaling entry: which stat it grows, how the growth curves, and how much per step. A
/// glyph's scaling is defined by its own entries rather than one shared formula, so one glyph
/// scales linearly while another accelerates or arrives in chunks.
[GlobalClass]
public partial class GlyphScaling : Resource
{
    [Export] public StatKey Stat;

    [Export] public GlyphScalingStyle Style = GlyphScalingStyle.Linear;

    /// The scaling amount; what it multiplies depends on the style.
    [Export] public float Value;

    /// Points per step, for Step scaling. Ignored by the other styles.
    [Export] public float StepSize = 1f;

    /// Growth contributed at a point count, on top of the stat's base value. One point is
    /// activation, so growth starts at zero there.
    public float GrowthAt(int points)
    {
        float past = Mathf.Max(0, points - 1);
        return Style switch
        {
            GlyphScalingStyle.Linear => Value * past,
            GlyphScalingStyle.Quadratic => Value * past * past,
            GlyphScalingStyle.SquareRoot => Value * Mathf.Sqrt(past),
            GlyphScalingStyle.Step => Value * Mathf.Floor(past / Mathf.Max(1f, StepSize)),
            _ => 0f
        };
    }
}
