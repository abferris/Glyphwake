using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

[GlobalClass]
public partial class PassiveGlyphData : GlyphData
{
    [Export] public Array<PassiveModifier> Modifiers = new();
}
