using Godot;

namespace Glyphwake.UI;

public partial class AimReticle : Control
{
	[Export] public float DotRadius = 2f;
	[Export] public float RingRadius = 9f;
	[Export] public float RingWidth = 1.5f;
	[Export] public Color DotColor = new Color(1f, 1f, 1f, 0.5f);
	[Export] public Color RingColor = new Color(1f, 1f, 1f, 0.9f);

	public override void _Draw()
	{
		Vector2 center = Size / 2f;
		DrawCircle(center, DotRadius, DotColor);
		DrawArc(center, RingRadius, 0f, Mathf.Tau, 64, RingColor, RingWidth, true);
	}
}
