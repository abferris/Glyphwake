using Godot;
using Godot.Collections;

public enum GlyphCategory
{
    Capability,
    Movement,
    Utility,
    Attack,
    Summoning
}

public abstract partial class GlyphData : Resource
{
    [Export] public string DisplayName = "";
    [Export(PropertyHint.MultilineText)] public string Description = "";
    [Export] public Texture2D Icon;
    [Export] public GlyphCategory Category;

    [Export] public Array<GlyphTag> Tags = new();

    public const int ActivationPoints = 1;
    public const int TotalPointPool = 100;
    public const int SecondaryGuidepostPoints = 3;
    public const int ImpactfulGuidepostPoints = 5;
    public const int PrimaryGuidepostPoints = 10;
    public const int SpecialistGuidepostPoints = 15;

    public bool IsActiveAt(int points) => points >= ActivationPoints;
}
