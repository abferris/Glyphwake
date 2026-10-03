using Godot;
using Glyphwake.Core;

namespace Glyphwake.Player;

/// A second, independent camera for inspecting the character from outside. It borrows the
/// viewport rather than owning it: only one Camera3D can be current, so it takes the viewport
/// on demand and hands it straight back, and the head camera is told either way so the game is
/// never left with no current camera at all.
public partial class DebugChaseCamera : Camera3D
{
    [Export] public float Distance = 3.2f;
    [Export] public float Height = 1.2f;
    [Export] public float PitchFactor = 0.5f;
    [Export] public Key ToggleKey = Key.F3;

    private Node3D _body;
    private CameraController _head;
    private bool _held;

    public bool Active => _held;

    public override void _Ready()
    {
        TopLevel = true;
        Node node = GetParent();
        while (node != null && node is not CharacterBody3D)
            node = node.GetParent();
        _body = node as Node3D;
        if (_body != null)
            _head = _body.GetNodeOrNull<CameraController>(PlayerRig.CameraNodePath);
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is not InputEventKey key || !key.Pressed || key.Echo)
            return;
        if (key.PhysicalKeycode != ToggleKey)
            return;
        SetActive(!_held);
        GetViewport().SetInputAsHandled();
    }

    // Claims or releases the viewport. The head camera is the default view, so it has to be told
    // either way, otherwise the game is left with no current camera at all.
    public void SetActive(bool on)
    {
        _held = on;
        Current = on;
        if (_head != null)
            _head.SetViewportHeld(on);
    }

    public override void _Process(double delta)
    {
        if (_body == null || _head == null || !_held)
            return;

        // The underwater tint lives on the head camera's environment, so borrow it rather than
        // duplicating the fog setup: this view would otherwise lose the tint while submerged.
        Environment = _head.Environment;

        float yaw = _body.Rotation.Y;
        float elev = Mathf.DegToRad(Mathf.RadToDeg(-_head.LookPitch) * PitchFactor);
        Vector3 behind = new Vector3(Mathf.Sin(yaw), 0f, Mathf.Cos(yaw));
        Vector3 target = _body.GlobalPosition + Vector3.Up * 1.0f;
        GlobalPosition = target + behind * (Distance * Mathf.Cos(elev)) + Vector3.Up * (Height + Distance * Mathf.Sin(elev));
        LookAt(target + Vector3.Up * 0.3f, Vector3.Up);
    }
}
