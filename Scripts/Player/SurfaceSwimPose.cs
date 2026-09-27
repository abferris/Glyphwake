using Godot;

public partial class SurfaceSwimPose : SkeletonModifier3D
{
    [Export] public float ArmSubmersion = 0.08f;

    private static readonly string[] Sides = { "Left", "Right" };

    private PlayerController _player;
    private Skeleton3D _skeleton;
    private int _headBone = -1;
    private readonly int[] _shoulders = { -1, -1 };
    private readonly int[] _hands = { -1, -1 };

    public override void _Ready()
    {
        _skeleton = GetParent() as Skeleton3D;
        Node n = GetParent();
        while (n != null && n is not PlayerController)
            n = n.GetParent();
        _player = n as PlayerController;

        if (_skeleton == null)
            return;

        _headBone = _skeleton.FindBone("Head");
        for (int i = 0; i < Sides.Length; i++)
        {
            _shoulders[i] = _skeleton.FindBone(Sides[i] + "Shoulder");
            _hands[i] = _skeleton.FindBone(Sides[i] + "Hand");
        }
        ProcessPriority = 100;
    }

    private bool _surfaceActive()
    {
        return _player != null && _skeleton != null
            && _player.IsSwimming && !_player.IsUnderwater && !_player.IsWading;
    }

    // The arm clamp is applied here, after the AnimationPlayer has written the clip poses
    // for this frame. A SetBoneGlobalPose issued from inside the SkeletonModifier3D pass is
    // discarded for non-leaf bones like the shoulder, because the skeleton re-derives them
    // from the animation. Late process priority guarantees we run after the player.
    public override void _Process(double delta)
    {
        if (!_surfaceActive())
            return;
        _submerge_arms();
    }

    public override void _ProcessModificationWithDelta(double delta)
    {
        if (!_surfaceActive() || _headBone < 0)
            return;
        _level_head();
    }

    private void _level_head()
    {
        Transform3D pose = _skeleton.GetBoneGlobalPose(_headBone);
        Basis facingFlip = new Basis(new Vector3(0f, 1f, 0f), Mathf.Pi);
        Basis levelWorld = _player.GlobalTransform.Basis * facingFlip * pose.Basis;
        Basis skeletonBasis = _skeleton.GlobalTransform.Basis;
        Basis leveled = skeletonBasis.Inverse() * levelWorld;
        _skeleton.SetBoneGlobalPose(_headBone, new Transform3D(leveled, pose.Origin));
    }

    // Holds both hands just below the waterline without altering the authored arm cycle.
    // Only the shoulder is rotated, so the elbow and wrist articulation and the arm
    // motion from the clip are preserved; a hand already submerged is left untouched.
    private void _submerge_arms()
    {
        Transform3D skelGlobal = _skeleton.GlobalTransform;
        Quaternion toSkel = skelGlobal.Basis.Orthonormalized().GetRotationQuaternion();
        Quaternion toWorld = toSkel.Inverse();
        float targetY = _player.WaterSurfaceY - ArmSubmersion;

        for (int i = 0; i < _hands.Length; i++)
        {
            if (_shoulders[i] < 0 || _hands[i] < 0)
                continue;

            Vector3 handW = skelGlobal * _skeleton.GetBoneGlobalPose(_hands[i]).Origin;
            if (handW.Y <= targetY)
                continue;

            Transform3D shPose = _skeleton.GetBoneGlobalPose(_shoulders[i]);
            Vector3 shW = skelGlobal * shPose.Origin;
            Vector3 vNow = handW - shW;
            float len = vNow.Length();
            Vector3 flat = new Vector3(vNow.X, 0f, vNow.Z);
            float hr = flat.Length();
            if (len < 1e-4f || hr < 1e-4f)
                continue;

            float desired = Mathf.Clamp(targetY - shW.Y, -len, len);
            float newHr = Mathf.Sqrt(Mathf.Max(0f, len * len - desired * desired));
            Vector3 vTgt = flat / hr * newHr + Vector3.Up * desired;

            Quaternion q = _rotation_between(vNow / len, vTgt.Normalized());
            Quaternion shoulder = shPose.Basis.Orthonormalized().GetRotationQuaternion();
            Quaternion corrected = toWorld * q * toSkel * shoulder;
            _skeleton.SetBoneGlobalPose(_shoulders[i], new Transform3D(new Basis(corrected), shPose.Origin));
        }
    }

    private static Quaternion _rotation_between(Vector3 a, Vector3 b)
    {
        Vector3 axis = a.Cross(b);
        float s = axis.Length();
        float c = a.Dot(b);
        if (s < 1e-6f)
            return c >= 0f ? Quaternion.Identity : new Quaternion(Vector3.Up, Mathf.Pi);
        return new Quaternion(axis / s, Mathf.Atan2(s, c));
    }
}
