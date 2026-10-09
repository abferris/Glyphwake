using System.Collections.Generic;
using Godot;
using Glyphwake.Core;
using Glyphwake.Player;

namespace Glyphwake.Glyphs;

/// The Terra Strike's payload: the strike that rides the caster's hand and resolves with the
/// cast. It has no visual for now -- the earthen fist asset is still being found -- so what
/// travels is the invisible strike shape, sized like the head of the model. When the real asset
/// lands the mesh goes in here; the wiring below is what it hangs off.
///
/// The cast handshake (<see cref="IGlyphPayload.Cast"/>) carries the three the strike needs: the
/// caster, whose hand it rides and whose facing the punch travels in; the damage the cast paid
/// for; and how long the cast takes, which is the cast clip's own length so this node's clock
/// and the animation cannot drift. Everything else is this script's: the hit window and the
/// leave when the cast ends.
///
/// The strike rides the hand rather than posing anything itself: a BoneAttachment3D on the hand
/// bone (found off the caster's skeleton by the model contract's bone name) is what the cast
/// clip's arm extension drags through the air, and this node parks itself on its transform every
/// tick. No node is reparented, so the caster's tree is never rewritten mid-frame.
public partial class TerraFistPayload : Node3D, IGlyphPayload
{
    // The hit window, as fractions of the cast duration: hits resolve in the window only, once
    // per body per cast -- the extended part of the swing, not the windup or the recovery.
    // First-pass placeholders; the window rides the cast's length.
    [Export(PropertyHint.Range, "0,1,0.01")] public float StrikeWindowStart = 0.4f;
    [Export(PropertyHint.Range, "0,1,0.01")] public float StrikeWindowEnd = 0.75f;

    // The strike shape's size: about the head of the model, per the spec. It has no mesh yet,
    // so this is the radius of the invisible sphere the hits resolve against.
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
    private Area3D _area;

    public void Cast(Node caster, float damage, float duration)
    {
        _caster = caster as Node3D;
        _casterRid = (caster as CollisionObject3D)?.GetRid() ?? default;
        _damage = damage;
        _duration = duration > 0.01f ? duration : 0.5f;
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

        if (t >= StrikeWindowStart && t <= StrikeWindowEnd)
            ResolveHits();

        if (t >= 1f)
            EndCast();
    }

    /// Parks a BoneAttachment3D on the caster's punching hand. The punching arm was chosen at
    /// cast time -- the rear arm, whichever side that was -- and the controller hands the choice
    /// down; the fallback is the right hand, the direction the clip is authored for. The skeleton
    /// is walked for rather than resolved by path -- the same depth-first search the cast
    /// animations use to find their player -- and the bone by the model contract's name, so a
    /// renamed bone is one failure in one place. A caster with no skeleton or no hand leaves the
    /// strike where it spawned, at the caster, which is still a reasonable place for a punch
    /// shape to resolve from.
    private void AttachToCasterHand()
    {
        Skeleton3D skeleton = FindSkeleton(_caster);
        if (skeleton == null)
            return;

        bool punchesLeft = (_caster as PlayerController)?.ActiveCastLeftArm == true;
        string handBone = punchesLeft ? PlayerRig.LeftHandBoneName : PlayerRig.RightHandBoneName;
        if (skeleton.FindBone(handBone) < 0)
            return;

        _hand = new BoneAttachment3D { Name = "TerraFistHand" };
        skeleton.AddChild(_hand);
        _hand.BoneName = handBone;
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

    /// Builds the strike's shape: the invisible sphere the hits resolve against, a child of this
    /// node so it rides the hand with it. No mesh or material yet -- the real earthen asset goes
    /// in beside this; the area is the strike's shape and stays.
    private void BuildFist()
    {
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

    /// The cast is over: the strike ends. The payload's life is the cast's, so it frees
    /// itself rather than waiting to be cleaned up.
    private void EndCast()
    {
        SetPhysicsProcess(false);
        QueueFree();
    }
}
