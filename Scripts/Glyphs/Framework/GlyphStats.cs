using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// The stat lookup shared by glyphs and by things that carry a glyph's numbers without being
/// one, such as a passive trigger's payload numbers.
public static class GlyphStats
{
    /// The value for a stat at a point count: base plus scaling growth. Returns 0 when the
    /// owner does not have the stat, so a caller does not have to know whether it exists.
    public static float StatAt(
        Array<StatValue> baseStats,
        Array<GlyphScaling> scalings,
        StatKey key,
        int points)
    {
        return TryStatAt(baseStats, scalings, key, points, out float value) ? value : 0f;
    }

    /// Reports whether the owner has a stat at all, because 0 is a legitimate value: a glyph
    /// with no ProjectileCount entry and one with an explicit 0 both read as 0 from StatAt,
    /// but only the first should fall back to a caller-supplied default.
    public static bool TryStatAt(
        Array<StatValue> baseStats,
        Array<GlyphScaling> scalings,
        StatKey key,
        int points,
        out float value)
    {
        value = 0f;
        bool found = false;

        foreach (StatValue stat in baseStats)
        {
            if (stat != null && stat.Key == key)
            {
                value = stat.Value;
                found = true;
                break;
            }
        }

        foreach (GlyphScaling scaling in scalings)
        {
            if (scaling != null && scaling.Stat == key)
            {
                value += scaling.GrowthAt(points);
                found = true;
            }
        }

        return found;
    }
}
