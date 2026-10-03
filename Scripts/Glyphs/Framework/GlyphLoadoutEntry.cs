using Godot;

namespace Glyphwake.Glyphs;

/// One glyph in a player's loadout and the points that player has put in it. The points live
/// here rather than on <see cref="GlyphData"/> on purpose: a GlyphData is a shared immutable
/// resource -- one .tres is one object -- so points stored on it would be the same for every
/// player holding the glyph. The entry is the player-owned half.
[GlobalClass]
public partial class GlyphLoadoutEntry : Resource
{
    [Export] public GlyphData Glyph;

    [Export] public int Points;
}
