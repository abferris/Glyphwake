using Godot;
using Godot.Collections;

namespace Glyphwake.Glyphs;

/// A one-shot animation a glyph plays on its caster, carried as its own scene rather than as a
/// clip name in the player's locomotion library.
///
/// The reason is <c>AnimationIds.ReachableClips</c>. That list is the closed set of clips movement
/// can ask for, and <c>LocomotionGraph</c> builds one state per clip with every state able to
/// reach every other -- 16 clips is already 240 transitions, and the rule is quadratic, so a cast
/// animation per glyph added to that list turns a fixed cost into a per-glyph one that grows far
/// faster than the number of glyphs. Carrying the animation in its own scene keeps that list
/// locomotion and lets any number of glyphs each own theirs.
///
/// Empty is meaningful and is the common case. The game is first person, so the caster's own body
/// is usually off screen, and a glyph with no cast animation casts without one rather than failing.
/// A separate AnimationPlayer writing the same skeleton as the locomotion tree is also the reason
/// this is opt-in per glyph rather than always on.
///
/// The scene is instantiated per cast by whoever plays it; this resource only says which scene and
/// which clip, and whether the two actually agree.
[GlobalClass]
public partial class GlyphCastAnimation : Resource
{
    /// The scene to instantiate under the caster. It must contain an AnimationPlayer holding
    /// <see cref="Clip"/>; it need not be the scene's root.
    [Export] public PackedScene Scene;

    /// The clip to play, named in that scene's AnimationPlayer. Also the fallback a variant
    /// key that names nothing resolves to, so a typo plays the default pose rather than
    /// nothing.
    [Export] public StringName Clip;

    /// The directional variants, keyed by the closed vocabulary in
    /// <see cref="GlyphCastVariant"/>. Empty is the common case: a cast animation with one
    /// pose needs no table. A key that names nothing resolves back to <see cref="Clip"/>
    /// rather than to silence, so an unkeyed cast and a mistyped key both fail safe.
    [Export] public Array<GlyphCastVariant> Variants = new();

    /// Crossfade from whatever the character is already playing into the cast.
    [Export(PropertyHint.Range, "0,1,0.01")] public float BlendIn = 0.15f;

    /// Crossfade from the cast back out to locomotion when the clip ends.
    [Export(PropertyHint.Range, "0,1,0.01")] public float BlendOut = 0.2f;

    /// The clip for a variant key, falling back to <see cref="Clip"/> when the key names
    /// nothing. The fallback rather than a null return is deliberate: a mistyped key or an
    /// unkeyed cast plays the default pose rather than nothing, and the caller does not have
    /// to handle a missing clip on top of a missing table.
    public StringName ClipFor(StringName key)
    {
        if (key != null && !key.IsEmpty)
        {
            foreach (GlyphCastVariant variant in Variants)
            {
                if (variant != null && variant.Key == key
                    && variant.Clip != null && !variant.Clip.IsEmpty)
                    return variant.Clip;
            }
        }
        return Clip;
    }

    /// Whether this names something playable at all. A null Scene or empty Clip is a glyph that
    /// casts without an animation, not a broken one, so this is the guard a caller checks before
    /// it tries to play anything.
    public bool HasAnimation => Scene != null && Clip != null && !Clip.IsEmpty;

    /// Checks that the scene can be instantiated and actually holds the named clip, pushing a Godot
    /// error naming the mismatch. Returns true when the two agree.
    ///
    /// This instantiates the scene, because a PackedScene exposes nothing about the clips inside
    /// it -- only an instantiated AnimationPlayer knows what its libraries hold. So it costs a node
    /// and whatever that node's _Ready does, which is why it is a call the caller chooses to make
    /// rather than something asked during load.
    ///
    /// It exists because the editor cannot check it: Scene accepts any scene, so a wrong clip name
    /// is authorable and would otherwise surface as a cast that silently plays nothing. That is the
    /// same failure shape <c>LocomotionGraph.MissingClips</c> already reports for a renamed
    /// locomotion clip, and it is why a cast animation is not just a StringName against the
    /// player's library -- there would be nothing to check it against.
    public bool Validate()
    {
        if (!HasAnimation)
        {
            GD.PushError($"{ResourcePath}: a cast animation needs both a scene and a clip name");
            return false;
        }

        if (!Scene.CanInstantiate())
        {
            GD.PushError($"{ResourcePath}: the scene '{Scene.ResourcePath}' cannot be instantiated");
            return false;
        }

        Node instance = Scene.Instantiate();
        AnimationPlayer player = FindAnimationPlayer(instance);

        if (player == null)
        {
            GD.PushError(
                $"{ResourcePath}: '{Scene.ResourcePath}' holds no AnimationPlayer to play " +
                $"'{Clip}' from");
            instance.Free();
            return false;
        }

        if (!player.HasAnimation(Clip))
        {
            GD.PushError(
                $"{ResourcePath}: '{Scene.ResourcePath}' has no clip '{Clip}'; it has " +
                $"{DescribeClips(player)}");
            instance.Free();
            return false;
        }

        // Every variant is checked against the same player, because the keys are hand-typed
        // strings in a .tres and a typo there surfaces as a variant that silently plays the
        // fallback rather than the pose that was authored.
        foreach (GlyphCastVariant variant in Variants)
        {
            if (variant == null || variant.Key == null || variant.Key.IsEmpty)
            {
                GD.PushError($"{ResourcePath}: a cast variant needs a key");
                instance.Free();
                return false;
            }
            if (variant.Clip == null || variant.Clip.IsEmpty || !player.HasAnimation(variant.Clip))
            {
                GD.PushError(
                    $"{ResourcePath}: '{Scene.ResourcePath}' has no clip for variant " +
                    $"'{variant.Key}' (named '{variant.Clip}'); it has {DescribeClips(player)}");
                instance.Free();
                return false;
            }
        }

        instance.Free();
        return true;
    }

    /// The AnimationPlayer to play from, searched depth-first so a scene may wrap its player in
    /// whatever structure suits it rather than having to be the player itself. Internal rather
    /// than private because the cast playback layer resolves the same player for the same reason.
    internal static AnimationPlayer FindAnimationPlayer(Node root)
    {
        if (root is AnimationPlayer player)
            return player;

        foreach (Node child in root.GetChildren())
        {
            AnimationPlayer found = FindAnimationPlayer(child);
            if (found != null)
                return found;
        }

        return null;
    }

    private static string DescribeClips(AnimationPlayer player)
    {
        // string[] rather than Godot.Collections.Array<StringName>: that is what
        // AnimationPlayer.GetAnimationList returns in the 4.7 C# bindings.
        string[] clips = player.GetAnimationList();
        return clips.Length == 0 ? "no clips at all" : string.Join(", ", clips);
    }
}