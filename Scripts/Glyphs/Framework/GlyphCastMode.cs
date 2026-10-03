namespace Glyphwake.Glyphs;

/// How much the caster is committed to casting. This is a separate axis from what the glyph
/// targets and from how long its effect lasts.
public enum GlyphCastMode
{
    /// Fires immediately. Does not affect movement.
    Impulse,

    /// Wind-up of a varying length. Does not affect movement. Not interruptable except by stun
    /// or silence.
    Focus,

    /// Must keep casting; the effect only exists while casting continues. Interruptable by stun
    /// or silence.
    Channel,

    /// Long cast, cannot move. Interruptable by damage.
    Ritual
}