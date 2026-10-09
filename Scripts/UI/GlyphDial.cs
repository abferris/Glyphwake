using System.Collections.Generic;
using Godot;
using Glyphwake.Glyphs;
using Glyphwake.Player;

namespace Glyphwake.UI;

public partial class GlyphDial : Control
{
	[Export]
	public float DialScale
	{
		get => _dialScale;
		set
		{
			float clamped = value > 0f ? value : 1f;
			if (Mathf.IsEqualApprox(_dialScale, clamped))
				return;
			_dialScale = clamped;
			QueueRedraw();
		}
	}

	[Export] public float HexWidth = 150f;
	[Export] public float BarWidth = 10.5f;
	[Export] public float DividerWidth = 4f;
	[Export] public float CornerRadius = 2f;
	[Export] public float GlyphSize = 120f;
	[Export] public int GlyphNameSize = 14;
	[Export] public Color HealthColor = new Color(0.85f, 0.2f, 0.25f, 0.9f);
	[Export] public Color ManaColor = new Color(0.25f, 0.5f, 0.9f, 0.9f);
	[Export] public Color StaminaColor = new Color(1f, 1f, 1f, 0.9f);
	[Export] public Color EmptyColor = new Color(1f, 1f, 1f, 0.14f);
	[Export] public Color BackColor = new Color(0f, 0f, 0f, 0.35f);
	[Export] public Color GlyphNameColor = new Color(1f, 1f, 1f, 0.85f);
	[Export] public Color BorderColor = new Color(0.08f, 0.06f, 0.04f, 1f);
	[Export] public GlyphElement HexBgElement = GlyphElement.Zephyr;
	[Export] public Key ToggleKey = Key.Quoteleft;
	[Export] public int StatsFontSize = 7;
	[Export] public Color StatsColor = new Color(1f, 1f, 1f, 0.8f);
	private float _dialScale = 1f;
	private bool _showStats;
	private PlayerController _player;
	private GlyphData _glyph;
	private Texture2D _glyphIcon;
	private string _glyphName;
	private float _health = -1f;
	private float _maxHealth = -1f;
	private float _mana = -1f;
	private float _maxMana = -1f;
	private float _stamina = -1f;
	private float _maxStamina = -1f;

	private float Scl => DialScale;
	private float BarW => BarWidth * Scl;
	private float DividerW => DividerWidth * Scl;
	private float CornerR => CornerRadius * Scl;

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

	public override void _Process(double delta)
	{
		PlayerController player = Player;
		if (player == null)
			return;

		PlayerResources resources = player.Techniques?.Resources;
		GlyphLoadout loadout = player.Techniques?.Loadout;

		float health = resources?.Health ?? 0f;
		float maxHealth = resources?.MaxHealth ?? 1f;
		float mana = resources?.Mana ?? 0f;
		float maxMana = resources?.MaxMana ?? 1f;
		float stamina = resources?.Stamina ?? 0f;
		float maxStamina = resources?.MaxStamina ?? 1f;

		GlyphData glyph = loadout?.SelectedActive;
		Texture2D icon = glyph?.Icon;
		string name = glyph?.DisplayName ?? "";

		if (health != _health || maxHealth != _maxHealth || mana != _mana || maxMana != _maxMana
			|| stamina != _stamina || maxStamina != _maxStamina
			|| !ReferenceEquals(glyph, _glyph) || icon != _glyphIcon || name != _glyphName)
		{
			_health = health;
			_maxHealth = maxHealth;
			_mana = mana;
			_maxMana = maxMana;
			_stamina = stamina;
			_maxStamina = maxStamina;
			_glyph = glyph;
			_glyphIcon = icon;
			_glyphName = name;
			QueueRedraw();
		}
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		if (@event is not InputEventKey key || !key.Pressed || key.Echo)
			return;
		if (key.PhysicalKeycode != ToggleKey && key.Keycode != ToggleKey)
			return;
		_showStats = !_showStats;
		QueueRedraw();
		GetViewport().SetInputAsHandled();
	}

	public override void _Draw()
	{
		float r = HexWidth * 0.5f * Scl;
		float apothem = (r * Mathf.Sqrt(3f) / 2f) + Scl;
		Vector2 c = new Vector2(Size.X - r - 3f * Scl, Size.Y - apothem - 2f * Scl);

        Vector2[] corners =
        {
            c + new Vector2(r, 0f),
            c + new Vector2(r / 2f, -apothem),
            c + new Vector2(-r / 2f, -apothem),
            c + new Vector2(-r, 0f),
            c + new Vector2(-r / 2f, apothem),
            c + new Vector2(r / 2f, apothem)
        };

        // Load texture if available
        string stonePath = $"res://Assets/Glyphs/{HexBgElement.ToString().ToLowerInvariant()}_hex_glyph_bg.png";
        Texture2D stoneTex = ResourceLoader.Exists(stonePath) ? GD.Load<Texture2D>(stonePath) : null;

        // Draw outer stone-like border (thick)
        Vector2[] outerCorners = new Vector2[6];
        for (int i = 0; i < 6; i++)
            outerCorners[i] = corners[i] + (corners[i] - c).Normalized() * 2.5f * Scl;
        DrawPolygon(outerCorners, new[] { new Color(0.15f, 0.12f, 0.09f, 1f) });

        // Inner bevel
        Vector2[] bevelIn = new Vector2[6];
        for (int i = 0; i < 6; i++)
            bevelIn[i] = corners[i] + (corners[i] - c).Normalized() * (-0.5f * Scl);
        DrawPolygon(bevelIn, new[] { new Color(0.25f, 0.2f, 0.15f, 1f) });

        // Main stone background - try texture first
        if (stoneTex != null)
        {
            Vector2 uvOrigin = c - new Vector2(r, apothem);
            Vector2 uvSpan = new Vector2(r * 2f, apothem * 2f);
            Vector2[] uv = new Vector2[6];
            for (int i = 0; i < 6; i++)
                uv[i] = (corners[i] - uvOrigin) / uvSpan;
            DrawPolygon(corners, new[] { Colors.White }, uv, stoneTex);
        }
        else
        {
            DrawPolygon(corners, new[] { new Color(0.22f, 0.18f, 0.13f, 0.95f) });

            // Stone texture-like highlights
            for (int i = 0; i < 6; i++)
            {
                Vector2 a = corners[i];
                Vector2 b = corners[(i + 1) % 6];
                DrawLine(a, b, new Color(0.35f, 0.29f, 0.22f, 0.4f), 0.8f * Scl, true);
                DrawLine(a, a + (a - c).Normalized() * 0.3f * Scl, new Color(0.4f, 0.33f, 0.25f, 0.25f), 0.5f * Scl, true);
            }
        }

        // // Draw empty tracks first (no outline on tracks to avoid clutter at overlaps)
        // for (int i = 0; i < 4; i++)
        //     DrawBar(corners[i], corners[(i + 1) % 6], 1f, c, new Color(0.12f, 0.1f, 0.08f, 0.6f), false);

        // Draw ornamental outer edge
        for (int i = 0; i < 6; i++)
            DrawLine(outerCorners[i], outerCorners[(i + 1) % 6], new Color(0.08f, 0.06f, 0.04f, 1f), 1.0f * Scl, true);
        for (int i = 0; i < 6; i++)
            DrawLine(corners[i], corners[(i + 1) % 6], new Color(0.08f, 0.06f, 0.04f, 0.8f), 0.5f * Scl, true);

	float health = HealthFraction();
	float mana = ManaFraction();
	float stamina = StaminaFraction();

        Vector2 splitApex = corners[2];
        Vector2 splitDir = (c - splitApex).Normalized();

        DrawResource(corners[4], corners[3], corners[2], health, c, HealthColor, splitApex, splitDir, true);
        DrawResource(corners[0], corners[1], corners[2], mana, c, ManaColor, splitApex, splitDir, true);
        DrawResource(corners[0], corners[5], corners[4], stamina, c, StaminaColor, corners[4],
            (c - corners[4]).Normalized(), true);
        DrawDivider(corners[2], corners[1], c);
        DrawDivider(corners[4], corners[3], c);
        DrawDivider(corners[0], corners[5], c);

        DrawGlyphGraphic(c, apothem);

        Vector2[] innerRing = new Vector2[6];
        for (int i = 0; i < 6; i++)
        {
            Vector2 prevCorner = corners[(i + 5) % 6];
            Vector2 corner = corners[i];
            Vector2 nextCorner = corners[(i + 1) % 6];
            Vector2 prevDir = (corner - prevCorner).Normalized();
            Vector2 nextDir = (nextCorner - corner).Normalized();
            Vector2 prevOffset = prevCorner
                + InwardNormal(prevDir, c, (prevCorner + corner) / 2f) * BarW;
            Vector2 nextOffset = corner
                + InwardNormal(nextDir, c, (corner + nextCorner) / 2f) * BarW;
            innerRing[i] = LineIntersect(prevOffset, prevDir, nextOffset, nextDir);
        }
        for (int i = 0; i < 6; i++)
            DrawLine(innerRing[i], innerRing[(i + 1) % 6], BorderColor, 3f * Scl, true);

        if (_showStats)
        {
            DrawStatLabel(corners[3], corners[2], c, "Health", _health, _maxHealth);
            DrawStatLabel(corners[2], corners[1], c, "Mana", _mana, _maxMana);
            DrawStatLabel(corners[4], corners[5], c, "Stamina", _stamina, _maxStamina);
        }
	}

	private float HealthFraction() =>
		_maxHealth > 0f ? Mathf.Clamp(_health / _maxHealth, 0f, 1f) : 0f;

	private float ManaFraction() =>
		_maxMana > 0f ? Mathf.Clamp(_mana / _maxMana, 0f, 1f) : 0f;

	private float StaminaFraction() =>
		_maxStamina > 0f ? Mathf.Clamp(_stamina / _maxStamina, 0f, 1f) : 0f;

    private void DrawResource(Vector2 start, Vector2 mid, Vector2 end, float fraction, Vector2 c, Color color,
        Vector2 splitApex, Vector2 splitDir, bool drawOutline = false)
    {
        float first = start.DistanceTo(mid);
        float second = end.DistanceTo(mid);
        if (first <= 0f || second <= 0f)
            return;

        float lit = Mathf.Clamp(fraction, 0f, 1f) * (first + second);
        if (lit <= 0f)
            return;

        Vector2 dir1 = (mid - start) / first;
        Vector2 dir2 = (end - mid) / second;
        Vector2 n1 = InwardNormal(dir1, c, (start + mid) / 2f);
        Vector2 n2 = InwardNormal(dir2, c, (mid + end) / 2f);
        float keepSign = SplitSide(splitApex, splitDir, mid) >= 0f ? 1f : -1f;
        Vector2 startApex = start;
        Vector2 startDir = (c - start).Normalized();
        float startKeepSign = SplitSide(startApex, startDir, mid) >= 0f ? 1f : -1f;

        bool spansSecond = lit > first;
        Vector2 tip1 = start + dir1 * Mathf.Min(lit, first);
        Vector2 tip = spansSecond ? mid + dir2 * (lit - first) : tip1;
        Vector2 tipInner = tip + (spansSecond ? n2 : n1) * BarW;

        Vector2[] Round(Vector2[] poly) =>
            RoundEnds(poly, tip, tipInner, splitApex, splitDir, startApex, startDir);

        Vector2[] path = OutlinePath(start, mid, tip, dir1, dir2, n1, n2, spansSecond);
        path = ClipSide(path, splitApex, splitDir, keepSign);
        path = ClipSide(path, startApex, startDir, startKeepSign);
        path = Round(path);
        if (path.Length >= 3)
            DrawPolygon(path, new[] { color });

        if (!drawOutline || path.Length < 3)
            return;

        Vector2[] loop = new Vector2[path.Length + 1];
        for (int i = 0; i < path.Length; i++)
            loop[i] = path[i];
        loop[path.Length] = path[0];
        DrawPolyline(loop, new Color(0.08f, 0.06f, 0.04f, 1f), 0.5f * Scl, true);
    }

    private Vector2[] RoundEnds(Vector2[] poly, Vector2 tip, Vector2 tipInner, Vector2 splitApex,
        Vector2 splitDir, Vector2 startApex, Vector2 startDir)
    {
        if (CornerR <= 0f || poly.Length < 3)
            return poly;

        int count = poly.Length;
        List<Vector2> result = new List<Vector2>(count + 16);
        for (int i = 0; i < count; i++)
        {
            Vector2 prev = poly[(i + count - 1) % count];
            Vector2 vertex = poly[i];
            Vector2 next = poly[(i + 1) % count];

            bool round = Mathf.Abs(SplitSide(startApex, startDir, vertex)) <= 0.001f
                || Mathf.Abs(SplitSide(splitApex, splitDir, vertex)) <= 0.001f
                || vertex.DistanceSquaredTo(tip) <= 0.0001f
                || vertex.DistanceSquaredTo(tipInner) <= 0.0001f;

            Vector2 back = vertex - prev;
            Vector2 forward = next - vertex;
            float backLength = back.Length();
            float forwardLength = forward.Length();
            if (!round || backLength <= 0.001f || forwardLength <= 0.001f)
            {
                result.Add(vertex);
                continue;
            }

            float radius = Mathf.Min(CornerR, Mathf.Min(backLength, forwardLength) * 0.45f);
            Vector2 from = vertex - back * (radius / backLength);
            Vector2 to = vertex + forward * (radius / forwardLength);
            const int segments = 4;
            for (int s = 0; s <= segments; s++)
            {
                float t = s / (float)segments;
                float u = 1f - t;
                result.Add(from * (u * u) + vertex * (2f * u * t) + to * (t * t));
            }
        }
        return result.ToArray();
    }

    private Vector2[] OutlinePath(Vector2 start, Vector2 mid, Vector2 tip, Vector2 dir1, Vector2 dir2,
        Vector2 n1, Vector2 n2, bool spansSecond)
    {
        if (!spansSecond)
        {
            return new[]
            {
                start,
                tip,
                tip + n1 * BarW,
                start + n1 * BarW
            };
        }

        Vector2 innerStart = start + n1 * BarW;
        Vector2 innerJoin = LineIntersect(innerStart, dir1, mid + n2 * BarW, dir2);
        if ((tip - mid).Dot(dir2) >= (innerJoin - mid).Dot(dir2))
            return new[] { start, mid, tip, tip + n2 * BarW, innerJoin, innerStart };
        return new[] { start, mid, tip, tip + n2 * BarW, innerStart };
    }

    private static Vector2 InwardNormal(Vector2 dir, Vector2 c, Vector2 mid)
    {
        Vector2 n = dir.Orthogonal();
        return n.Dot(c - mid) < 0f ? -n : n;
    }

    private static float SplitSide(Vector2 linePoint, Vector2 lineDir, Vector2 point) =>
        lineDir.X * (point.Y - linePoint.Y) - lineDir.Y * (point.X - linePoint.X);

    private static Vector2[] ClipSide(Vector2[] polygon, Vector2 linePoint, Vector2 lineDir, float keepSign)
    {
        List<Vector2> result = new List<Vector2>(polygon.Length + 2);
        for (int i = 0; i < polygon.Length; i++)
        {
            Vector2 a = polygon[i];
            Vector2 b = polygon[(i + 1) % polygon.Length];
            float sa = SplitSide(linePoint, lineDir, a) * keepSign;
            float sb = SplitSide(linePoint, lineDir, b) * keepSign;

            if (sa >= 0f)
                result.Add(a);
            if ((sa > 0f && sb < 0f) || (sa < 0f && sb > 0f))
            {
                Vector2 p = a.Lerp(b, sa / (sa - sb));
                if (result.Count == 0 || result[result.Count - 1].DistanceSquaredTo(p) > 0.0001f)
                    result.Add(p);
            }
        }

        for (int i = result.Count - 1; i > 0; i--)
            if (result[i].DistanceSquaredTo(result[i - 1]) <= 0.0001f)
                result.RemoveAt(i);
        if (result.Count > 1 && result[0].DistanceSquaredTo(result[result.Count - 1]) <= 0.0001f)
            result.RemoveAt(result.Count - 1);
        return result.ToArray();
    }

    private static Vector2 LineIntersect(Vector2 pointA, Vector2 dirA, Vector2 pointB, Vector2 dirB)
    {
        float denom = dirA.X * dirB.Y - dirA.Y * dirB.X;
        if (Mathf.IsZeroApprox(denom))
            return pointA;
        float t = ((pointB.X - pointA.X) * dirB.Y - (pointB.Y - pointA.Y) * dirB.X) / denom;
        return pointA + dirA * t;
    }

    private Vector2 SplitEnd(Vector2 from, Vector2 to, Vector2 c, Vector2 splitApex, Vector2 splitDir)
    {
        Vector2 edgeDir = (to - from).Normalized();
        Vector2 inward = InwardNormal(edgeDir, c, (from + to) / 2f);
        return LineIntersect(splitApex, splitDir, from + inward * BarW, edgeDir);
    }

    private void DrawDivider(Vector2 corner, Vector2 edgeFrom, Vector2 c)
    {
        Vector2 splitDir = (c - corner).Normalized();
        Vector2 dividerEnd = SplitEnd(edgeFrom, corner, c, corner, splitDir);
        float cap = Mathf.Min(DividerW * 0.5f, corner.DistanceTo(dividerEnd) * 0.5f);
        Vector2 dividerFrom = corner + splitDir * cap;
        Vector2 dividerTo = dividerEnd - splitDir * cap;
        DrawLine(dividerFrom, dividerTo, BorderColor, DividerW, true);
        DrawCircle(dividerFrom, cap, BorderColor, true);
        DrawCircle(dividerTo, cap, BorderColor, true);
    }

    private void DrawStatLabel(Vector2 from, Vector2 to, Vector2 c, string label, float value, float max)
    {
        Vector2 dir = to - from;
        float length = dir.Length();
        if (length <= 0f)
            return;

        Vector2 mid = (from + to) / 2f;
        Vector2 anchor = mid + InwardNormal(dir.Normalized(), c, mid) * (BarW * 0.5f);
        float rotation = Mathf.Atan2(dir.Y, dir.X);

        string text = $"{label} {Mathf.RoundToInt(value)}/{Mathf.RoundToInt(max)}";
        Font font = ThemeDB.FallbackFont;
        int fontSize = Mathf.RoundToInt(StatsFontSize * Scl);
        float maxWidth = length * 0.9f;
        while (fontSize > Mathf.RoundToInt(6f * Scl)
            && font.GetStringSize(text, HorizontalAlignment.Left, -1, fontSize).X > maxWidth)
            fontSize--;

        Vector2 pos = new Vector2(-maxWidth * 0.5f, fontSize * 0.35f);
        DrawSetTransform(anchor, rotation, Vector2.One);
        DrawString(font, pos + Vector2.One * Scl, text, HorizontalAlignment.Center, maxWidth, fontSize,
            new Color(0f, 0f, 0f, 0.8f));
        DrawString(font, pos, text, HorizontalAlignment.Center, maxWidth, fontSize, StatsColor);
        DrawSetTransform(Vector2.Zero, 0f, Vector2.One);
    }

	private void DrawGlyphGraphic(Vector2 c, float apothem)
	{
		float inner = Mathf.Max(apothem - BarW, Scl);
		float size = GlyphSize > 0f ? GlyphSize * Scl : inner * 2.35f;

		if (_glyphIcon != null)
		{
			Vector2 textureSize = _glyphIcon.GetSize();
			float scale = size / Mathf.Max(textureSize.X, textureSize.Y);
			Vector2 drawSize = textureSize * scale;

			DrawTextureRect(
				_glyphIcon,
				new Rect2(c - drawSize / 2f, drawSize),
				false,
				Colors.White
			);
			return;
		}

		if (string.IsNullOrEmpty(_glyphName))
			return;

		Font font = ThemeDB.FallbackFont;
		int fontSize = Mathf.RoundToInt(GlyphNameSize * Scl);
		float maxWidth = inner * 2f;
		while (fontSize > Mathf.RoundToInt(8f * Scl)
			&& font.GetStringSize(_glyphName, HorizontalAlignment.Left, -1, fontSize).X > maxWidth)
			fontSize--;

		DrawString(font, new Vector2(c.X - maxWidth / 2f, c.Y + fontSize * 0.35f), _glyphName,
			HorizontalAlignment.Center, maxWidth, fontSize, GlyphNameColor);
	}
}
