namespace Glyphwake.Glyphs;

/// What a cast is paid out of. Health-costing glyphs are a deliberate outlier (blood magic) and
/// stamina pays for movement-adjacent techniques, so cost cannot be assumed to be mana.
public enum CostResource
{
    Mana,
    Health,
    Stamina
}