using Godot;

namespace Glyphwake.Core;

/// Resolves the player's node tree and skeleton once, and hands the results to everything that
/// needs them.
///
/// Everything walks the same node tree looking for the same handful of nodes by string literal
/// -- "Head", "Visual/Anim", "Visual/Skeleton3D", and the bone named "Head" -- so the paths and
/// bone names live here once, with one set of names to change. Bone names are part of the model
/// contract rather than scene layout, but they resolve through the same place: renaming one and
/// getting it wrong should be one failure to report, not several failing quietly.
public sealed class PlayerRig
{
    /// Bone names are part of the model contract, not scene layout, but they resolve through
    /// here for the same reason as the node paths: one place to find out what is missing.
    public const string HeadBoneName = "Head";
    public const string Spine1BoneName = "Spine1";
    public const string Spine2BoneName = "Spine2";
    public const string LeftShoulderBoneName = "LeftShoulder";
    public const string RightShoulderBoneName = "RightShoulder";
    public const string LeftHandBoneName = "LeftHand";
    public const string RightHandBoneName = "RightHand";

    public const string HeadNodePath = "Head";
    public const string CameraNodePath = "Head/Camera3D";
    public const string VisualNodePath = "Visual";
    public const string SkeletonNodePath = "Visual/Skeleton3D";
    public const string AnimNodePath = "Visual/Anim";
    public const string AnimTreeNodePath = "AnimTree";
    public const string CollisionNodePath = "CollisionShape3D";

    /// Fallbacks used when the scene has no skeleton to measure, so a rig built without a
    /// visual still swims at a plausible height rather than collapsing to the origin.
    private const float DefaultRestHeight = 0.895f;
    private const float DefaultRestHeadHeight = 1.45f;
    private const float FallbackHeadHeight = 1.6f;

    /// Height of the head bone above the body origin. This is the reference the treading
    /// float holds on the waterline and the reference the eye test uses to raise the
    /// underwater state, so it is measured once and shared rather than re-derived per system.
    public float RestHeadHeight { get; }

    /// Half the collision capsule, less the collision shape's own offset, i.e. the distance
    /// from the body origin down to the feet. Water depth is measured from here.
    public float RestHeight { get; }

    /// The head's resting height in player space. The surface-swim lean pins the visual
    /// against this, clamped to a small bob either side.
    public float HeadLocalY => RestHeadHeight;

    public Node3D Body { get; }
    public Node3D Head { get; }
    public Camera3D Camera { get; }
    public Node3D Visual { get; }
    public Skeleton3D Skeleton { get; }
    public AnimationPlayer Anim { get; }
    public AnimationTree AnimTree { get; }
    public Vector3 VisualRestPosition { get; }

    public int HeadBone { get; }
    public int LeftShoulderBone { get; }
    public int RightShoulderBone { get; }
    public int LeftHandBone { get; }
    public int RightHandBone { get; }

    public bool HasSkeleton => Skeleton != null;
    public bool HasHeadBone => Skeleton != null && HeadBone >= 0;
    public bool HasVisual => Visual != null;

    /// Reads the player's node tree. The body must already be in the tree, because the
    /// measurements below are global.
    public PlayerRig(Node3D body)
    {
        Body = body;
        Head = body.GetNodeOrNull<Node3D>(HeadNodePath);
        Camera = body.GetNodeOrNull<Camera3D>(CameraNodePath);
        Visual = body.GetNodeOrNull<Node3D>(VisualNodePath);
        Skeleton = body.GetNodeOrNull<Skeleton3D>(SkeletonNodePath);
        Anim = body.GetNodeOrNull<AnimationPlayer>(AnimNodePath);
        AnimTree = body.GetNodeOrNull<AnimationTree>(AnimTreeNodePath);

        if (Visual != null)
            VisualRestPosition = Visual.Position;

        CollisionShape3D shapeNode = body.GetNodeOrNull<CollisionShape3D>(CollisionNodePath);
        CapsuleShape3D capsule = shapeNode?.Shape as CapsuleShape3D;
        RestHeight = capsule != null
            ? capsule.Height * 0.5f - shapeNode.Position.Y
            : DefaultRestHeight;

        if (Skeleton != null)
        {
            HeadBone = Skeleton.FindBone(HeadBoneName);
            LeftShoulderBone = Skeleton.FindBone(LeftShoulderBoneName);
            RightShoulderBone = Skeleton.FindBone(RightShoulderBoneName);
            LeftHandBone = Skeleton.FindBone(LeftHandBoneName);
            RightHandBone = Skeleton.FindBone(RightHandBoneName);
        }

        RestHeadHeight = MeasureHeadHeight();
    }

    /// World-space origin of the head bone, or of the head node, or a fixed offset above the
    /// body -- whichever the scene actually provides.
    public Vector3 HeadWorldPosition()
    {
        if (HasHeadBone)
            return (Skeleton.GlobalTransform * Skeleton.GetBoneGlobalPose(HeadBone)).Origin;
        if (Head != null)
            return Head.GlobalPosition;
        return Body.GlobalPosition + Vector3.Up * FallbackHeadHeight;
    }

    private float MeasureHeadHeight()
    {
        if (HasHeadBone)
        {
            float height = HeadWorldPosition().Y - Body.GlobalPosition.Y;
            // At _Ready the skeleton has not necessarily been posed yet, so a height that
            // measures as zero means "not measured", not "a character with no head".
            if (height > 0.1f)
                return height;
        }
        if (Head != null)
            return Mathf.Max(0.1f, Head.GlobalPosition.Y - Body.GlobalPosition.Y);
        return DefaultRestHeadHeight;
    }
}
