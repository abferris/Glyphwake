using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// The condition the caster's state must satisfy for a technique to fire. A technique is not
/// bound to a hotkey and is not aimed: it rides an existing input, so what varies between
/// techniques is the trigger, not the target.
public enum TechniqueTrigger
{
    /// Cast while airborne. Double jump, air dash.
    Airborne,

    /// Cast while against a wall. Wall jump.
    WallContact,

    /// Always available while points are in it, gated on holding an input.
    HeldInput,

    /// Available whenever submerged.
    Submerged
}

/// A technique glyph: a capability rather than a castable skill. It does not occupy a hotbar
/// slot and adds functionality that did not exist before, which is what separates it from an
/// active on one side and a passive on the other. When points are in it, it is on.
[GlobalClass]
public partial class TechniqueGlyphData : GlyphData
{
    [Export] public TechniqueTrigger Trigger;

    /// What the technique spends. The resource is the glyph's call: double jump pays mana
    /// (decided 10-02, more points spend less), air dash may pay stamina, and a held resource
    /// is what waterbreathing and spiderclimb drain.
    [Export] public Array<GlyphCost> Costs = new();

    /// Spends per second while the capability is held, such as climbing. Paid by a cost entry's
    /// PerSecond rather than here.
    [Export] public bool Held;

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