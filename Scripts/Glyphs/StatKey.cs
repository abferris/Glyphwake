namespace Glyphwake.Glyphs;

/// The stats a glyph can scale. This is the closed set of things a glyph is allowed to touch:
/// a modifier that names something outside it has no way to be applied, and no way to be
/// reported to the player either.
public enum StatKey
{
    Damage,
    Radius,
    Range,
    Duration,
    Cooldown,
    ManaCost,
    CastTime,
    Speed,
    JumpHeight,
    Knockback,
    MaxHealth,
    ManaRecovery,
}
