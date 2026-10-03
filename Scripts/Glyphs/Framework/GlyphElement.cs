namespace Glyphwake.Glyphs;

/// An element is the energy type a glyph channels, and it is what decides what the glyph is
/// resisted by. Element is optional: a town portal has no element. Multi-element is allowed
/// (Meteor is Inferno and Terra), so a glyph carries a list and splits damage evenly between
/// its damaging elements.
public enum GlyphElement
{
    None,
    Inferno,
    Aqua,
    Terra,
    Zephyr,
    Anima,
    Lux
}