using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// A player's point allocation: which glyphs that player has put points in, and how many.
/// Read by everything that turns points into numbers -- techniques, the future caster, the
/// passive resolver -- so no consumer has to know where the points live.
///
/// Allocation is keyed by resource path rather than by instance: two instances of the same
/// .tres are the same glyph with the same points, which is also what keeps a duplicated
/// resource from masquerading as a second glyph. A glyph built in code has no path, so those
/// fall back to instance identity.
///
/// This is the player-owned half and it is meant to be runtime state: Entries is seeded from
/// <see cref="Catalog"/> on ready and then changed by <see cref="TrySetPoints"/>, and saved with
/// the player rather than authored into a scene. The catalog is the shared list of which glyphs
/// exist; nothing here decides that.
    [GlobalClass]
    public partial class GlyphLoadout : Node
    {
        [Export] public GlyphCatalog Catalog;

        [Export] public Array<GlyphLoadoutEntry> Entries = new();

        /// The player's selected skill: the slot the cast input fires. Player-owned runtime state
        /// like the entries -- the default is the catalog's first active (slot 1 of the bar) until
        /// a key or the rune setup menu changes it, and a switch sets it here so everything that
        /// reads the selection reads one place.
        [Export] public ActiveGlyphData SelectedActive;

        public override void _Ready()
        {
            // Seed rather than assign, so an entry that is already present -- authored, or restored
            // from a save -- is left exactly as it is. A glyph with no entry gets the catalog's
            // starting points; a glyph the player has deliberately zeroed keeps that.
            if (Catalog == null)
                return;

            // The catalog's three lists reach Godot as untyped resource arrays, so a glyph in the
            // wrong one is only detectable here. Do not seed off a catalog that failed: a wrong-typed
            // glyph would surface as a failed cast inside a consumer, with no clue which entry caused
            // it.
            if (!Catalog.Validate())
            {
                GD.PushError($"{GetPath()}: the glyph catalog is malformed, so the loadout was not seeded");
                return;
            }

            foreach (GlyphData glyph in Catalog.AllGlyphs())
                if (glyph != null && !HasEntry(glyph))
                    TrySetPoints(glyph, Catalog.DefaultSeedPoints);

            // The default selection is the catalog's first active -- slot 1. Only when nothing
            // already selected one, so a restored save or a caller that set it first keeps it.
            if (SelectedActive == null)
            {
                foreach (ActiveGlyphData glyph in Catalog.Actives)
                    if (glyph != null)
                    {
                        SelectedActive = glyph;
                        break;
                    }
            }
        }

    /// Whether this loadout has an entry for the glyph at all, which is not the same question as
    /// how many points it has: a legal zero-point allocation stores an entry (see
    /// <see cref="TrySetPoints"/>), and the distinction is what lets seeding leave an existing
    /// allocation alone.
    public bool HasEntry(GlyphData glyph)
    {
        foreach (GlyphLoadoutEntry entry in Entries)
            if (entry != null && SameGlyph(entry.Glyph, glyph))
                return true;
        return false;
    }

    /// The whole loadout's spend against the shared 100-point pool.
    public int TotalPoints()
    {
        int total = 0;
        foreach (GlyphLoadoutEntry entry in Entries)
        {
            if (entry != null)
                total += entry.Points;
        }
        return total;
    }

    /// The points a player has in one glyph. Summed, so a duplicated resource folds into one
    /// number the same way the pool accounts for it.
    public int PointsFor(GlyphData glyph)
    {
        int total = 0;
        foreach (GlyphLoadoutEntry entry in Entries)
        {
            if (entry != null && SameGlyph(entry.Glyph, glyph))
                total += entry.Points;
        }
        return total;
    }

    public bool IsActive(GlyphData glyph) =>
        glyph != null && glyph.IsActiveAt(PointsFor(glyph));

    /// Sets a glyph's points, adding the entry when there is none. Refuses a negative count
    /// and any allocation that would push the loadout past the shared pool; the pool is the
    /// one cap, since a glyph may sink all of it.
    public bool TrySetPoints(GlyphData glyph, int points)
    {
        if (glyph == null || points < 0)
            return false;

        int others = TotalPoints() - PointsFor(glyph);
        if (others + points > GlyphData.TotalPointPool)
            return false;

        bool set = false;
        foreach (GlyphLoadoutEntry entry in Entries)
        {
            // PointsFor sums, so a duplicated glyph folds into its first entry rather than
            // splitting the new count across instances.
            if (entry != null && SameGlyph(entry.Glyph, glyph))
            {
                entry.Points = set ? 0 : points;
                set = true;
            }
        }
        if (set)
            return true;

        Entries.Add(new GlyphLoadoutEntry { Glyph = glyph, Points = points });
        return true;
    }

    private static bool SameGlyph(GlyphData a, GlyphData b)
    {
        if (a == null || b == null)
            return false;
        if (a == b)
            return true;

        string path = a.ResourcePath;
        return !string.IsNullOrEmpty(path) && path == b.ResourcePath;
    }
}
