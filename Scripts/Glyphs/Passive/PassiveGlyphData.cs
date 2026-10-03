using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// A passive glyph: no skill, no hotbar slot, usable in a safe zone. It adds no capability of
/// its own and binds no input; it changes something that already exists. The three lists are
/// separate because the three kinds of passive are genuinely different shapes — a stat you own,
/// a stat on another glyph filtered by classification, and an event that spawns something — and
/// one list carrying all three would let every modifier hold fields that do not apply to it.
[GlobalClass]
public partial class PassiveGlyphData : GlyphData
{
    /// The caster's own stats: health, mana, regen, speed.
    [Export] public Array<SelfStatModifier> SelfModifiers = new();

    /// Other glyphs, filtered by school, element or tag.
    [Export] public Array<GlyphModifier> GlyphModifiers = new();

    /// Event-driven: burn on hit, refill on kill.
    [Export] public Array<PassiveTrigger> Triggers = new();
}