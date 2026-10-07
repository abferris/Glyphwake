using System.Collections.Generic;
using Godot;
using Glyphwake.Core;

namespace Glyphwake.Glyphs;

/// The Terra Strike's payload: the earthen fist that forms around the caster's right hand and
/// punches with the cast. The visuals are a placeholder -- a brown sphere about the size of the
/// model's head, per the spec -- until the real asset is found; what gets replaced then is the
/// mesh and its material below, not the wiring.
///
/// The cast handshake (<see cref="IGlyphPayload.Cast"/>) carries the three the fist needs: the
/// caster, whose right hand it rides and whose facing the punch travels in; the damage the cast
/// paid for; and how long the cast takes, which is the punch clip's own length so the fist's
/// clock and the animation cannot drift. Everything else is this script's: the form through the
/// windup, the hit window, and the leave when the cast ends.
///
/// The fist rides the right hand rather than posing anything itself: a BoneAttachment3D on the
/// hand bone (found off the caster's skeleton by the model contract's bone name) is what the
/// punch clip's arm extension drags through the air, and this node parks itself on its transform
/// every tick. No node is reparented, so the caster's tree is never rewritten mid-frame.
public partial class TerraFistPayload : Node3D, IGlyphPayload
{
    // The hit window, as fractions of the cast duration: the fist grows in through the windup,
    // is out in front through the window, and is gone by the end. Hits resolve in the window
    // only, once per body per cast. First-pass placeholders; the window rides the cast's length.
    [Export(PropertyHint.Range, "0,1,0.01")] public float StrikeWindowStart = 0.4f;
    [Export(PropertyHint.Range, "0,1,0.01")] public float StrikeWindowEnd = 0.75f;

    // The placeholder fist's size: about the head of the model, per the spec.
    [Export(PropertyHint.Range, "0.02,0.5,0.01")] public float FistRadius = 0.1f;

    // Which bodies the strike can hurt. No enemy layer exists yet, so the default hits nothing
    // -- the test dummies ride the player layer and set this at runtime; when the enemy layer
    // lands it goes here. Read live rather than copied at _Ready, so a runtime retune takes
    // effect within the same cast. The caster's own body is excluded in code regardless.
    [Export(PropertyHint.Layers3DPhysics)] public uint TargetMask = 0u;

    private Node3D _caster;
    private Rid _casterRid;
    private float _damage;
    private float _duration;
    private float _elapsed;
    private readonly HashSet<Node> _hit = new();

    private BoneAttachment3D _hand;
    private MeshInstance3D _mesh;
    private Area3D _area;

    public void Cast(Node caster, float damage, float duration)
    {
        _caster = caster as Node3D;
        _casterRid = (caster as CollisionObject3D)?.GetRid() ?? default;
        _damage = damage;
        _duration = duration > 0.01f ? duration : 0.25f;
    }

    public override void _Ready()
    {
        AttachToCasterHand();
        BuildFist();
    }

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;
        _elapsed += dt;
        float t = _elapsed / _duration;

        if (_hand != null)
            GlobalTransform = _hand.GlobalTransform;

        UpdateFist(t);

        if (t >= StrikeWindowStart && t <= StrikeWindowEnd)
            ResolveHits();

        if (t >= 1f)
            EndCast();
    }

    /// Parks a BoneAttachment3D on the caster's right hand. The skeleton is walked for rather
    /// than resolved by path -- the same depth-first search the cast animations use to find their
    /// player -- and the bone by the model contract's name, so a renamed bone is one failure in
    /// one place. A caster with no skeleton or no hand leaves the fist where it spawned, at the
    /// caster, which is still a reasonable place for a punch shape to resolve from.
    private void AttachToCasterHand()
    {
        Skeleton3D skeleton = FindSkeleton(_caster);
        if (skeleton == null)
            return;

        if (skeleton.FindBone(PlayerRig.RightHandBoneName) < 0)
            return;

        _hand = new BoneAttachment3D { Name = "TerraFistHand" };
        skeleton.AddChild(_hand);
        _hand.BoneName = PlayerRig.RightHandBoneName;
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

    /// Builds the placeholder fist: the brown sphere and the hit area it carries, both children
    /// of this node so they ride the hand with it. The mesh and its material are what the real
    /// earthen asset replaces; the area is the strike's shape and stays.
    private void BuildFist()
    {
        SphereMesh sphere = new SphereMesh { Radius = FistRadius, Height = FistRadius * 2f };
        var material = new StandardMaterial3D { AlbedoColor = new Color(0.45f, 0.28f, 0.12f) };
        sphere.Material = material;

        _mesh = new MeshInstance3D { Name = "Fist", Mesh = sphere };
        AddChild(_mesh);

        _area = new Area3D
        {
            Name = "StrikeArea",
            CollisionLayer = 0,
            CollisionMask = TargetMask,
            Monitoring = true,
            Monitorable = false,
        };
        _area.AddChild(new CollisionShape3D { Shape = new SphereShape3D { Radius = FistRadius } });
        AddChild(_area);

        _mesh.Visible = false;
    }

    /// The fist's size at a moment of the cast, as a fraction of its radius: 0 at the fire,
    /// grown in by the strike window, gone by the end. Hidden entirely outside the cast.
    private void UpdateFist(float t)
    {
        if (_mesh == null)
            return;

        float scale;
        if (t < StrikeWindowStart)
            scale = Mathf.Clamp(t / StrikeWindowStart, 0f, 1f);
        else if (t <= StrikeWindowEnd)
            scale = 1f;
        else
            scale = Mathf.Clamp((1f - t) / Mathf.Max(0.01f, 1f - StrikeWindowEnd), 0f, 1f);

        _mesh.Visible = scale > 0.001f;
        _mesh.Scale = Vector3.One * scale;
    }

    /// Reports the strike's overlaps to the damageables they name. The caster's own body is
    /// excluded here rather than by the area's mask alone, so a mask that includes the caster's
    /// own layer cannot make the caster punch itself; a body already hit by this cast is
    /// skipped, so standing inside the window is one hit, not a per-frame drain.
    private void ResolveHits()
    {
        if (_area == null || _caster == null || _damage <= 0f)
            return;

        _area.CollisionMask = TargetMask;
        Vector3 direction = -_caster.GlobalTransform.Basis.Z;
        foreach (Node3D body in _area.GetOverlappingBodies())
        {
            if (body is not CollisionObject3D collider || collider.GetRid() == _casterRid)
                continue;
            if (!_hit.Add(body))
                continue;

            if (body is Combat.IDamageable damageable)
                damageable.ApplyDamage(_damage, direction);
            else if (body.HasMethod("apply_damage"))
                body.Call("apply_damage", _damage, direction);
        }
    }

    /// The cast is over: the fist dissipates. The payload's life is the cast's, so it frees
    /// itself rather than waiting to be cleaned up.
    private void EndCast()
    {
        SetPhysicsProcess(false);
        QueueFree();
    }
}
