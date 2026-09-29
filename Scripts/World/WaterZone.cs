using System.Collections.Generic;
using Godot;
using Glyphwake.Core;
using Glyphwake.Player;

namespace Glyphwake.World;

/// A body of water: an authored surface height plus the volume that contains it.
///
/// Overlap is resolved by diffing the current set against the previous one rather than by
/// rebuilding both sets every physics step, so entering and leaving cost one allocation on the
/// frame they happen and nothing on the frames they do not.
public partial class WaterZone : Area3D
{
    [Export] public float WaterSurfaceY = 55f;

    private readonly HashSet<PlayerController> _inside = new();

    public override void _PhysicsProcess(double delta)
    {
        Godot.Collections.Array<Node3D> overlapping = GetOverlappingBodies();
        HashSet<PlayerController> stillInside = new();

        foreach (Node3D body in overlapping)
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
