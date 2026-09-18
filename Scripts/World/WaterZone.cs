using System.Collections.Generic;
using Godot;

public partial class WaterZone : Area3D
{
	[Export] public float WaterSurfaceY = 55f;

	private readonly HashSet<PlayerController> _inside = new();

	public override void _PhysicsProcess(double delta)
	{
		HashSet<PlayerController> stillInside = new();

		foreach (Node3D body in GetOverlappingBodies())
		{
			if (body is PlayerController player)
			{
				player.EnterWater(WaterSurfaceY);
				stillInside.Add(player);
			}
		}

		foreach (PlayerController player in _inside)
		{
			if (!stillInside.Contains(player))
				player.ExitWater();
		}

		_inside.Clear();
		foreach (PlayerController player in stillInside)
			_inside.Add(player);
	}
}
