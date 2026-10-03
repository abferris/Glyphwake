namespace Glyphwake.Glyphs;

/// The stats a glyph can scale. This is the closed set of things a glyph is allowed to touch:
/// a modifier that names something outside it has no way to be applied, and no way to be
/// reported to the player either.
///
/// Split by what the number belongs to. A glyph's own numbers (Damage, Radius, Range) are set
/// on the glyph and scaled by the points in it; the caster's numbers (MaxHealth, ManaRecovery,
/// MovementSpeed) are the player's base values that passives modify. Keeping one enum for both
/// is what let ManaCost exist twice, once as a field on ActiveGlyphData and once here.
public enum StatKey
{
    // The glyph's own numbers, scaled by the points in the glyph.
    Damage,
    Radius,
    Range,
    Duration,
    Cooldown,
    ManaCost,
    CastTime,
    Speed,
    JumpHeight,
    JumpCount,
    Knockback,
    ProjectileCount,
    AreaOfEffect,

    // The caster's numbers, modified by passives.
    MaxHealth,
    ManaRecovery,
    HealthRecovery,
    Stamina,
    StaminaRecovery
}