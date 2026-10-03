namespace Glyphwake.Core;

/// The project's 3D physics collision layers, and the masks that go with them.
///
/// An object's layer is declared and set from here rather than as a literal at each site, for
/// the same reason the clip names live in AnimationIds: the mapping from role to bit is
/// knowledge the whole project shares, and shared knowledge can be changed in one place. The bit
/// values are duplicated in project.godot's [layer_names] so the editor shows the same names, and
/// in the scene files, because a scene's layer is data rather than code.
///
/// <see cref="PlayerHitbox"/> and <see cref="Projectile"/> are reserved -- nothing sits on them
/// yet, so every mask below ignores them. That is the point: adding the shapes without adding
/// them to somebody's mask should mean a skillshot that forgets to opt in hits terrain, not
/// players.
///
/// The player's own mask is World and not "everything": the movement capsule should collide with
/// geometry, not with other capsules' combat shapes or with projectiles bouncing off them. Contact
/// with another player body is a separate decision to make deliberately against PlayerBody
/// rather than arriving by default.
public static class CollisionLayers
{
    /// Static geometry: terrain, rocks, trees. Layer 1, so objects that never set a layer and
    /// so default to it -- Terrain3D's generated collision, the TestWorld ground -- are already
    /// on World without an edit.
    public const uint World = 1;

    /// The player's movement capsule, and the only layer the water zones look for.
    public const uint PlayerBody = 2;

    /// Combat shapes derived from the player's skeleton. Not in use yet.
    public const uint PlayerHitbox = 4;

    /// Skillshot bodies in flight. Not in use yet.
    public const uint Projectile = 8;

    /// What a downward ground probe should be allowed to hit: geometry, and nothing else. This
    /// is the mask that keeps a second player's capsule from being reported as the floor.
    public const uint GroundProbeMask = World;

    /// What a third-person camera boom should be allowed to hit. Same reasoning as
    /// <see cref="GroundProbeMask"/>: pulling the camera in for a wall is the intent, and
    /// pulling it in for another player walking past is not.
    public const uint CameraBoomMask = World;

    /// What a water zone should detect: player bodies only. Water is a volume the player is
    /// inside of, not something the player collides with, so this is deliberately not a
    /// symmetric pairing -- the zone watches PlayerBody, and the capsule's own mask is
    /// irrelevant to being detected.
    public const uint WaterZoneDetectMask = PlayerBody;
}
