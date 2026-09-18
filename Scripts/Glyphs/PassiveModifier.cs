using Godot;
using Godot.Collections;

public enum ModifierOperation
{
    Add,
    Multiply
}

[GlobalClass]
public partial class PassiveModifier : Resource
{
    [Export] public bool AppliesToAll;
    [Export] public Array<GlyphTag> TargetTags = new();
    [Export] public StatKey Stat;
    [Export] public ModifierOperation Operation;
    [Export] public float Value;
    [Export] public float PerPoint;

    public bool AffectsTag(GlyphTag tag)
    {
        if (AppliesToAll)
            return true;
        if (TargetTags == null)
            return false;
        return tag != null && TargetTags.Contains(tag);
    }

    public float ValueAt(int points) => Value + PerPoint * Mathf.Max(0, points - 1);
}
