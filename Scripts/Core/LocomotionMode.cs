namespace Glyphwake.Core;

/// The single authoritative description of how the character is currently moving. Every
/// consumer of water state -- animation, the camera, the swim pose, the physics -- reads
/// this instead of recombining the individual water flags by hand, which is what made
/// "am I swimming" mean something slightly different in each of the six places it was asked.
public enum LocomotionMode
{
    /// Out of the water and on the floor.
    Grounded,

    /// Out of the water and off the floor.
    Airborne,

    /// In a water body, with the feet near the floor and the body not submerged.
    Wading,

    /// In a water body, not wading, and not yet submerged to the neck. This is a body on its
    /// way in: the water zone reaches above the waterline, so a jump or a leap off a ledge puts
    /// the body inside the zone while it is still falling through open air. Nothing that
    /// switches the character into a swimming *look* fires in this state, so a jump into the
    /// water keeps its fall and its jump animation until the body is genuinely submerged.
    EnteringWater,

    /// In a water body, not wading, at or above the waterline, and submerged to the neck.
    SurfaceSwimming,

    /// In a water body, not wading, with the eye below the waterline.
    UnderwaterSwimming,
}
