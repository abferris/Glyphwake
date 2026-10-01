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

    /// Vertical velocity of the body, in world Y, negative when falling. Depth alone cannot tell
    /// a plunge from a swim: a body dropping in from height crosses the treading depth in a
    /// couple of ticks while still doing 15 m/s, so it would already be submerged and still
    /// falling at the same moment. Speed is what separates "falling into the water" from "in the
    /// water", and it is the body that integrates it, so it comes in with the rest of the
    /// frame's measurements.
    public readonly float VerticalVelocity;

    public SubmersionProbe(
        float waterSurfaceY,
        float bodyY,
        float footY,
        float eyeY,
        float restHeight,
        float restHeadHeight,
        bool onFloor,
        float verticalVelocity)
    {
        WaterSurfaceY = waterSurfaceY;
        BodyY = bodyY;
        FootY = footY;
        EyeY = eyeY;
        RestHeight = restHeight;
        RestHeadHeight = restHeadHeight;
        OnFloor = onFloor;
        VerticalVelocity = verticalVelocity;
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

    /// Fraction of the feet-to-head span at which a body standing on the floor hands over from
    /// the walk clips to the swim clips. Deeper than <see cref="FloatEngageDepth"/> on purpose:
    /// a body in the air is falling, and being mostly under is enough for the float to arrest
    /// it, but a body on the bottom is not going anywhere and still has its footing, so the
    /// water has to be over its shoulders before the ground look gives way. 0.92 is measured
    /// rather than picked: the shoulder bone sits 0.114 m below the head on this rig, and the
    /// head is the whole span above the feet, so the shoulders go under at 0.921 of it.
    public float WadeHandoverDepth = 0.92f;

    /// Water depth, in metres, below which a body over water is wading rather than swimming.
    /// A depth in metres of water under the ground, not a fraction of the body like its
    /// neighbours.
    public float WadeDepth = 2f;

    /// Downward speed, in m/s, above which a body in water is still falling rather than
    /// swimming, however deep it is. This is what separates a plunge from a dive: submersion
    /// alone fires the swimming look while a body dropping in from height is still doing well
    /// over 10 m/s, because the fall covers the last half-metre of depth in two or three ticks.
    /// It has to sit above <see cref="MaxSwimVerticalSpeed"/>-class speeds, or a body deliberately
    /// diving down would read as a plunge and be denied its own swimming look.
    public float PlungeSpeed = 6f;

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

    /// True while the body is in water and still arriving at it fast enough to be falling
    /// rather than swimming. Latched, and released at half <see cref="PlungeSpeed"/>, so the
    /// float spring's overshoot around its equilibrium cannot put the body back into a fall
    /// that has already ended.
    public bool IsPlunging { get; private set; }

    /// Whether the body is in water shallow enough to walk in, or standing on a floor that
    /// counts as shallow.
    public bool IsWading { get; private set; }

    /// Height of the floor beneath the body, in world Y, or negative infinity when there is
    /// none. Only meaningful while <see cref="InWater"/>, because that is the only time the
    /// caller pays for the raycast. Published because <see cref="IsWading"/> answers the
    /// yes/no but not the where, and the float needs the where: it has to know how far down
    /// the shelf is that the body is standing on rather than treading over.
    public float GroundY { get; private set; } = float.NegativeInfinity;

    /// Whether the floor under the body is shallow enough to stand in, rather than the body
    /// being wading because it is already standing. The difference matters to the float: a
    /// body already on the floor is being held up by it, but a body floating over a shallow
    /// floor is being held up by the water at a depth that puts its feet below the step it is
    /// trying to climb.
    public bool IsOverShallowFloor => IsWading && !IsUnderwater && _overShallowFloor;

    private bool _overShallowFloor;

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
    /// surface or still falling in. The camera's eye lift wants exactly this, which is why it
    /// used to be spelled out separately.
    ///
    /// The swim pose modifier does not use this, despite the name reading as if it should. It
    /// used to, and because the water zone reaches 25 m above the waterline that meant it ran for
    /// the whole of the plunge through open air. It waits on <see cref="IsSurfaceSwimming"/>
    /// instead, so the water only starts authoring the pose once the body is floating in it.
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
        IsPlunging = false;
        _overShallowFloor = false;
        GroundY = float.NegativeInfinity;
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
            IsPlunging = false;
            WadeSubmersion = 0f;
            _overShallowFloor = false;
            GroundY = float.NegativeInfinity;
            Mode = probe.OnFloor ? LocomotionMode.Grounded : LocomotionMode.Airborne;
            return;
        }

        float span = Mathf.Max(0.1f, probe.RestHeadHeight + probe.RestHeight);

        float depth = probe.WaterSurfaceY - probe.EyeY;
        float releaseDepth = Mathf.Max(0f, SubmergedThreshold - SurfaceHysteresis);
        IsUnderwater = IsUnderwater ? depth > releaseDepth : depth > SubmergedThreshold;

        WadeSubmersion = Mathf.Clamp((probe.WaterSurfaceY - probe.FootY) / span, 0f, 1f);

        // A plunge latches on the way in and only lets go once the body has slowed to half
        // PlungeSpeed, so the spring's overshoot around its equilibrium cannot re-arm it. The
        // latch is what the swimming look waits on, and it is deliberately independent of depth:
        // depth alone fires the moment the body is submerged, which a fall from height reaches
        // while still doing well over 10 m/s, and the swimming look then replaces the fall pose
        // on a body that has not stopped moving yet.
        IsPlunging = IsPlunging
            ? probe.VerticalVelocity < -PlungeSpeed * 0.5f
            : probe.VerticalVelocity < -PlungeSpeed;

        // Latches on at FloatEngageDepth -- or at WadeHandoverDepth for a body standing on the
        // bottom, which has to be under further before the water takes its look -- and backs off
        // by the same hysteresis IsUnderwater uses, in span fractions rather than metres, so a
        // body sitting exactly on the threshold settles instead of chattering between two large
        // pose changes. Which of the two applies is re-read every frame rather than latched
        // alongside it, so touching down and standing back up cannot strand the body on the
        // wrong side of its own dead zone.
        float engage = probe.OnFloor ? WadeHandoverDepth : FloatEngageDepth;
        float swimRelease = Mathf.Max(0f, engage - SurfaceHysteresis / span);
        AtSwimDepth = AtSwimDepth
            ? WadeSubmersion > swimRelease
            : WadeSubmersion >= engage;

        bool shallow = probe.WaterSurfaceY - groundY < WadeDepth;
        IsWading = !IsUnderwater && (probe.OnFloor || shallow);
        _overShallowFloor = shallow;
        GroundY = groundY;

        // The eye wins outright, then submersion, then the ground, and the three are mutually
        // exclusive by construction, which is the whole point: there is no fourth combination
        // to remember. Wading used to be resolved first, which meant a body standing in
        // chest-deep water kept the ground clips until the eye itself went under -- the walk
        // outlived the water by the whole depth of the head, and the same ordering made a body
        // climbing back out tread until the eye crossed the surface on the way up. Wading is a
        // statement about what is holding the body up, so it belongs last: it only gets a say
        // once the water is demonstrably not over the shoulders.
        // The plunge is resolved first, ahead of everything below it, because it is the only one
        // of the four that is a statement about speed rather than about depth or ground. A body
        // that is still arriving fast is falling, whatever it happens to be submerged to, so it
        // keeps the fall clip and the upright body until the water has actually caught it. That
        // is what stops a jump into the water from swapping to the swimming pose on the way in:
        // the old ordering asked only how deep the body was, and depth runs out long before speed
        // does. Everything else is mutually exclusive by construction, which is the rest of the
        // point: there is no fourth combination to remember.
        Mode = IsPlunging
            ? LocomotionMode.EnteringWater
            : IsUnderwater
                ? LocomotionMode.UnderwaterSwimming
                : AtSwimDepth
                    ? LocomotionMode.SurfaceSwimming
                    : IsWading
                        ? LocomotionMode.Wading
                        : LocomotionMode.EnteringWater;
    }
}
