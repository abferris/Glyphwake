using Godot;
using Glyphwake.Glyphs;

namespace Glyphwake.Player;

/// The active-glyph layer: what turns points in an <see cref="ActiveGlyphData"/> into a cast the
/// body can fire. It mirrors <see cref="PlayerTechniques"/> -- a technique rides an existing
/// input, an active takes the cast input -- and keeps the same contract: one atomic check-pay
/// call, never a piecewise read the caller could get wrong between two frames.
///
/// Which active answers is the loadout's selected skill, read live rather than resolved once --
/// the selection is the loadout's state, and a slot switch is a set on it, not wiring here.
public partial class PlayerActives : Node
{
	private const string LoadoutNodePath = "Loadout";
	private const string ResourcesNodePath = "Resources";

	private ActiveGlyphData _active;

	/// The active glyph the cast input fires: the loadout's selected skill, or the override.
	/// The override is for the GDScript tests, which hand a glyph directly instead of standing
	/// up a catalog, exactly as the technique layer does. When it is unset the selection reads
	/// through to the loadout live, so a slot switch takes effect on the next cast without this
	/// node knowing about slots.
	public ActiveGlyphData Active
	{
		get => _active != null ? _active : Loadout?.SelectedActive;
		set => _active = value;
	}

	public GlyphLoadout Loadout { get; private set; }

	public PlayerResources Resources { get; private set; }

	public override void _Ready()
	{
		Node body = GetParent();
		Loadout = body?.GetNodeOrNull<GlyphLoadout>(LoadoutNodePath);
		Resources = body?.GetNodeOrNull<PlayerResources>(ResourcesNodePath);
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