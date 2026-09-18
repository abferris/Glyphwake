using Godot;
using Godot.Collections;

public enum CastStyle
{
    Projectile,
    Beam,
    GroundTarget,
    SelfTarget,
    Directional,
    Summon
}

[GlobalClass]
public partial class ActiveGlyphData : GlyphData
{
    [Export] public CastStyle Style;
    [Export] public float ManaCost;
    [Export] public float ManaCostPerPoint;
    [Export] public float CastTime;
    [Export] public float CastTimePerPoint;
    [Export] public float Cooldown;
    [Export] public float CooldownPerPoint;

    [Export] public Array<ScaledStat> Stats = new();

    public float ManaCostAt(int points) => Mathf.Max(0f, ManaCost + ManaCostPerPoint * Mathf.Max(0, points - 1));
    public float CastTimeAt(int points) => Mathf.Max(0f, CastTime + CastTimePerPoint * Mathf.Max(0, points - 1));
    public float CooldownAt(int points) => Mathf.Max(0f, Cooldown + CooldownPerPoint * Mathf.Max(0, points - 1));
}
