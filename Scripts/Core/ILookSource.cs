namespace Glyphwake.Core;

/// Implemented by anything that can report where it is looking, in radians, with 0 as level.
/// The character reads this to pitch its body under water. It is an interface rather than a
/// direct reference to the camera class so the dependency runs one way: the camera knows it
/// is being watched, the body does not know what class is watching it.
public interface ILookSource
{
    float LookPitch { get; }
}
