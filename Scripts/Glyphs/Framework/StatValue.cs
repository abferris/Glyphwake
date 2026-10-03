using Godot;

namespace Glyphwake.Glyphs;

/// A base statistic: one of the glyph's own numbers before scaling. Which keys appear on a
/// glyph is deliberate — a Self-targeted glyph has no Range entry and an Impulse cast has no
/// CastTime entry, and absence is how "zero for that mode" is expressed.
[GlobalClass]
public partial class StatValue : Resource
{
    [Export] public StatKey Key;

    [Export] public float Value;

    public static StatValue Create(StatKey key, float value)
    {
        return new StatValue { Key = key, Value = value };
    }
}
