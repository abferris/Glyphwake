using System.Collections.Generic;
using Godot;
using Glyphwake.Core;
using Glyphwake.Player;

namespace Glyphwake.Glyphs;

/// The Cinder Shot's payload: the fire bolt the cast gathers and pushes. A red sphere
/// placeholder -- the real fire asset lands as a mesh swap here, the wiring below is what it
/// hangs off.
///
/// The cast handshake (<see cref="IGlyphPayload.Cast"/>) carries the caster, whose rig's head
/// camera is where the aim reticule sits, and the damage the cast paid for. The duration is the
/// cast animation clip's own length, and the shot's clock rides it: the cast's beats are the
/// gather and the push (<see cref="ReleaseAt"/> is the fraction where the push completes).
///
/// Until the push the shot sits between both hands: it spawns on their midpoint and parks on
/// it every tick, so the cast clip's own hand motion carries it to the chest as the hands
/// gather. At the push it is shoved forwards: the aim is read at the push, off the camera's
/// centre ray -- the reticule is drawn at screen centre, so that ray is what it points at --
/// landing on whatever is under it, or on a point MaxAimRange out when it touches nothing.
/// Gravity pulls the arc down from there. The shot is the caster's child (that is where the
/// caster adds it) but keeps its own world-space position and writes it absolutely every tick,
/// so the caster's movement never drags a shot already in flight.
///
/// Contact is resolved by the shot's own area: a skillshot that forgets to opt in hits terrain
/// and not players (CollisionLayers' rule), so the default mask is the World layer and the
/// enemy layers are opt-in -- the test dummies ride the player layer and retune the mask the
/// way a menu will, live, in flight. The first tick with anything under the mask is the shot's
/// whole resolution: every damageable under it takes the damage once, and the shot frees
/// itself -- terrain contact included, so an arc that misses dies in the ground, and a shot
/// that flies past the world dies at <see cref="Lifetime"/>.
public partial class CinderShotPayload : Node3D, IGlyphPayload
{
    // How fast the shot is pushed out, in m/s. First-pass placeholder until the numbers are
    // decided.
    [Export] public float LaunchSpeed = 20f;

    // The arc's pull, in m/s^2, negative down -- the body's own convention and value, so a shot
    // falls with the same gravity the caster jumps with until a retune says otherwise.
    [Export] public float Gravity = -9.81f;

    // The shot's size, for both the placeholder sphere and the contact shape: one radius, so
    // what you see is what hits.
    [Export(PropertyHint.Range, "0.02,0.5,0.01")] public float Radius = 0.1f;

    // How long a shot that touches nothing stays in flight before it frees itself.
    [Export] public float Lifetime = 6f;

    // How far out the aim reads when the centre ray touches nothing: the shot flies toward the
    // horizon point rather than nowhere.
    [Export] public float MaxAimRange = 50f;

    // Where in the cast the push completes, as a fraction of its duration: the cast clip's
    // beats are the gather (0-0.3) and the push (0.3-0.55), so the shot leaves as the arms
    // reach extension.
    [Export(PropertyHint.Range, "0,1,0.01")] public float ReleaseAt = 0.55f;

    // What the shot can resolve against. The default is the World layer -- terrain and props,
    // which is what an arc that misses reaches -- and the enemy layers are opt-in, retuned the
    // way a menu will. Read live rather than copied at _Ready, so a runtime retune takes
    // effect on a shot already in flight.
    [Export(PropertyHint.Layers3DPhysics)] public uint TargetMask = CollisionLayers.World;

    private Node3D _caster;
    private Rid _casterRid;
    private float _damage;
    private float _duration = 0.5f;
    private Vector3 _spawnAt;
    private Vector3 _position;
    private Vector3 _velocity;
    private float _elapsed;
    private bool _riding = true;
    private readonly HashSet<Node> _hit = new();

    private Area3D _area;

    public void Cast(Node caster, float damage, float duration)
    {
        _caster = caster as Node3D;
        _casterRid = (caster as CollisionObject3D)?.GetRid() ?? default;
        _damage = damage;
        _duration = duration > 0.01f ? duration : 0.5f;
        _spawnAt = HandsMidpoint();
    }

    public override void _Ready()
    {
        _position = _spawnAt;
        GlobalPosition = _position;
        BuildShot();
    }

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;
        _elapsed += dt;

        if (_riding)
        {
            // The windup: the shot parks on the hands' midpoint every tick, so the cast clip's
            // own gather carries it to the chest. The push reads the aim at the moment the
            // arms reach extension, then the flight takes over from the same tick.
            GlobalPosition = HandsMidpoint();
            if (_elapsed < ReleaseAt * _duration)
                return;
            _riding = false;
            Vector3 direction = AimPoint(_caster) - GlobalPosition;
            _velocity = (direction.LengthSquared() > 0.0001f
                ? direction / direction.Length()
                : -_caster.GlobalTransform.Basis.Z) * LaunchSpeed;
            _position = GlobalPosition;
        }

        _velocity.Y += Gravity * dt;
        _position += _velocity * dt;
        GlobalPosition = _position;

        if (ResolveHits() || _elapsed >= Lifetime)
            EndShot();
    }

    /// The point between both hands, in world space: the hands' global poses, re-read every
    /// call, so the ride follows the cast clip's own hand motion rather than a captured
    /// snapshot. The skeleton is walked for rather than resolved by path -- the same
    /// depth-first search the other payloads use. A caster with no skeleton or hands parks the
    /// shot at chest height in front of the body, which is still a reasonable place for a
    /// gathered shot to sit.
    private Vector3 HandsMidpoint()
    {
        if (_caster == null)
            return Vector3.Zero;

        Skeleton3D skeleton = FindSkeleton(_caster);
        if (skeleton == null)
            return _caster.GlobalPosition - _caster.GlobalTransform.Basis.Z * 0.3f
                + Vector3.Up * 1.2f;

        int left = skeleton.FindBone(PlayerRig.LeftHandBoneName);
        int right = skeleton.FindBone(PlayerRig.RightHandBoneName);
        if (left < 0 || right < 0)
            return _caster.GlobalPosition - _caster.GlobalTransform.Basis.Z * 0.3f
                + Vector3.Up * 1.2f;

        Vector3 l = (skeleton.GlobalTransform * skeleton.GetBoneGlobalPose(left)).Origin;
        Vector3 r = (skeleton.GlobalTransform * skeleton.GetBoneGlobalPose(right)).Origin;
        return (l + r) * 0.5f;
    }

    private static Skeleton3D FindSkeleton(Node root)
    {
        if (root is Skeleton3D skeleton)
            return skeleton;

        foreach (Node child in root.GetChildren())
        {
            Skeleton3D found = FindSkeleton(child);
            if (found != null)
                return found;
        }

        return null;
    }

    /// Where the reticule points, read at the push: a ray from the head camera -- the rig's, so
    /// the debug view never aims a shot -- through the screen centre out to MaxAimRange. The
    /// ray reads the world and the bodies the shot can name, excluding the caster's own body;
    /// the fallback is the ray's far end, so aiming at the sky throws toward the horizon.
    private Vector3 AimPoint(Node caster)
    {
        Camera3D camera = (caster as PlayerController)?.Rig?.Camera;
        Vector3 from = camera != null
            ? camera.GlobalPosition
            : _caster != null ? _caster.GlobalPosition : Vector3.Zero;
        Vector3 forward = camera != null
            ? -camera.GlobalTransform.Basis.Z
            : _caster != null ? -_caster.GlobalTransform.Basis.Z : Vector3.Back;
        Vector3 far = from + forward * MaxAimRange;

        PhysicsDirectSpaceState3D space = camera != null
            ? camera.GetWorld3D().DirectSpaceState
            : _caster != null ? _caster.GetWorld3D().DirectSpaceState : null;
        if (space == null)
            return far;

        PhysicsRayQueryParameters3D query = PhysicsRayQueryParameters3D.Create(from, far);
        query.CollisionMask = CollisionLayers.World | CollisionLayers.PlayerBody;
        if (caster is CollisionObject3D self)
            query.Exclude = new Godot.Collections.Array<Rid> { self.GetRid() };
        Godot.Collections.Dictionary hit = space.IntersectRay(query);
        return hit.Count > 0 && hit.ContainsKey("position") ? (Vector3)hit["position"] : far;
    }

    /// Builds the shot: the contact area on the Projectile layer -- the layer reserved for
    /// skillshots in flight, and this is the first thing on it -- and the red sphere placeholder
    /// beside it. One radius sizes both, so what you see is what hits; the mesh and its material
    /// are what the real fire asset replaces.
    private void BuildShot()
    {
        _area = new Area3D
        {
            Name = "ShotArea",
            CollisionLayer = CollisionLayers.Projectile,
            CollisionMask = TargetMask,
            Monitoring = true,
            Monitorable = false,
        };
        _area.AddChild(new CollisionShape3D { Shape = new SphereShape3D { Radius = Radius } });
        AddChild(_area);

        var mesh = new MeshInstance3D
        {
            Name = "Cinder",
            Mesh = new SphereMesh { Radius = Radius, Height = Radius * 2f },
        };
        mesh.MaterialOverride = new StandardMaterial3D
        {
            AlbedoColor = new Color(0.9f, 0.2f, 0.05f),
            EmissionEnabled = true,
            Emission = new Color(0.85f, 0.15f, 0.02f),
            EmissionEnergyMultiplier = 1.5f,
        };
        AddChild(mesh);
    }

    /// Reports the shot's overlaps to the damageables they name. The caster's own body is
    /// excluded here rather than by the area's mask alone, so a mask that includes the caster's
    /// own layer cannot make the caster shoot itself; a body already hit by this shot is
    /// skipped, so a frame that straddles two shapes is one hit, not a per-frame drain. Returns
    /// whether anything at all was under the mask -- the terrain counts -- which is the shot's
    /// cue to resolve and die.
    private bool ResolveHits()
    {
        if (_area == null)
            return false;
        _area.CollisionMask = TargetMask;

        Vector3 direction = _velocity.LengthSquared() > 0.0001f
            ? _velocity.Normalized()
            : -GlobalTransform.Basis.Z;
        bool contact = false;
        foreach (Node3D body in _area.GetOverlappingBodies())
        {
            if (body is not CollisionObject3D collider || collider.GetRid() == _casterRid)
                continue;
            contact = true;
            if (_damage <= 0f || !_hit.Add(body))
                continue;

            if (body is Combat.IDamageable damageable)
                damageable.ApplyDamage(_damage, direction);
            else if (body.HasMethod("apply_damage"))
                body.Call("apply_damage", _damage, direction);
        }
        return contact;
    }

    /// The shot is done: it hit the world, or it flew out of its life. It frees itself rather
    /// than waiting to be cleaned up.
    private void EndShot()
    {
        SetPhysicsProcess(false);
        QueueFree();
    }
}
