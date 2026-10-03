using Godot;

namespace Glyphwake.Glyphs;

/// One resource a cast spends. A glyph carries a list so a glyph can cost mana up front and
/// stamina per second while it channels.
[GlobalClass]
public partial class GlyphCost : Resource
{
    [Export] public CostResource Resource;

    /// Paid once when the cast is committed.
    [Export] public float Amount;

    [Export] public float AmountPerPoint;

    /// Paid per second for as long as the cast lasts. Only meaningful for a channel.
    [Export] public float PerSecond;

    [Export] public float PerSecondPerPoint;

    public float AmountAt(int points) =>
        Mathf.Max(0f, Amount + AmountPerPoint * Mathf.Max(0, points - 1));

    public float PerSecondAt(int points) =>
        Mathf.Max(0f, PerSecond + PerSecondPerPoint * Mathf.Max(0, points - 1));
}