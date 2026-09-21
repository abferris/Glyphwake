using Godot;

public partial class SurfaceSwimPose : SkeletonModifier3D
{
    private PlayerController _player;
    private Skeleton3D _skeleton;
    private int _headBone = -1;
    private Basis _restRotation = Basis.Identity;

    public override void _Ready()
    {
        _skeleton = GetParent() as Skeleton3D;
        Node n = GetParent();
        while (n != null && n is not PlayerController)
            n = n.GetParent();
        _player = n as PlayerController;

        if (_skeleton != null)
        {
            _headBone = _skeleton.FindBone("Head");
            if (_headBone >= 0)
                _restRotation = _skeleton.GetBoneGlobalPose(_headBone).Basis;
        }
    }

    public override void _ProcessModificationWithDelta(double delta)
    {
        if (_player == null || _skeleton == null || _headBone < 0)
            return;
        if (!_player.IsSwimming || _player.IsUnderwater || _player.IsWading)
            return;

        float lean = _player.LeanPitchRad;
        if (Mathf.Abs(lean) < 0.01f)
            return;

        Transform3D g = _skeleton.GetBoneGlobalPose(_headBone);
        Basis counter = new Basis(new Vector3(1f, 0f, 0f), -lean);
        _skeleton.SetBoneGlobalPose(_headBone, new Transform3D(counter * _restRotation, g.Origin));
    }
}