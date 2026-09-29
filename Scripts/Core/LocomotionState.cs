using Godot;

namespace Glyphwake.Core;

/// Everything the submersion model needs to know about the body in one frame, measured by
/// whoever owns the physics. Kept separate from the state it feeds so the state machine has
/// no dependency on the scene tree, the camera, or the character body, and can therefore be
/// reasoned about (and tested) on its own.
public readonly struct SubmersionProbe
{
    /// Height of the water surface, in world Y.
    public readonly float WaterSurfaceY;

    /// Origin of the character body, in world Y.
    public readonly float BodyY;

    /// Bottom of the collision capsule, in world Y. This is what the water depth is measured
    /// from, not the body origin, so the capsule's own half height has to come in with it.
    public readonly float FootY;

    /// Eye position, in world Y. Submersion is judged from the eye because that is what the
    /// player actually sees go under.
    public readonly float EyeY;

    /// Capsule half height, and the height of the head bone above the body origin. Together
    /// they define the feet-to-head span that every submersion fraction is measured against.
    public readonly float RestHeight;
    public readonly float RestHeadHeight;

    /// Whether the body is resting on a surface. Only meaningful when
    /// <see cref="InWater"/>, because it is wading that needs it: a body can be wading because
    /// it is standing in the shallows, or because the floor is close enough to count as shallow
    /// even while it is still falling.
    public readonly bool OnFloor;

    public SubmersionProbe(
        float waterSurfaceY,
        float bodyY,
        float footY,
        float eyeY,
        float restHeight,
        float restHeadHeight,
        bool onFloor)
    {
        WaterSurfaceY = waterSurfaceY;
        BodyY = bodyY;
        FootY = footY;
        EyeY = eyeY;
        RestHeight = restHeight;
        RestHeadHeight = restHeadHeight;
        OnFloor = onFloor;
    }
}

/// The single owner of the character's water state.
///
/// This used to be five flags -- IsSwimming, IsUnderwater, IsWading, AtSwimDepth and
/// WadeSubmersion -- set in one place and then recombined by hand at six separate call sites
/// across three files. Two of those six were the same predicate written twice, and one was a
/// third spelling of it, which is the kind of drift that produces a camera that fights the
/// body it is attached to. The raw latches still exist here, because they are genuinely
/// independent measurements with hysteresis, but the *answers* to "is this character
/// swimming" are now asked of <see cref="Mode"/>, and there is exactly one of it.
public sealed class LocomotionState
{
    // --- Tuning. Mirrored from the owning controller's exports so the scene keeps a single
    // --- place to author them, but consumed here so the state machine owns its own rules.

    /// Eye depth, in metres, at which the character counts as underwater. Latched with
    /// hysteresis against <see cref="SurfaceHysteresis"/> so treading, which bobs the eye
    /// through the waterline, cannot flicker the underwater state.
    public float SubmergedThreshold = 0.15f;

    /// How much less depth it takes to *leave* the underwater state than to enter it.
    public float SurfaceHysteresis = 0.1f;

    /// Fraction of the feet-to-head span that has to be under before the water takes over.
    /// This is the one knob for "submerged to the neck": it starts the float that slows the
    /// fall and the swim clip together, so the buoyancy and the animation can never disagree
    /// about when the character counts as being in the water.
    public float FloatEngageDepth = 0.7f;

    /// Water depth, in metres, below which a body over water is wading rather than swimming.
    public float WadeDepth = 2f;

    // --- Raw latched state. These are measurements, not answers.

    /// True while the body is inside a water volume. The water zone reaches above the
    /// waterline, so this only means the body is *over* the water -- leaping off a ledge puts
    /// you inside the zone while still in open air. Nothing that switches the character into a
    /// swimming *look* fires off this on its own.
    public bool InWater { get; private set; }

    /// Height of the water surface the body is in, in world Y.
    public float WaterSurfaceY { get; private set; }

    /// Whether the eye is below the waterline, latched with hysteresis.
    public bool IsUnderwater { get; private set; }

    /// Whether the body is submerged to the neck, latched with hysteresis so a body settling
    /// exactly on the threshold cannot chatter between the swim clip and the jump clip.
    public bool AtSwimDepth { get; private set; }

    /// Fraction of the feet-to-head span that is currently under, 0 to 1. Drag scales with
    /// this, so it bottoms out exactly where swimming takes over rather than at some
    /// unrelated depth.
    public float WadeSubmersion { get; private set; }

    /// Whether the body is in water shallow enough to walk in, or standing on a floor that
    /// counts as shallow.
    public bool IsWading { get; private set; }

    /// The answer to every "what is this character doing" question. Assigned once per physics
    /// step by <see cref="Update"/> and read by everything else.
    public LocomotionMode Mode { get; private set; } = LocomotionMode.Grounded;

    /// In a water volume but not wading: swimming, or on the way in. This is the predicate
    /// the water surface and the pitch clamp want.
    public bool IsSwimmingFreely =>
        Mode is LocomotionMode.EnteringWater
            or LocomotionMode.SurfaceSwimming
            or LocomotionMode.UnderwaterSwimming;

    /// In a water volume, not wading, and not submerged past the eye: either treading at the
    /// surface or still falling in. The swim pose and the camera's eye lift both want exactly
    /// this, which is why they used to spell the same condition out separately.
    public bool IsAtOrAboveSurface =>
        Mode is LocomotionMode.EnteringWater or LocomotionMode.SurfaceSwimming;

    /// On the surface, rather than on the way in. The surface-swim lean and the surface-swim
    /// clip want this, and it is deliberately narrower than <see cref="IsAtOrAboveSurface"/>:
    /// a body still falling into the water keeps its fall.
    public bool IsSurfaceSwimming => Mode == LocomotionMode.SurfaceSwimming;

    /// Playing a swimming clip of any kind, surface or submerged.
    public bool IsSwimming =>
        Mode is LocomotionMode.SurfaceSwimming or LocomotionMode.UnderwaterSwimming;

    public void EnterWater(float surfaceY)
    {
        WaterSurfaceY = surfaceY;
        if (InWater)
            return;
        InWater = true;
    }

    public void ExitWater()
    {
        if (!InWater)
            return;
        InWater = false;
        IsUnderwater = false;
        IsWading = false;
        AtSwimDepth = false;
        WadeSubmersion = 0f;
    }

    /// Recomputes every latch and then <see cref="Mode"/>. The order matters: submersion is
    /// measured before it is latched, and wading is resolved last because it is the only one of
    /// the three that also depends on the ground.
    ///
    /// <paramref name="groundY"/> is the height of the floor beneath the body, or negative
    /// infinity when there is none. It is only read when the body is in water, which is why the
    /// caller can skip the raycast entirely when it is not -- that raycast is the single most
    /// expensive thing this class could otherwise ask for, and a character on dry land has no
    /// use for it.
    public void Update(in SubmersionProbe probe, float groundY)
    {
        if (!InWater)
        {
            IsUnderwater = false;
            IsWading = false;
            AtSwimDepth = false;
            WadeSubmersion = 0f;
            Mode = probe.OnFloor ? LocomotionMode.Grounded : LocomotionMode.Airborne;
            return;
        }

        float span = Mathf.Max(0.1f, probe.RestHeadHeight + probe.RestHeight);

        float depth = probe.WaterSurfaceY - probe.EyeY;
        float releaseDepth = Mathf.Max(0f, SubmergedThreshold - SurfaceHysteresis);
        IsUnderwater = IsUnderwater ? depth > releaseDepth : depth > SubmergedThreshold;

        WadeSubmersion = Mathf.Clamp((probe.WaterSurfaceY - probe.FootY) / span, 0f, 1f);

        // Latches on at FloatEngageDepth and back off by the same hysteresis IsUnderwater
        // uses, in span fractions rather than metres, so a body sitting exactly on the
        // threshold settles instead of chattering between two large pose changes.
        float swimRelease = Mathf.Max(0f, FloatEngageDepth - SurfaceHysteresis / span);
        AtSwimDepth = AtSwimDepth
            ? WadeSubmersion > swimRelease
            : WadeSubmersion >= FloatEngageDepth;

        bool shallow = probe.WaterSurfaceY - groundY < WadeDepth;
        IsWading = !IsUnderwater && (probe.OnFloor || shallow);

        // Wading wins over everything, then submersion, then whether the body is deep enough
        // to be swimming rather than falling in. The three are mutually exclusive by
        // construction, which is the whole point: there is no fourth combination to remember.
        Mode = IsWading
            ? LocomotionMode.Wading
            : IsUnderwater
                ? LocomotionMode.UnderwaterSwimming
                : AtSwimDepth
                    ? LocomotionMode.SurfaceSwimming
                    : LocomotionMode.EnteringWater;
    }
}
