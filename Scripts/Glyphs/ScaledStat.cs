using Godot;

[GlobalClass]
public partial class ScaledStat : Resource
{
    [Export] public StatKey Key;
    [Export] public float BaseValue;
    [Export] public float PerPoint;

    public float ValueAt(int points) => BaseValue + PerPoint * Mathf.Max(0, points - 1);

    public static ScaledStat Create(StatKey key, float baseValue, float perPoint)
    {
        return new ScaledStat { Key = key, BaseValue = baseValue, PerPoint = perPoint };
    }
}
