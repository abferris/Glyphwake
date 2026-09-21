using Godot;

public partial class DebugChaseCamera : Camera3D
{
    [Export] public float Distance = 3.2f;
    [Export] public float Height = 1.2f;
    [Export] public float PitchFactor = 0.5f;

    private Node3D _body;
    private CameraController _fps;

    public override void _Ready()
    {
        TopLevel = true;
        Node node = GetParent();
        while (node != null && node is not CharacterBody3D)
            node = node.GetParent();
        _body = node as Node3D;
        if (_body != null)
            _fps = _body.GetNodeOrNull<CameraController>("Head/Camera3D");
        Current = true;
    }

    public override void _Process(double delta)
    {
        if (_body == null || _fps == null || !Current)
            return;

        float yaw = _body.Rotation.Y;
        float elev = Mathf.DegToRad(Mathf.RadToDeg(-_fps.LookPitch) * PitchFactor);
        Vector3 behind = new Vector3(Mathf.Sin(yaw), 0f, Mathf.Cos(yaw));
        Vector3 target = _body.GlobalPosition + Vector3.Up * 1.0f;
        GlobalPosition = target + behind * (Distance * Mathf.Cos(elev)) + Vector3.Up * (Height + Distance * Mathf.Sin(elev));
        LookAt(target + Vector3.Up * 0.3f, Vector3.Up);
    }
}