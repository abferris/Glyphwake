using Godot;
using Glyphwake.Glyphs;

namespace Glyphwake.Player;

/// The technique layer: what turns points in a <see cref="TechniqueGlyphData"/> into a
/// capability the locomotion code can ask for. A technique rides an existing input rather
/// than a hotbar slot, so the contract with the body is a query -- can this fire, what does
/// it cost, how strong is it -- answered in one atomic call, never a piecewise read the
/// caller could get wrong between two frames.
///
/// Which glyph answers is data, not wiring: this asks the loadout's catalog for the technique
/// with its own trigger rather than holding an export per technique. The next ones (wall jump,
/// air dash, waterbreathing) each ride a different trigger, so each is a new entry in the
/// catalog and no change here or in the scene. The property stays settable for the GDScript
/// tests, which hand it a glyph directly instead of standing up a catalog.
public partial class PlayerTechniques : Node
{
	private const string LoadoutNodePath = "Loadout";
	private const string ResourcesNodePath = "Resources";

	private TechniqueGlyphData _technique;

	public TechniqueGlyphData Technique
	{
		get => _technique;
		set => _technique = value;
	}

	// Resolved by path at ready, in the house pattern (PlayerRig), rather than exported node
	// references: a node export serialized into a hand-written scene did not resolve under
	// 4.7 -- the property stayed null with no error and no warning, and only the probe found it.
	public GlyphLoadout Loadout { get; private set; }

	public PlayerResources Resources { get; private set; }

	public override void _Ready()
	{
		Node body = GetParent();
		Loadout = body?.GetNodeOrNull<GlyphLoadout>(LoadoutNodePath);
		Resources = body?.GetNodeOrNull<PlayerResources>(ResourcesNodePath);

		// Only when nothing already supplied one, so a caller that set the glyph before this node
		// entered the tree keeps it. Otherwise this node's own capability, which is the airborne
		// technique, comes from the catalog.
		if (_technique == null && Loadout?.Catalog != null)
			_technique = Loadout.Catalog.TechniqueWithTrigger(TechniqueTrigger.Airborne);
	}

	/// How many mid-air jumps the points in the technique buy: the glyph's own JumpCount stat
	/// (base plus scaling growth) floored to a count. 0 with no points in it.
	public int AirJumpCountAt(int points) =>
		Technique != null ? Mathf.FloorToInt(Technique.StatAt(StatKey.JumpCount, points)) : 0;

	/// The height of one mid-air jump, counted from 1.
	///
	/// The curve is the user's decade design (GlyphDecisions.md, "Techniques"): air jump 1
	/// unlocks at 1 point at half the normal jump and reaches twice it at 10; air jump 2
	/// unlocks at 11 at half and reaches twice it at 20; and so on to the pool. Each jump
	/// caps at twice the normal jump -- further points unlock new jumps rather than growing
	/// old ones. The ramp inside a decade is linear, which is a judgement call the doc does
	/// not settle. It is relative to the caller's normal jump height rather than an absolute,
	/// because "half of a normal jump" is what the design asks for.
	public float AirJumpHeightAt(int airJumpIndex, int points, float normalJumpHeight)
	{
		float unlockAt = 10f * (airJumpIndex - 1) + 1f;
		float ramp = Mathf.Clamp((points - unlockAt) / 9f, 0f, 1f);
		return normalJumpHeight * Mathf.Lerp(0.5f, 2f, ramp);
	}

	/// The one call the body makes when its jump input fires mid-air: checks the trigger, the
	/// activation threshold, the jump budget and the cost, pays the cost, and returns the
	/// height. -1 means nothing happened and nothing was spent; heights are always positive,
	/// so the sentinel cannot be mistaken for one. Returns the height rather than taking an
	/// out parameter so the GDScript tests call the same path the body does.
	public float TryAirJump(int airJumpsUsed, float normalJumpHeight)
	{
		if (Technique == null || Loadout == null || Resources == null)
			return -1f;
		if (Technique.Trigger != TechniqueTrigger.Airborne)
			return -1f;

		int points = Loadout.PointsFor(Technique);
		if (!Technique.IsActiveAt(points))
			return -1f;
		if (airJumpsUsed >= AirJumpCountAt(points))
			return -1f;

		// The cost is the glyph's call, not this layer's: every entry pays out of the resource
		// it declares, so the double jump's stamina entry pays stamina and the next technique
		// can declare its own. All entries are checked before any is paid, so a refusal spends
		// nothing and the call stays atomic across a mixed set of costs.
		foreach (GlyphCost cost in Technique.Costs)
		{
			if (cost != null && !Resources.CanSpend(cost.Resource, cost.AmountAt(points)))
				return -1f;
		}
		foreach (GlyphCost cost in Technique.Costs)
		{
			if (cost != null)
				Resources.TrySpend(cost.Resource, cost.AmountAt(points));
		}

		return AirJumpHeightAt(airJumpsUsed + 1, points, normalJumpHeight);
	}
}
