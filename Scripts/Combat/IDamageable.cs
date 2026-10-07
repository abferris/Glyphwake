using Godot;

namespace Glyphwake.Combat;

/// Anything a glyph's effect can hurt. The caster's melee shapes and, later, its projectiles
/// resolve their hits against this rather than against a concrete enemy type, so a training
/// dummy, a breakable crate and a real enemy all take a hit through the same call.
///
/// <paramref name="direction"/> is the direction the damage travels, in world space: the
/// receiver decides what to do with it -- a knockback, a blood decal, a flinch -- rather than
/// the sender deciding on its behalf.
public interface IDamageable
{
    void ApplyDamage(float amount, Vector3 direction);
}