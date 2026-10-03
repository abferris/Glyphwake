namespace Glyphwake.Glyphs;

/// What the glyph addresses.
public enum GlyphTargetType
{
    /// Applied to or centered on the caster: shield, dash, healing aura.
    Self,

    /// One entity: magic missile, buffing an ally.
    Single,

    /// Emits a shot.
    Projectile,

    /// A point on the terrain.
    GroundPoint,

    /// A direction: dragon's breath.
    Direction
}