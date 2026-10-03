namespace Glyphwake.Glyphs;

/// How long the glyph's effect persists. Independent of cast mode: a channel cast can leave an
/// anchored totem behind it.
public enum GlyphEffectMode
{
    /// Resolves now, nothing persists.
    Instant,

    /// Exists only while the caster keeps casting.
    Channel,

    /// Persists while its physical thing exists (totem, summon, ward).
    Anchored,

    /// Lasts a set duration.
    OverTime
}