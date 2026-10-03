using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// A passive that changes other glyphs rather than the caster. Which glyphs it reaches is the
/// whole point of it: a Zephyr damage buff applies to Zephyr glyphs, and the filter is what
/// makes a specialized passive worth more points than a general one.
[GlobalClass]
public partial class GlyphModifier : Resource
{
    [Export] public StatKey Stat;
    [Export] public ModifierOperation Operation;
    [Export] public float Value;
    [Export] public float PerPoint;

    /// Which glyphs this reaches. An empty filter means every glyph, which is the "All" case.
    [Export] public Array<GlyphSchool> Schools = new();
    [Export] public Array<GlyphElement> Elements = new();

    /// Matched by GlyphTag.Id rather than resource identity.
    [Export] public Array<StringName> TargetTagIds = new();

    public float ValueAt(int points) => Value + PerPoint * Mathf.Max(0, points - 1);

    public bool Affects(GlyphData glyph)
    {
        if (glyph == null)
            return false;

        bool unfiltered = Schools.Count == 0 && Elements.Count == 0 && TargetTagIds.Count == 0;
        if (unfiltered)
            return true;

        if (Schools.Count > 0 && !Schools.Contains(glyph.School))
            return false;

        if (Elements.Count > 0)
        {
            bool anyElement = false;
            foreach (GlyphElement element in Elements)
            {
                if (element != GlyphElement.None && glyph.HasElement(element))
                {
                    anyElement = true;
                    break;
                }
            }
            if (!anyElement)
                return false;
        }

        foreach (StringName tagId in TargetTagIds)
        {
            if (glyph.HasTag(tagId))
                return true;
        }

        return TargetTagIds.Count == 0;
    }
}