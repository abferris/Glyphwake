using System.Collections.Generic;
using Godot;

namespace Glyphwake.Player;

/// <summary>
/// A poseable stone hand built from a pivot hierarchy (palm chunks + finger joint chains).
/// Poses are rotations on the pivot nodes, so any system can pose it without rigging:
/// SetPose for presets, SetFingerCurl for per-finger control.
/// </summary>
public partial class StoneHand : Node3D
{
    public enum Pose { Open, Relax, Fist, Point }

    [Export] public Pose StartPose = Pose.Relax;
    [Export] public float BaseCurlDegrees = 70f;
    [Export] public float MidCurlDegrees = 80f;
    [Export] public float TipCurlDegrees = 55f;

    private static readonly string[] FingerNames = { "Thumb", "Index", "Middle", "Ring", "Pinky" };
    private static readonly string[] JointNames = { "Base", "Mid", "Tip" };

    private readonly Dictionary<string, Node3D> _pivots = new();
    private readonly Dictionary<string, Vector3> _rest = new();

    public override void _Ready()
    {
        foreach (string finger in FingerNames)
        {
            foreach (string joint in JointNames)
            {
                Node3D pivot = GetNodeOrNull<Node3D>(finger + joint);
                if (pivot == null)
                    continue;
                _pivots[finger + joint] = pivot;
                _rest[finger + joint] = pivot.Rotation;
            }
        }
        SetPose(StartPose);
    }

    public void SetPose(Pose pose)
    {
        switch (pose)
        {
            case Pose.Open:
                SetAllCurls(0f);
                break;
            case Pose.Relax:
                SetAllCurls(0.3f);
                break;
            case Pose.Fist:
                SetAllCurls(1f);
                break;
            case Pose.Point:
                SetFingerCurl("Index", 0f);
                SetFingerCurl("Thumb", 1f);
                SetFingerCurl("Middle", 1f);
                SetFingerCurl("Ring", 1f);
                SetFingerCurl("Pinky", 1f);
                break;
        }
    }

    public void SetAllCurls(float curl)
    {
        foreach (string finger in FingerNames)
            SetFingerCurl(finger, curl);
    }

    public void SetFingerCurl(string finger, float curl)
    {
        curl = Mathf.Clamp(curl, 0f, 1f);
        Curl(finger + "Base", curl, BaseCurlDegrees);
        Curl(finger + "Mid", curl, MidCurlDegrees);
        Curl(finger + "Tip", curl, TipCurlDegrees);
    }

    private void Curl(string key, float curl, float maxDegrees)
    {
        if (!_pivots.TryGetValue(key, out Node3D pivot))
            return;
        pivot.Rotation = _rest[key] + new Vector3(-curl * Mathf.DegToRad(maxDegrees), 0f, 0f);
    }
}
