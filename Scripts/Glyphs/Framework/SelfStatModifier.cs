using Godot;

namespace Glyphwake.Glyphs;

public enum ModifierOperation
{
    Add,
    Percent,
    Multiply
}

/// A passive that changes one of the caster's own stats. This is the "self" target from the
/// design: health, mana, regen, speed.
[GlobalClass]
public partial class SelfStatModifier : Resource
{
    [Export] public StatKey Stat;
    [Export] public ModifierOperation Operation;
    [Export] public float Value;
    [Export] public float PerPoint;

    public float ValueAt(int points) => Value + PerPoint * Mathf.Max(0, points - 1);
}