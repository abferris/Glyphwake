using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// The project's authored glyphs, in one place: which .tres exist, grouped by the three
/// subclasses that behave differently. This is the answer to "what can this character have",
/// which every consumer needs and none of them should own.
///
/// Referencing the catalog rather than each glyph individually keeps that cost constant in the
/// scene: adding a glyph is a new .tres plus one line in GlyphCatalog.tres, and the scene does
/// not need reopening.
///
/// Three typed lists rather than one list with a kind field, for the same reason
/// GlyphDecisions.md gives for passive targets: the three subclasses carry different fields, and
/// one array would let every entry claim fields that cannot apply to it. It also means the
/// editor's type filter and the type-checked assignment both work, with no cast at the point of use.
///
/// This is shared authored data and is identical for every player. Per-player state -- which
/// glyphs someone has points in -- is GlyphLoadout's, and deliberately not stored here.
///
/// Known Godot limit, found by probing (test_glyph_catalog): `[Export] Array<SomeCSharpClass>`
/// does NOT preserve the script element type. Godot reports these arrays as Array[Resource] and
/// saves them without a type marker, whatever is written in the .tres by hand. So the three lists
/// give compile-time type safety on the C# side and self-document the grouping, but the editor
/// shows a plain resource array and will happily accept a passive in the Actives list. That is
/// what <see cref="Validate"/> is for -- it is the editor's missing type filter, done in code.
[GlobalClass]
public partial class GlyphCatalog : Resource
{
    [Export] public Array<TechniqueGlyphData> Techniques = new();

    [Export] public Array<ActiveGlyphData> Actives = new();

    [Export] public Array<PassiveGlyphData> Passives = new();

    /// The points a glyph starts on when a loadout is seeded from this catalog and that glyph has
    /// no entry yet. One value for every glyph because nothing needs per-glyph starting points
    /// yet -- it exists so the loadout is not authored in a scene file, and per-glyph seeds (and
    /// save-loaded allocations) replace it once the rune setup menu does.
    [Export] public int DefaultSeedPoints = GlyphData.ActivationPoints * 5;

    /// Every glyph in the catalog, flattened. For enumeration only -- a consumer that needs a
    /// glyph's own type should read the list it belongs to, so the typed fields stay reachable.
    public Array<GlyphData> AllGlyphs()
    {
        Array<GlyphData> all = new();
        foreach (TechniqueGlyphData technique in Techniques)
            if (technique != null)
                all.Add(technique);
        foreach (ActiveGlyphData active in Actives)
            if (active != null)
                all.Add(active);
        foreach (PassiveGlyphData passive in Passives)
            if (passive != null)
                all.Add(passive);
        return all;
    }

    /// The first technique with this trigger, or null when the catalog has none.
    ///
    /// Lookup is by trigger rather than by a per-technique export because that is the whole
    /// point of the catalog: PlayerTechniques asks for the capability it implements ("the
    /// airborne technique") and the wiring decides which .tres answers. Adding the airborne
    /// technique after the double jump therefore costs an entry in the catalog and nothing at
    /// all in the scene or in code.
    public TechniqueGlyphData TechniqueWithTrigger(TechniqueTrigger trigger)
    {
        foreach (TechniqueGlyphData technique in Techniques)
            if (technique != null && technique.Trigger == trigger)
                return technique;
        return null;
    }

    /// Checks that every glyph in the catalog is in the list its own subclass belongs to, and
    /// pushes a Godot error naming each one that is not.
    ///
    /// This exists because the editor cannot do it: the three arrays reach Godot as
    /// Array[Resource], so the inspector offers any resource for any of them and a glyph dragged
    /// into the wrong list would otherwise surface much later as a failed cast inside a consumer.
    /// A null slot is reported too, since an emptied element is just as easy to author.
    ///
    /// Returns true when the catalog is well formed. Callers treat a false as "do not seed".
    public bool Validate()
    {
        bool clean = true;

        foreach (GlyphData glyph in AllGlyphs())
        {
            if (glyph == null)
            {
                GD.PushError($"{ResourcePath}: the catalog holds a null glyph slot");
                clean = false;
            }
            else if (!InItsOwnList(glyph))
            {
                // A GlyphData that is none of the three falls to the default arm and is reported
                // as belonging nowhere, so a fourth subclass is caught rather than half-accepted.
                GD.PushError(
                    $"{ResourcePath}: '{glyph.ResourcePath}' ({glyph.GetType().Name}) belongs in " +
                    $"{DescribeListFor(glyph)}, and is not in it");
                clean = false;
            }
        }

        return clean;
    }

    private bool InItsOwnList(GlyphData glyph) => glyph switch
    {
        TechniqueGlyphData technique => Techniques.Contains(technique),
        ActiveGlyphData active => Actives.Contains(active),
        PassiveGlyphData passive => Passives.Contains(passive),
        _ => false
    };

    private static string DescribeListFor(GlyphData glyph) => glyph switch
    {
        TechniqueGlyphData => "Techniques",
        ActiveGlyphData => "Actives",
        PassiveGlyphData => "Passives",
        _ => "none of the three lists"
    };
}