namespace Glyphwake.Glyphs;

/// How a scaling entry's Value grows as points are added past activation. Not locked to one
/// shape: a skill-shot glyph can accelerate while a utility glyph grows slowly.
public enum GlyphScalingStyle
{
    /// Value per point.
    Linear,

    /// Value times the square of points past activation. Slow early, steep late.
    Quadratic,

    /// Value times the square root of points past activation. Diminishing returns.
    SquareRoot,

    /// Value per StepSize points. Growth arrives in chunks rather than smoothly.
    Step
}
