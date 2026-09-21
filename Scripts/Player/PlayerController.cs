using Godot;

public partial class PlayerController : CharacterBody3D
{
    [Export] public float MoveSpeed = 5f;
    [Export] public float SprintSpeed = 8f;
    [Export] public float Acceleration = 12f;
    [Export] public float JumpHeight = 1.5f;
    [Export] public float Gravity = -9.81f;
    [Export] public float ImpulseDecay = 4f;
    [Export] public float MaxFallSpeed = -20f;

    [Export] public float SwimSpeed = 3f;
    [Export] public float SurfaceSwimSpeed = 5f;
    [Export] public float SwimAcceleration = 8f;
    [Export] public float SurfaceHeadHeight = 0.1f;
    [Export] public float DiveDelay = 0.25f;
    [Export] public float DiveLookDownDeg = 25f;
    [Export] public float SurfaceSpring = 10f;
    [Export] public float SurfaceDamping = 6f;
    [Export] public float SubmergedThreshold = 0.15f;
    [Export] public float SurfaceHysteresis = 0.1f;
    [Export] public float MaxSwimVerticalSpeed = 4f;
    [Export(PropertyHint.Range, "0.1,1,0.05")] public float WadeSpeedFactor = 0.5f;
    [Export] public float WadeDepth = 2f;
    [Export] public float CameraFloorClearance = 0.4f;

    [Export] public float IdleSpeed = 0.2f;
    [Export] public float WalkRunThreshold = 6f;
    [Export] public float WalkAnimSpeed = 2.5f;
    [Export] public float RunAnimSpeed = 6f;
    [Export] public float MinAnimScale = 0.6f;
    [Export] public float MaxAnimScale = 1.6f;
    [Export] public float AnimBlend = 0.15f;
    [Export] public float SwimVigorousSpeed = 2.2f;
    [Export] public float SwimStrokeBlend = 4f;
    [Export] public float MaxSwimForwardPitchDeg = 40f;
    [Export] public float MaxSwimStrafeRollDeg = 45f;
    [Export] public float SwimLeanSpeed = 60f;
    [Export] public float BodyPitchSpeed = 360f;
    [Export] public float MinJumpScale = 0.5f;
    [Export] public float MaxJumpScale = 1.5f;

    private Vector3 _horizontalVelocity = Vector3.Zero;
    private Vector3 _impulseVelocity = Vector3.Zero;
    private Vector3 _swimVelocity = Vector3.Zero;
    private float _verticalVelocity;
    private bool _jumpHeld;
    private float _diveCharge;
    private float _swimStrokeSpeed = 1f;
    private float _jumpScale = 1f;
    private float _jumpClipLength;
    private float _restHeight = 0.9f;
    private float _restHeadHeight = 1.45f;
    private float _leanRoll;
    private float _leanPitch;
    private float _bodyPitch;
    private Node3D _head;
    private Node3D _visual;
    private Skeleton3D _skeleton;
    private Camera3D _camera;
    private AnimationPlayer _anim;
    private string _clip = "";

    public bool IsGrounded => IsOnFloor();
    public bool IsSwimming { get; private set; }
    public float WaterSurfaceY { get; private set; }
    public bool IsUnderwater { get; private set; }
    public bool IsWading { get; private set; }
    public Vector2 SwimLeanDeg => new Vector2(_leanPitch, _leanRoll);
    public float LeanPitchRad => _leanPitch;
    public float BodyPitch => _bodyPitch;

    public override void _Ready()
    {
        _head = GetNodeOrNull<Node3D>("Head");
        _camera = GetNodeOrNull<Camera3D>("Head/Camera3D");
        _anim = GetNodeOrNull<AnimationPlayer>("Visual/Anim");
        _visual = GetNodeOrNull<Node3D>("Visual");
        _skeleton = GetNodeOrNull<Skeleton3D>("Visual/Skeleton3D");

        CapsuleShape3D capsule = (GetNodeOrNull<CollisionShape3D>("CollisionShape3D")?.Shape) as CapsuleShape3D;
        if (capsule != null)
            _restHeight = capsule.Height * 0.5f;

        float measuredHead = _HeadBoneHeight();
        if (measuredHead > 0.1f)
            _restHeadHeight = measuredHead;

        if (_anim != null)
        {
            Animation jump = _anim.GetAnimation("Jumping Up");
            if (jump != null)
                _jumpClipLength = (float)jump.Length;
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;
        Vector2 input = ReadMoveInput();

        _impulseVelocity = _impulseVelocity.MoveToward(Vector3.Zero, ImpulseDecay * dt);

        if (IsSwimming)
        {
            UpdateSubmersion();
            bool shallow = WaterSurfaceY - GroundHeightUnder(GlobalPosition) < WadeDepth;
            IsWading = !IsUnderwater && (IsOnFloor() || shallow);
            if (IsWading)
                SimulateGround(input, dt, WadeSpeedFactor);
            else
                SimulateSwim(input, dt);
        }
        else
        {
            IsUnderwater = false;
            IsWading = false;
            SimulateGround(input, dt, 1f);
        }

        MoveAndSlide();
        UpdateBodyPitch(input, dt);
        UpdateLean(input, dt);
        UpdateAnimation(input, dt);
    }

    private void UpdateBodyPitch(Vector2 input, float dt)
    {
        float target = 0f;
        if (IsSwimming && !IsWading && IsUnderwater)
        {
            if (_camera is CameraController cc)
                target = cc.LookPitch - Mathf.DegToRad(90f);
        }
        _bodyPitch = Mathf.MoveToward(_bodyPitch, target, Mathf.DegToRad(BodyPitchSpeed) * dt);
    }

    private void UpdateLean(Vector2 input, float dt)
    {
        float targetRoll = 0f;
        float targetPitch = 0f;
        if (IsSwimming && !IsWading && !IsUnderwater)
        {
            float lookDown = 0f;
            if (_camera is CameraController cc)
                lookDown = Mathf.Clamp((Mathf.RadToDeg(-cc.LookPitch) - 10f) / 15f, 0f, 1f);
            targetRoll = input.X * MaxSwimStrafeRollDeg;
            targetPitch = Mathf.Clamp(input.Y, 0f, 1f) * MaxSwimForwardPitchDeg * (1f - lookDown);
        }
        _leanRoll = Mathf.MoveToward(_leanRoll, targetRoll, SwimLeanSpeed * dt);
        _leanPitch = Mathf.MoveToward(_leanPitch, targetPitch, SwimLeanSpeed * dt);
        if (_visual == null)
            return;
        _visual.Rotation = new Vector3(Mathf.DegToRad(_leanPitch), Mathf.Pi, Mathf.DegToRad(_leanRoll));
    }

    private void UpdateAnimation(Vector2 input, float dt)
    {
        if (_anim == null)
            return;

        float speed = _horizontalVelocity.Length() + _impulseVelocity.Length();
        string clip;
        float scale = 1f;

        if (IsSwimming && !IsWading)
        {
            clip = "Swimming Loop";
            float activity = Mathf.Clamp(input.Length(), 0f, 1f);
            float target = Mathf.Lerp(1f, SwimVigorousSpeed, activity);
            _swimStrokeSpeed = Mathf.MoveToward(_swimStrokeSpeed, target, SwimStrokeBlend * dt);
            scale = _swimStrokeSpeed;
        }
        else if (!IsOnFloor())
        {
            clip = "Jumping Up";
            if (clip != _clip)
            {
                float airTime = PredictAirTime();
                _jumpScale = _jumpClipLength > 0.01f && airTime > 0.05f
                    ? Mathf.Clamp(_jumpClipLength / airTime, MinJumpScale, MaxJumpScale)
                    : 1f;
            }
            scale = _jumpScale;
        }
        else if (speed < IdleSpeed)
        {
            clip = "Idle";
        }
        else
        {
            bool running = speed >= WalkRunThreshold;
            clip = DirectionalClip(running ? "Run" : "Walk", input);
            scale = running
                ? Mathf.Clamp(speed / RunAnimSpeed, MinAnimScale, MaxAnimScale)
                : Mathf.Clamp(speed / WalkAnimSpeed, MinAnimScale, MaxAnimScale);
        }

        _anim.SpeedScale = scale;
        if (clip == _clip)
            return;

        _clip = clip;
        _anim.Play(clip, AnimBlend);
    }

    private float PredictAirTime()
    {
        float groundY = GroundHeightUnder(GlobalPosition);
        if (float.IsNegativeInfinity(groundY))
            return 1f;

        float g = -Gravity;
        if (g <= 0.01f)
            return 1f;

        float height = Mathf.Max(0f, GlobalPosition.Y - (groundY + _restHeight));
        float v = _verticalVelocity;
        return (v + Mathf.Sqrt(v * v + 2f * g * height)) / g;
    }

    private static string DirectionalClip(string gait, Vector2 input)
    {
        bool forward = input.Y > 0.5f;
        bool backward = input.Y < -0.5f;
        bool left = input.X < -0.5f;
        bool right = input.X > 0.5f;

        if (forward && left)
            return gait + " Diagonal Forward Left";
        if (forward && right)
            return gait + " Diagonal Forward Right";
        if (backward && left)
            return gait + " Diagonal Backward Left";
        if (backward && right)
            return gait + " Diagonal Backward Right";
        if (forward)
            return gait + " Forward";
        if (backward)
            return gait + " Backward";
        if (left)
            return gait + " Strafe Left";
        if (right)
            return gait + " Strafe Right";
        return gait;
    }

    private static Vector2 ReadMoveInput()
    {
        float x = (Input.IsPhysicalKeyPressed(Key.D) ? 1f : 0f) - (Input.IsPhysicalKeyPressed(Key.A) ? 1f : 0f);
        float z = (Input.IsPhysicalKeyPressed(Key.W) ? 1f : 0f) - (Input.IsPhysicalKeyPressed(Key.S) ? 1f : 0f);
        return new Vector2(x, z);
    }

    private void SimulateGround(Vector2 input, float dt, float speedFactor)
    {
        Vector3 forward = -GlobalTransform.Basis.Z;
        Vector3 right = GlobalTransform.Basis.X;
        Vector3 direction = right * input.X + forward * input.Y;
        if (direction.LengthSquared() > 0.0001f)
            direction = direction.Normalized();

        bool groundedNow = IsOnFloor();

        if (groundedNow)
        {
            bool running = Input.IsPhysicalKeyPressed(Key.Shift);
            float speed = (running ? SprintSpeed : MoveSpeed) * speedFactor;
            _horizontalVelocity = _horizontalVelocity.MoveToward(direction * speed, Acceleration * dt);
        }

        if (groundedNow)
            _verticalVelocity = -2f;

        if (groundedNow && Input.IsPhysicalKeyPressed(Key.Space) && !_jumpHeld)
            _verticalVelocity = Mathf.Sqrt(JumpHeight * -2f * Gravity);

        _jumpHeld = Input.IsPhysicalKeyPressed(Key.Space);

        _verticalVelocity += Gravity * dt;
        _verticalVelocity = Mathf.Max(_verticalVelocity, MaxFallSpeed);

        Velocity = _horizontalVelocity + _impulseVelocity + Vector3.Up * _verticalVelocity;
    }

    private void SimulateSwim(Vector2 input, float dt)
    {
        Vector3 camForward = _camera != null ? -_camera.GlobalTransform.Basis.Z : -GlobalTransform.Basis.Z;
        Vector3 camRight = _camera != null ? _camera.GlobalTransform.Basis.X : GlobalTransform.Basis.X;

        if (!IsUnderwater)
        {
            Vector3 fwdH = new Vector3(camForward.X, 0f, camForward.Z).Normalized();
            Vector3 rightH = new Vector3(camRight.X, 0f, camRight.Z).Normalized();
            Vector3 dirH = rightH * input.X + fwdH * input.Y;
            if (dirH.LengthSquared() > 1f)
                dirH = dirH.Normalized();

            _horizontalVelocity = _horizontalVelocity.MoveToward(dirH * SurfaceSwimSpeed, SwimAcceleration * dt);

            bool diveHold = input.Y > 0f && camForward.Y < -Mathf.Sin(Mathf.DegToRad(DiveLookDownDeg));
            if (diveHold)
                _diveCharge += dt;
            else
                _diveCharge = 0f;

            if (_diveCharge >= DiveDelay)
            {
                float diveSpeed = Mathf.Min(SwimSpeed, -camForward.Y * SwimSpeed * 3f);
                _verticalVelocity = Mathf.MoveToward(_verticalVelocity, -diveSpeed, SwimAcceleration * dt);
            }
            else
            {
                float headDip = _restHeadHeight * (1f - Mathf.Cos(_leanPitch));
                float targetY = WaterSurfaceY + SurfaceHeadHeight - _restHeadHeight + headDip;
                float displacement = targetY - GlobalPosition.Y;
                float accel = displacement * SurfaceSpring - _verticalVelocity * SurfaceDamping;
                _verticalVelocity = Mathf.Clamp(_verticalVelocity + accel * dt, -MaxSwimVerticalSpeed, MaxSwimVerticalSpeed);
            }

            _swimVelocity = Vector3.Zero;
            Velocity = _horizontalVelocity + Vector3.Up * _verticalVelocity;
        }
        else
        {
            Vector3 dir = camRight * input.X + camForward * input.Y;
            if (dir.LengthSquared() > 1f)
                dir = dir.Normalized();

            _swimVelocity = _swimVelocity.MoveToward(dir * SwimSpeed, SwimAcceleration * dt);
            _swimVelocity.Y = Mathf.Clamp(_swimVelocity.Y, -MaxSwimVerticalSpeed, MaxSwimVerticalSpeed);

            _verticalVelocity = 0f;
            _horizontalVelocity = Vector3.Zero;
            _diveCharge = 0f;

            Velocity = _swimVelocity + _impulseVelocity;
        }

        KeepCameraAboveGround();
    }

    private float _HeadBoneHeight()
    {
        if (_skeleton != null)
        {
            int bone = _skeleton.FindBone("Head");
            if (bone >= 0)
                return (_skeleton.GlobalTransform * _skeleton.GetBoneGlobalPose(bone)).Origin.Y - GlobalPosition.Y;
        }
        return _head != null ? Mathf.Max(0.1f, _head.GlobalPosition.Y - GlobalPosition.Y) : 1.6f;
    }

    private void UpdateSubmersion()
    {
        float depth = WaterSurfaceY - EyePosition().Y;
        float releaseDepth = Mathf.Max(0f, SubmergedThreshold - SurfaceHysteresis);
        IsUnderwater = IsUnderwater ? depth > releaseDepth : depth > SubmergedThreshold;
    }

    private void KeepCameraAboveGround()
    {
        Vector3 eye = EyePosition();
        float groundY = GroundHeightUnder(eye);
        if (float.IsNegativeInfinity(groundY))
            return;

        float minY = groundY + CameraFloorClearance;
        if (eye.Y < minY)
            GlobalPosition += Vector3.Up * (minY - eye.Y);
    }

    private float GroundHeightUnder(Vector3 position)
    {
        PhysicsDirectSpaceState3D space = GetWorld3D().DirectSpaceState;
        Vector3 origin = position + Vector3.Up * 3f;
        PhysicsRayQueryParameters3D query = PhysicsRayQueryParameters3D.Create(origin, origin + Vector3.Down * 100f);
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };
        Godot.Collections.Dictionary hit = space.IntersectRay(query);
        if (hit.Count == 0)
            return float.NegativeInfinity;
        return ((Vector3)hit["position"]).Y;
    }

    private Vector3 EyePosition()
    {
        if (_camera != null)
            return _camera.GlobalPosition;
        if (_head != null)
            return _head.GlobalPosition;
        return GlobalPosition + Vector3.Up * 1.6f;
    }

    public void EnterWater(float surfaceY)
    {
        WaterSurfaceY = surfaceY;
        if (IsSwimming)
            return;

        IsSwimming = true;
        _swimVelocity = Vector3.Zero;
        _impulseVelocity = Vector3.Zero;
        _diveCharge = 0f;
        if (_verticalVelocity < -MaxSwimVerticalSpeed)
            _verticalVelocity = -MaxSwimVerticalSpeed;
    }

    public void ExitWater()
    {
        if (!IsSwimming)
            return;

        IsSwimming = false;
        IsUnderwater = false;
        IsWading = false;
        _swimVelocity = Vector3.Zero;
        _diveCharge = 0f;
        if (_verticalVelocity < 0f)
            _verticalVelocity = 0f;
    }

    public void AddImpulse(Vector3 impulse)
    {
        _impulseVelocity += impulse;
    }

    public void Jump(float height)
    {
        _verticalVelocity = Mathf.Sqrt(height * -2f * Gravity);
    }
}
