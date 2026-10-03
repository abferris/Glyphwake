namespace Glyphwake.Glyphs;

/// A glyph's school is the essence of how it effects the world, independent of its element,
/// target, shape and cast time. Single-valued: a glyph is one school. What it does to other
/// glyphs is filtered on this, so it is a closed set rather than a free-form tag.
public enum GlyphSchool
{
    Kindling,
    Warding,
    Calling,
    Seeking,
    Flowing,
    Shaping
}