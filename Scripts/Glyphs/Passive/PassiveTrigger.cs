using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

public enum TriggerEvent
{
    OnHit,
    OnKill,
    OnDamaged,
    OnCast,
    OnLand
}

/// A passive that attaches something to an event rather than changing a number: burn on hit,
/// mana on kill. It fires a payload the same way an active does, so the two cannot diverge on
/// how a spawned effect gets its stats.
[GlobalClass]
public partial class PassiveTrigger : Resource
{
    [Export] public TriggerEvent Event;

    /// Only fire when a glyph in a matching school hits. Empty means any.
    [Export] public Godot.Collections.Array<GlyphSchool> TriggeringSchools = new();

    /// What gets spawned into the world when the event fires.
    [Export] public PackedScene Payload;

    /// The payload's own numbers before scaling, separate from the owning passive's because
    /// one passive can fire several payloads with different needs.
    [Export] public Array<StatValue> BaseStats = new();

    /// How the payload's numbers grow with points, defined by the trigger itself.
    [Export] public Array<GlyphScaling> Scalings = new();

    public float StatAt(StatKey key, int points) =>
        GlyphStats.StatAt(BaseStats, Scalings, key, points);

    public bool TryStatAt(StatKey key, int points, out float value) =>
        GlyphStats.TryStatAt(BaseStats, Scalings, key, points, out value);

    public bool FiredBy(GlyphData source)
    {
        if (TriggeringSchools.Count == 0)
            return true;
        return source != null && TriggeringSchools.Contains(source.School);
    }
}