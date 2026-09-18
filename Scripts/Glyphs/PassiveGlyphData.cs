using Godot;
using Godot.Collections;

[GlobalClass]
public partial class PassiveGlyphData : GlyphData
{
    [Export] public Array<PassiveModifier> Modifiers = new();
}
