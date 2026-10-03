using Godot;

namespace Glyphwake.Glyphs;

[GlobalClass]
public partial class GlyphTag : Resource
{
    /// The identity a tag is matched on. Set it to something stable ("Ranged", "Channel") rather
    /// than relying on DisplayName, which is player-facing text and free to be reworded.
    [Export] public StringName Id = "";

    [Export] public string DisplayName = "";
    [Export] public Color TagColor = Colors.White;
}