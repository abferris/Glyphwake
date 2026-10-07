using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

public abstract partial class GlyphData : Resource
{
    [Export] public string DisplayName = "";
    [Export(PropertyHint.MultilineText)] public string Description = "";
    [Export] public Texture2D Icon;

    [Export] public GlyphSchool School;

    /// The animation this glyph plays on its caster when it fires, if it has one.
    ///
    /// On the base rather than on ActiveGlyphData because a technique needs one too -- an air dash
    /// and a wall jump both want a clip -- and a passive whose trigger fires on a swing wants one
    /// on the trigger. Nothing reads this yet: casting is not implemented, so this is the
    /// attachment point rather than a working feature. See GlyphDecisions.md, "Not built yet".
    ///
    /// Null is the common case and is correct: the game is first person, so a glyph the player
    /// never sees themselves perform needs no cast animation.
    [Export] public GlyphCastAnimation CastAnimation;

    /// The glyph's own numbers before scaling. Which keys appear here is deliberate: an
    /// Impulse cast has no CastTime entry and a Self target has no Range entry, and absence
    /// is how "zero for that mode" is expressed.
    [Export] public Array<StatValue> BaseStats = new();

    /// How the glyph's numbers grow with points, defined by the glyph itself rather than a
    /// shared formula: one glyph scales linearly, another accelerates or arrives in chunks.
    [Export] public Array<GlyphScaling> Scalings = new();

    /// Optional, and more than one is allowed. Empty or all-None means the glyph has no element
    /// and is resisted by nothing.
    [Export] public Array<GlyphElement> Elements = new();

    /// Free-form tags for targeting that the closed School/Element sets do not cover. Matched by
    /// <see cref="GlyphTag.Id"/>, not by resource identity, so a tag authored in the editor and
    /// one built in code still match.
    [Export] public Array<GlyphTag> Tags = new();

    public const int ActivationPoints = 1;
    public const int TotalPointPool = 100;
    public const int SecondaryGuidepostPoints = 3;
    public const int ImpactfulGuidepostPoints = 5;
    public const int PrimaryGuidepostPoints = 10;
    public const int SpecialistGuidepostPoints = 15;

    public bool IsActiveAt(int points) => points >= ActivationPoints;

    /// The glyph's value for a stat at a point count: base plus scaling growth. Returns 0
    /// when the glyph does not have the stat, so a caller does not have to know whether it
    /// exists.
    public float StatAt(StatKey key, int points) =>
        GlyphStats.StatAt(BaseStats, Scalings, key, points);

    public bool TryStatAt(StatKey key, int points, out float value) =>
        GlyphStats.TryStatAt(BaseStats, Scalings, key, points, out value);

    public bool HasElement(GlyphElement element)
    {
        if (element == GlyphElement.None)
            return Elements.Count == 0 || !Elements.Contains(GlyphElement.None);
        return Elements.Contains(element);
    }

    public bool HasTag(GlyphTag tag) => tag != null && HasTag(tag.Id);

    public bool HasTag(StringName tagId)
    {
        if (tagId == null || tagId.IsEmpty)
            return false;
        foreach (GlyphTag tag in Tags)
        {
            if (tag != null && tag.Id == tagId)
                return true;
        }
        return false;
    }
}