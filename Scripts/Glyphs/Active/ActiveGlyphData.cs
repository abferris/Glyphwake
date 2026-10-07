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

    /// What the glyph's payload produces where it lands: the burst, the scorch, the splinters.
    ///
    /// A second slot rather than something authored inside <see cref="Payload"/> because that
    /// scene is instantiated once at the caster and travels, while this one is instantiated where
    /// the payload resolves, which is somewhere else entirely. It is also what lets one impact be
    /// shared by every glyph that uses it, rather than every projectile scene carrying its own copy.
    ///
    /// Null is correct and common: a glyph whose damage is the whole point and whose arrival needs
    /// no dressing resolves with no separate effect.
    [Export] public PackedScene ImpactPayload;

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