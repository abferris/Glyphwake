using Godot;

public partial class CameraController : Camera3D
{
    [Export] public float MouseSensitivity = 0.15f;
    [Export] public float MinPitch = -85f;
    [Export] public float MaxPitch = 85f;
    [Export] public float MinPitchInWater = -90f;
    [Export] public float MaxPitchInWater = 90f;
    [Export] public float FieldOfView = 70f;
    [Export] public bool CaptureMouseOnStart = true;
    [Export] public float SwimCameraLift = 0.8f;
    [Export] public float SwimLiftSpeed = 6f;
    [Export] public float EyeOffset = 0.08f;
    [Export] public float FaceReach = 0.35f;

    private Node3D _body;
    private PlayerController _player;
    private Skeleton3D _skeleton;
    private int _headBone = -1;
    private float _yaw;
    private float _pitch;
    private float _currentLift;
    private bool _debugOn;
    private FileAccess _debugFile;

    public override void _Ready()
    {
        Node node = GetParent();
        while (node != null && node is not CharacterBody3D)
            node = node.GetParent();
        _body = node as Node3D;
        _player = node as PlayerController;

        Node worldNode = GetParent();
        while (worldNode != null && worldNode.Name != "World")
            worldNode = worldNode.GetParent();
        if (worldNode != null)
        {
            var environment = worldNode.GetNodeOrNull<WorldEnvironment>("WorldEnvironment");
        //     if (environment != null)
        //         _underwaterEnv = environment.Environment;
        }

        if (_body != null)
        {
            _skeleton = _body.GetNodeOrNull<Skeleton3D>("Visual/Skeleton3D");
            if (_skeleton != null)
                _headBone = _skeleton.FindBone("Head");
            _yaw = _body.Rotation.Y;
        }

        Fov = FieldOfView;
        if (CaptureMouseOnStart)
            Input.MouseMode = Input.MouseModeEnum.Captured;
    }

    public override void _Process(double delta)
    {
        float dt = (float)delta;
        if (_player != null)
            _pitch = ClampPitch(_pitch);
        bool surfaceSwim = _player != null && _player.IsSwimming && !_player.IsUnderwater && !_player.IsWading;

        float pitchDownDeg = Mathf.RadToDeg(-_pitch);
        float lookDown = Mathf.Clamp((pitchDownDeg - 10f) / 15f, 0f, 1f);
        float targetLift = surfaceSwim ? SwimCameraLift * (1f - lookDown) : 0f;

        _currentLift = surfaceSwim && targetLift < _currentLift
            ? targetLift
            : Mathf.MoveToward(_currentLift, targetLift, SwimLiftSpeed * dt);

        if (_headBone >= 0 && _body != null)
        {
            float bodyPitch = _player != null ? _player.BodyPitch : 0f;
            _body.Rotation = new Vector3(bodyPitch, _yaw, 0f);

            Transform3D bone = _skeleton.GlobalTransform * _skeleton.GetBoneGlobalPose(_headBone);
            float sp = Mathf.Sin(_pitch);
            float cp = Mathf.Cos(_pitch);
            Vector3 forward = new Vector3(0f, sp, -cp);
            GlobalPosition = bone.Origin + Vector3.Up * (EyeOffset + _currentLift) + forward * FaceReach;
        }
        else
        {
            Position = new Vector3(0f, _currentLift, -FaceReach);
        }

        Rotation = new Vector3(_pitch, 0f, 0f);

        if (_debugOn && _debugFile != null && _player != null)
        {
            float min = ClampPitch(-Mathf.Pi);
            float max = ClampPitch(Mathf.Pi);
            float headY = _headBone >= 0 && _skeleton != null
                ? (_skeleton.GlobalTransform * _skeleton.GetBoneGlobalPose(_headBone)).Origin.Y
                : float.NaN;
            _debugFile.StoreLine(string.Format(
                "t={0:0.00} swim={1} under={2} wade={3} camMin={4:0.0} camMax={5:0.0} pitch={6:0.00} bodyPitch={7:0.00} eyeY={8:0.00} headY={9:0.00}",
                Time.GetTicksMsec() / 1000f,
                _player.IsSwimming, _player.IsUnderwater, _player.IsWading,
                Mathf.RadToDeg(min), Mathf.RadToDeg(max), Mathf.RadToDeg(_pitch),
                Mathf.RadToDeg(_player.BodyPitch), GlobalPosition.Y, headY));
        }
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventKey key && key.Pressed && !key.Echo)
        {
            if (key.PhysicalKeycode == Key.F2)
            {
                _debugOn = !_debugOn;
                if (_debugFile != null)
                {
                    _debugFile.Flush();
                    _debugFile.Close();
                    _debugFile = null;
                }
                if (_debugOn)
                    _debugFile = FileAccess.Open("user://swim_debug.txt", FileAccess.ModeFlags.Write);
                return;
            }

            if (key.PhysicalKeycode == Key.Escape)
            {
                Input.MouseMode = Input.MouseMode == Input.MouseModeEnum.Captured
                    ? Input.MouseModeEnum.Visible
                    : Input.MouseModeEnum.Captured;
                return;
            }
        }

        if (@event is InputEventMouseMotion motion && Input.MouseMode == Input.MouseModeEnum.Captured)
        {
            _yaw -= Mathf.DegToRad(motion.Relative.X * MouseSensitivity);
            _pitch -= Mathf.DegToRad(motion.Relative.Y * MouseSensitivity);
            _pitch = ClampPitch(_pitch);
        }
    }

    private float ClampPitch(float pitch)
    {
        bool inWater = _player != null && _player.IsSwimming && !_player.IsWading;
        float min = Mathf.DegToRad(inWater ? MinPitchInWater : MinPitch);
        float max = Mathf.DegToRad(inWater ? MaxPitchInWater : MaxPitch);
        return Mathf.Clamp(pitch, min, max);
    }

    public float LookPitch
    {
        get => _pitch;
        set => _pitch = ClampPitch(value);
    }
}
