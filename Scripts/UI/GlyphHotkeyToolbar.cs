using Godot;
using Godot.Collections;
using Glyphwake.Glyphs;
using Glyphwake.Player;

namespace Glyphwake.UI;

public partial class GlyphHotkeyToolbar : Control
{
	[Export] public Array<GlyphData> Glyphs = new();
	[Export] public float SlotSize = 44f;
	[Export] public float SlotGap = 6f;
	[Export] public float BarPad = 6f;
	[Export] public float LabelPadX = 8f;
	[Export] public float LabelPadY = 4f;
	[Export] public float BottomMargin = 16f;
	[Export] public int KeyLabelSize = 9;
	[Export] public int CostLabelSize = 8;
	[Export] public Color KeyLabelColor = new Color(1f, 1f, 1f, 0.8f);
	[Export] public Color CostLabelColor = new Color(0.55f, 0.72f, 1f, 0.95f);
	[Export] public Color GlyphNameColor = new Color(1f, 1f, 1f, 0.9f);
	[Export] public Color BarColor = new Color(0.06f, 0.05f, 0.04f, 0.82f);
	[Export] public Color BorderColor = new Color(0.08f, 0.06f, 0.04f, 1f);
	[Export] public Color HexBorderColor = new Color(0.45f, 0.4f, 0.33f, 0.9f);
	[Export] public Color SelectedColor = new Color(1f, 0.92f, 0.65f, 1f);
	[Export] public Color EmptyColor = new Color(1f, 1f, 1f, 0.14f);
	[Export] public GlyphElement HexBgElement = GlyphElement.Zephyr;
	[Export] public Color GlowColor = new Color(0f, 0f, 0f, 0.5f);
	[Export] public float GlowDepth = 4f;

	private const int SlotCount = 10;
	private static readonly string[] Hotkeys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" };
	private static readonly Key[] SlotKeyCodes =
		{ Key.Key1, Key.Key2, Key.Key3, Key.Key4, Key.Key5, Key.Key6, Key.Key7, Key.Key8, Key.Key9, Key.Key0 };

	private PlayerController _player;
	private GlyphData[] _drawnGlyphs = new GlyphData[SlotCount];
	private string[] _drawnCosts = new string[SlotCount];
	private GlyphData _drawnSelected;
	private readonly bool[] _slotHeld = new bool[SlotCount];

	private PlayerController Player
	{
		get
		{
			if (_player == null)
			{
				Node node = GetParent();
				while (node != null && node is not PlayerController)
					node = node.GetParent();
				_player = node as PlayerController;
			}
			return _player;
		}
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		if (@event is not InputEventMouseButton wheel || !wheel.Pressed)
			return;
		int step;
		if (wheel.ButtonIndex == MouseButton.WheelDown)
			step = 1;
		else if (wheel.ButtonIndex == MouseButton.WheelUp)
			step = -1;
		else
			return;
		StepSelection(step);
		GetViewport().SetInputAsHandled();
	}

	/// Steps the selected skill one slot toward <paramref name="step"/>: +1 is the next slot to
	/// the right, -1 the previous to the left. Empty slots are skipped -- the step lands on the
	/// next equipped one -- and the edges wrap, so scrolling down from the last slot lands on
	/// the first and scrolling up from the first lands on the last. The equipped order is the
	/// bar's own (techniques never take a slot, see _Process); the selection is the loadout's,
	/// so the step is a set on it. A selection that is not in the bar (a hand-set glyph) steps
	/// in from the nearest edge.
	private void StepSelection(int step)
	{
		GlyphLoadout loadout = Player?.Techniques?.Loadout;
		if (loadout == null)
			return;

		// The equipped slots as the player sees them: techniques never take one, and only an
		// active answers the selection, so empty and non-active slots are skipped here by
		// construction rather than stepped over one at a time.
		var equipped = new System.Collections.Generic.List<ActiveGlyphData>();
		foreach (GlyphData glyph in Glyphs)
			if (glyph is ActiveGlyphData active && active != null)
				equipped.Add(active);
		if (equipped.Count == 0)
			return;

		int count = equipped.Count;
		int i = equipped.IndexOf(loadout.SelectedActive);
		if (i < 0)
			i = step > 0 ? -1 : 0;
		i = (i + step + count) % count;
		loadout.SelectedActive = equipped[i];
	}

	public override void _Process(double delta)
	{
		PlayerController player = Player;
		GlyphLoadout loadout = player?.Techniques?.Loadout;

		bool changed = false;
		GlyphData selected = loadout?.SelectedActive;
		if (!ReferenceEquals(selected, _drawnSelected))
		{
			_drawnSelected = selected;
			changed = true;
		}

		// Techniques are capabilities that ride an existing input, not equipables: they never
		// take a slot, and a technique in the list shifts the equipables up rather than showing
		// a skill that cannot be cast from the bar.
		int slot = 0;
		for (int i = 0; i < Glyphs.Count && slot < SlotCount; i++)
		{
			GlyphData glyph = Glyphs[i];
			if (glyph is TechniqueGlyphData)
				continue;
			string cost = glyph != null ? ManaCostLabel(glyph, loadout) : "";
			if (!ReferenceEquals(glyph, _drawnGlyphs[slot]) || cost != _drawnCosts[slot])
			{
				_drawnGlyphs[slot] = glyph;
				_drawnCosts[slot] = cost;
				changed = true;
			}
			slot++;
		}
		for (; slot < SlotCount; slot++)
		{
			if (_drawnGlyphs[slot] != null)
			{
				_drawnGlyphs[slot] = null;
				_drawnCosts[slot] = "";
				changed = true;
			}
		}

		// The number keys select a slot: a press, not a hold, and an empty slot keeps the
		// current selection. The toolbar owns the key-to-slot mapping; the selection itself is
		// the loadout's, and only an active can answer it -- a technique never routes through
		// the bar or the cast input (its activation is its own trigger, never the mouse).
		for (int i = 0; i < SlotCount; i++)
		{
			bool held = Input.IsPhysicalKeyPressed(SlotKeyCodes[i]);
			if (held && !_slotHeld[i] && _drawnGlyphs[i] is ActiveGlyphData active && loadout != null)
			{
				loadout.SelectedActive = active;
				changed = true;
			}
			_slotHeld[i] = held;
		}
		if (changed)
			QueueRedraw();
	}

	public override void _Draw()
	{
		float r = SlotSize * 0.5f;
		float hexH = SlotSize * Mathf.Sqrt(3f) * 0.5f;
		float cellW = SlotSize + LabelPadX * 2f;
		float cellH = hexH + LabelPadY * 2f;
		float barW = SlotCount * cellW + (SlotCount - 1) * SlotGap + BarPad * 2f;
		float barH = cellH + BarPad * 2f;
		Vector2 bar = new Vector2((Size.X - barW) * 0.5f, Size.Y - BottomMargin - barH);
		Rect2 barRect = new Rect2(bar, new Vector2(barW, barH));

		DrawRect(barRect, BarColor, true);
		DrawRect(barRect, BorderColor, false, 2f);

		for (int i = 0; i < SlotCount; i++)
		{
			Vector2 cell = bar + new Vector2(BarPad + i * (cellW + SlotGap), BarPad);
			DrawSlot(cell, cellW, cellH, r, hexH, i);
		}
	}

	private void DrawSlot(Vector2 cell, float cellW, float cellH, float r, float hexH, int slot)
	{
		Vector2 c = cell + new Vector2(cellW * 0.5f, cellH * 0.5f);
		Vector2[] corners =
		{
			c + new Vector2(r, 0f),
			c + new Vector2(r * 0.5f, -hexH * 0.5f),
			c + new Vector2(-r * 0.5f, -hexH * 0.5f),
			c + new Vector2(-r, 0f),
			c + new Vector2(-r * 0.5f, hexH * 0.5f),
			c + new Vector2(r * 0.5f, hexH * 0.5f)
		};

		GlyphData glyph = _drawnGlyphs[slot];
		bool filled = glyph != null;
		bool selected = filled && ReferenceEquals(Player?.Techniques?.Loadout?.SelectedActive, glyph);

		string stonePath = $"res://Assets/Glyphs/{HexBgElement.ToString().ToLowerInvariant()}_hex_glyph_bg.png";
		if (filled && ResourceLoader.Exists(stonePath) && GD.Load<Texture2D>(stonePath) is Texture2D stoneTex)
		{
			Vector2 uvOrigin = c - new Vector2(r, hexH * 0.5f);
			Vector2 uvSpan = new Vector2(r * 2f, hexH);
			Vector2[] uv = new Vector2[6];
			for (int i = 0; i < 6; i++)
				uv[i] = (corners[i] - uvOrigin) / uvSpan;
			DrawPolygon(corners, new[] { Colors.White }, uv, stoneTex);
		}
		else
		{
			DrawPolygon(corners, new[] { filled ? new Color(0.22f, 0.18f, 0.13f, 0.95f) : EmptyColor });
		}

		if (glyph?.Icon != null)
		{
			Vector2 uvOrigin = c - new Vector2(r, hexH * 0.5f);
			Vector2 uvSpan = new Vector2(r * 2f, hexH);
			Vector2[] uv = new Vector2[6];
			for (int i = 0; i < 6; i++)
				uv[i] = (corners[i] - uvOrigin) / uvSpan;
			DrawPolygon(corners, new[] { Colors.White }, uv, glyph.Icon);
		}
		else if (!string.IsNullOrEmpty(glyph?.DisplayName))
		{
			Font font = ThemeDB.FallbackFont;
			int fontSize = Mathf.RoundToInt(SlotSize * 0.25f);
			float maxWidth = SlotSize * 0.8f;
			while (fontSize > 6
				&& font.GetStringSize(glyph.DisplayName, HorizontalAlignment.Left, -1, fontSize).X > maxWidth)
				fontSize--;
			Vector2 pos = new Vector2(c.X - maxWidth * 0.5f, c.Y + fontSize * 0.35f);
			DrawString(font, pos + Vector2.One, glyph.DisplayName, HorizontalAlignment.Center, maxWidth,
				fontSize, new Color(0f, 0f, 0f, 0.8f));
			DrawString(font, pos, glyph.DisplayName, HorizontalAlignment.Center, maxWidth, fontSize,
				GlyphNameColor);
		}

		if (filled)
			DrawGlow(corners, c, hexH);

		Vector2[] loop = new Vector2[7];
		for (int i = 0; i < 6; i++)
			loop[i] = corners[i];
		loop[6] = corners[0];
		Color hexBorder = HexBorderColor;
		if (!filled)
			hexBorder.A *= 0.5f;
		if (selected)
		{
			hexBorder = SelectedColor;
			DrawPolyline(loop, hexBorder, 3f, true);
		}
		else
			DrawPolyline(loop, hexBorder, 1.5f, true);

		Font labelFont = ThemeDB.FallbackFont;
		Vector2 keyPos = new Vector2(cell.X + 2f, cell.Y + LabelPadY + KeyLabelSize + 1f);
		DrawString(labelFont, keyPos, Hotkeys[slot], HorizontalAlignment.Left, SlotSize, KeyLabelSize,
			KeyLabelColor);
		if (_drawnCosts[slot] != "")
		{
			Vector2 costPos = new Vector2(cell.X + 2f, cell.Y + cellH - 2f);
			DrawString(labelFont, costPos, _drawnCosts[slot], HorizontalAlignment.Left, SlotSize,
				CostLabelSize, CostLabelColor);
		}
	}

	private void DrawGlow(Vector2[] corners, Vector2 c, float hexH)
	{
		if (GlowDepth <= 0f || GlowColor.A <= 0f)
			return;
		float k = 1f - GlowDepth / (hexH * 0.5f);
		if (k <= 0f)
			k = 0f;
		Color zero = new Color(GlowColor.R, GlowColor.G, GlowColor.B, 0f);
		Vector2[] inner = new Vector2[6];
		for (int i = 0; i < 6; i++)
			inner[i] = c + (corners[i] - c) * k;
		for (int i = 0; i < 6; i++)
		{
			int j = (i + 1) % 6;
			DrawPolygon(
				new[] { corners[i], corners[j], inner[j], inner[i] },
				new[] { GlowColor, GlowColor, zero, zero });
		}
	}

	private static string ManaCostLabel(GlyphData glyph, GlyphLoadout loadout)
	{
		Array<GlyphCost> costs = glyph switch
		{
			ActiveGlyphData active => active.Costs,
			TechniqueGlyphData technique => technique.Costs,
			_ => null
		};
		if (costs == null || costs.Count == 0)
			return "";

		int points = loadout != null ? loadout.PointsFor(glyph) : 0;
		float upFront = 0f;
		float perSecond = 0f;
		bool hasMana = false;
		foreach (GlyphCost cost in costs)
		{
			if (cost == null || cost.Resource != CostResource.Mana)
				continue;
			hasMana = true;
			upFront += cost.AmountAt(points);
			perSecond += cost.PerSecondAt(points);
		}
		if (!hasMana)
			return "";
		if (upFront > 0f)
			return Mathf.RoundToInt(upFront).ToString();
		if (perSecond > 0f)
			return $"{Mathf.RoundToInt(perSecond)}/s";
		return "0";
	}
}
