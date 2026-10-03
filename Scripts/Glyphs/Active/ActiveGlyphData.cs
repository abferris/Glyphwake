using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// An active glyph: something the player binds to a hotkey and casts. It can spend resources,
/// takes time to cast, and produces a payload node in the world.
[GlobalClass]
public partial class ActiveGlyphData : GlyphData
{
    [Export] public GlyphCastMode CastMode;
    [Export] public GlyphEffectMode EffectMode;

    /// What the glyph addresses.
    [Export] public GlyphTargetType TargetType;

    /// Who the target or area is allowed to affect.
    [Export] public GlyphAffects Affects = GlyphAffects.Enemies;

    /// What the cast spends. Empty means free.
    [Export] public Array<GlyphCost> Costs = new();

    /// What the glyph actually produces: the projectile, the beam, the totem. The caster
    /// instantiates it; the payload's own script decides what it does once it exists.
    [Export] public PackedScene Payload;

    public float CostUpFrontAt(CostResource resource, int points)
    {
        float total = 0f;
        foreach (GlyphCost cost in Costs)
        {
            if (cost != null && cost.Resource == resource)
                total += cost.AmountAt(points);
        }
        return total;
    }

    public float CostPerSecondAt(CostResource resource, int points)
    {
        float total = 0f;
        foreach (GlyphCost cost in Costs)
        {
            if (cost != null && cost.Resource == resource)
                total += cost.PerSecondAt(points);
        }
        return total;
    }
}