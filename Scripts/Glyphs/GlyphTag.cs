using Godot;

[GlobalClass]
public partial class GlyphTag : Resource
{
    [Export] public string DisplayName = "";
    [Export] public Color TagColor = Colors.White;
}
