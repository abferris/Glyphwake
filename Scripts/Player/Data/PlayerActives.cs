using Godot;
using Glyphwake.Glyphs;

namespace Glyphwake.Player;

/// The active-glyph layer: what turns points in an <see cref="ActiveGlyphData"/> into a cast the
/// body can fire. It mirrors <see cref="PlayerTechniques"/> -- a technique rides an existing
/// input, an active takes the cast input -- and keeps the same contract: one atomic check-pay
/// call, never a piecewise read the caller could get wrong between two frames.
///
/// Which active answers is data, not wiring: this asks the loadout's catalog for the first active
/// with points in it rather than holding an export per glyph. Until the rune bar exists that is
/// the selection rule; when it does, this is the one place that changes to "the selected slot".
///
/// The property stays settable for the GDScript tests, which hand it a glyph directly instead of
/// standing up a catalog, exactly as the technique layer does.
public partial class PlayerActives : Node
{
	private const string LoadoutNodePath = "Loadout";
	private const string ResourcesNodePath = "Resources";

	private ActiveGlyphData _active;

	public ActiveGlyphData Active
	{
		get => _active;
		set => _active = value;
	}

	public GlyphLoadout Loadout { get; private set; }

	public PlayerResources Resources { get; private set; }

	public override void _Ready()
	{
		Node body = GetParent();
		Loadout = body?.GetNodeOrNull<GlyphLoadout>(LoadoutNodePath);
		Resources = body?.GetNodeOrNull<PlayerResources>(ResourcesNodePath);

		// Only when nothing already supplied one, so a caller that set the glyph before this node
		// entered the tree keeps it.
		if (_active == null && Loadout?.Catalog != null)
			_active = FirstCastable();
	}

	/// The first active glyph the player has points in. Null when the loadout has none or has
	/// allocated nothing to any active.
	private ActiveGlyphData FirstCastable()
	{
		foreach (ActiveGlyphData glyph in Loadout.Catalog.Actives)
			if (glyph != null && Loadout.PointsFor(glyph) > 0)
				return glyph;
		return null;
	}

	/// The damage the selected active deals at its points: the glyph's own Damage stat, base plus
	/// scaling growth. 0 with no active or no points.
	public float DamageAt(int points) =>
		Active != null ? Active.StatAt(StatKey.Damage, points) : 0f;

	/// The one call the body makes when its cast input fires: checks the activation threshold and
	/// the cost, pays the cost, and returns the damage to deal. -1 means nothing happened and
	/// nothing was spent; damage is never negative, so the sentinel cannot be mistaken for a hit.
	/// Returns the number rather than taking an out parameter so the GDScript tests call the same
	/// path the body does.
	public float TryCast()
	{
		if (Active == null || Loadout == null || Resources == null)
			return -1f;

		int points = Loadout.PointsFor(Active);
		if (!Active.IsActiveAt(points))
			return -1f;

		float cost = Active.CostUpFrontAt(CostResource.Mana, points);
		if (!Resources.TrySpend(CostResource.Mana, cost))
			return -1f;

		return Active.StatAt(StatKey.Damage, points);
	}
}