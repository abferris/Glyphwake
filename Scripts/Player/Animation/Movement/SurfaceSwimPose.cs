using Godot;
using Glyphwake.Core;

namespace Glyphwake.Player;

/// Holds the surface-swim pose: the head level, and both hands just under the waterline while
/// treading.
///
/// The arm clamp is applied in _Process rather than in the modifier pass, because a
/// SetBoneGlobalPose issued from inside the SkeletonModifier3D pass is discarded for non-leaf
/// bones like the shoulder -- the skeleton re-derives those from the animation. Late process
/// priority is what guarantees this runs after the AnimationPlayer has written the frame.
public partial class SurfaceSwimPose : SkeletonModifier3D
{
    [Export] public float ArmSubmersion = 0.08f;
    // Floor on how far below horizontal the arm hangs. Solving for the hand height alone lets the
    // arm come out level: the required drop is only a couple of centimetres at the treading
    // waterline, so the horizontal component stays at nearly the full arm length and the upper arm
    // ends up parallel with the surface. The "Swim Tread" clip already carries a 45 degree upper
    // arm, so this only has to catch hands that breach the waterline; keep it under the clip's
    // angle or the clamp fights the authored pose. Tilting further down never lifts a hand, so the
    // "hands stay submerged" guarantee is unaffected.
    [Export] public float ArmDropDeg = 35f;

    private PlayerController _player;
    private PlayerRig _rig;
    private Skeleton3D _skeleton;
    private int[] _shoulders;
    private int[] _hands;

    /// Resolved on first use rather than in _Ready: Godot readies children before parents, so
    /// the PlayerController that owns the rig has not built it yet when this runs.
    private PlayerRig Rig
    {
        get
        {
            if (_rig == null && _player != null)
                _rig = _player.Rig;
            return _rig;
        }
    }

    public override void _Ready()
    {
        _skeleton = GetParent() as Skeleton3D;
        Node n = GetParent();
        while (n != null && n is not PlayerController)
            n = n.GetParent();
        _player = n as PlayerController;

        if (_skeleton == null)
            return;

        _shoulders = new[]
        {
            _skeleton.FindBone(PlayerRig.LeftShoulderBoneName),
            _skeleton.FindBone(PlayerRig.RightShoulderBoneName),
        };
        _hands = new[]
        {
            _skeleton.FindBone(PlayerRig.LeftHandBoneName),
            _skeleton.FindBone(PlayerRig.RightHandBoneName),
        };
        ProcessPriority = 100;
    }

    private bool SurfaceActive()
	{
		// IsSurfaceSwimming, not IsAtOrAboveSurface. The water zone reaches 25 m above the
		// waterline, so "at or above the surface" also covers the whole of a plunge through
		// open air -- and SubmergeArms pulls the hands down to a world height just under the
		// waterline, which is nonsense applied to a body still falling towards it from a
		// height. The modifier waits until the water is actually holding the body up.
		return _player != null && Rig != null && _player.State.IsSurfaceSwimming;
	}

    public override void _Process(double delta)
    {
        if (!SurfaceActive() || _skeleton == null || _hands == null)
            return;
        SubmergeArms();
    }

    public override void _ProcessModificationWithDelta(double delta)
    {
        PlayerRig rig = Rig;
        if (!SurfaceActive() || _skeleton == null || rig == null || !rig.HasHeadBone)
            return;
        LevelHead(rig.HeadBone);
    }

    private void LevelHead(int headBone)
    {
        Transform3D pose = _skeleton.GetBoneGlobalPose(headBone);
        Basis facingFlip = new Basis(new Vector3(0f, 1f, 0f), Mathf.Pi);
        Basis levelWorld = _player.GlobalTransform.Basis * facingFlip * pose.Basis;
        Basis skeletonBasis = _skeleton.GlobalTransform.Basis;
        Basis leveled = skeletonBasis.Inverse() * levelWorld;
        _skeleton.SetBoneGlobalPose(headBone, new Transform3D(leveled, pose.Origin));
    }

    // Holds both hands just below the waterline without altering the authored arm cycle.
    // Only the shoulder is rotated, so the elbow and wrist articulation and the arm
    // motion from the clip are preserved; a hand already submerged is left untouched.
    private void SubmergeArms()
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

            // Hold the arm at least ArmDropDeg below horizontal, keeping the azimuth it already
            // has. Only ever increases the downward component, so a hand can never be lifted back
            // towards the surface by the clamp.
            float drop = Mathf.Max(-vTgt.Y / len, Mathf.Sin(Mathf.DegToRad(ArmDropDeg)));
            float hTgt = Mathf.Sqrt(Mathf.Max(0f, len * len - drop * drop * len * len));
            vTgt = flat / hr * hTgt - Vector3.Up * (drop * len);

            Quaternion q = RotationBetween(vNow / len, vTgt.Normalized());
            Quaternion shoulder = shPose.Basis.Orthonormalized().GetRotationQuaternion();
            Quaternion corrected = toWorld * q * toSkel * shoulder;
            _skeleton.SetBoneGlobalPose(_shoulders[i], new Transform3D(new Basis(corrected), shPose.Origin));
        }
    }

    private static Quaternion RotationBetween(Vector3 a, Vector3 b)
    {
        Vector3 axis = a.Cross(b);
        float s = axis.Length();
        float c = a.Dot(b);
        if (s < 1e-6f)
            return c >= 0f ? Quaternion.Identity : new Quaternion(Vector3.Up, Mathf.Pi);
        return new Quaternion(axis / s, Mathf.Atan2(s, c));
    }
}
