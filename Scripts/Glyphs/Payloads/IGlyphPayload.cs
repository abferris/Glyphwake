using Godot;

namespace Glyphwake.Glyphs;

/// The handshake between a cast and the payload it spawns. The caster instantiates the active
/// glyph's <see cref="ActiveGlyphData.Payload"/>, calls <see cref="Cast"/> before the payload
/// enters the tree, and adds it as a child; from there the payload's own script decides what to
/// do with the cast. The caster never reads back into a payload, so a new glyph is a new payload
/// scene and script, and no change to the caster.
public interface IGlyphPayload
{
    /// Hands the payload its cast. <paramref name="caster"/> is the body that fired it (and whose
    /// tree the payload may attach into), <paramref name="damage"/> is what the cast paid for
    /// (0 for a glyph that deals no damage), and <paramref name="duration"/> is how long the cast
    /// takes -- the cast animation clip's own length, so a payload that rides the cast cannot
    /// drift off its own clock. Called before the payload enters the tree, so an implementation
    /// has all three in _Ready.
    void Cast(Node caster, float damage, float duration);
}
