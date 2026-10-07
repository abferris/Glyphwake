using System;
using Godot;
using Glyphwake.Core;
using Glyphwake.Glyphs;

namespace Glyphwake.Player;

/// Plays a glyph's cast animation as a layer over the locomotion tree: one AnimationTree, the
/// cast clip blended in over the bones its tracks name, every other bone left to locomotion.
///
/// This is the per-bone takeover the cast model asks for -- a fire bolt would take the hands,
/// a technique the legs -- and it needs no second AnimationPlayer writing the skeleton, which
/// dissolves the two-writer question entirely. The cast's clips are merged into the main
/// player's library under a under the "cast" library, and a one-shot node in
/// the tree (<see cref="LocomotionGraph.CastNode"/>) runs the clip once, fades in and out, and
/// hands back. The one-shot's filters are set from the clip's own track list at cast time, so
/// the bones taken over follow from what the clip animates rather than from a second list to
/// keep in sync.
///
/// The cast scene's own AnimationPlayer is never a second writer: the scene is instantiated
/// once at build, its clips are merged into the main player's library, and the instance is
/// freed -- the Animation resources survive in the library, and nothing plays through the
/// scene's player.
public sealed class CastAnimationLayer
{
    /// The library namespace the cast's clips are merged under. A separate library on the main
    /// player, because an animation name cannot contain a "/": the namespace is the library,
    /// and "cast/<clip>" is the player's library/animation path. Keeping the cast clips in
    /// their own library means the locomotion graph and the tests never mistake a cast clip
    /// for a reachable one.
    public const string CastLibraryName = "cast";

    private readonly AnimationTree _tree;
    private readonly AnimationPlayer _player;
    private readonly AnimationNodeOneShot _oneShot;
    private readonly AnimationNodeAnimation _castClipNode;

    private GlyphCastAnimation _techniqueCast;
    private GlyphCastAnimation _activeCast;
    private string _currentClip = "";
    private bool _wasActive;

    /// The technique's cast animation this layer plays. Null means the technique has no cast
    /// animation, and every air jump then plays the bare locomotion look rather than a step.
    public GlyphCastAnimation Cast => _techniqueCast;

    /// The cast clip currently playing, without the library namespace, or an empty string
    /// when nothing is. Read by the GDScript tests: the one-shot reports nothing on its own,
    /// so this is the honest way to ask what the cast is doing.
    public string CurrentClip => _currentClip;

    /// The cast clips merged into the player's library -- the technique's and the active's, in
    /// the order they were built. Empty when there is no cast animation.
    public string[] ClipNames { get; private set; } = Array.Empty<string>();

    /// Whether the tree can play casts at all: a cast animation, a tree, and a player all
    /// resolved. False otherwise, and every call here is then a no-op.
    public bool Playable =>
        (_techniqueCast != null || _activeCast != null) && _oneShot != null && _player != null && _tree != null;

    /// Whether a cast is playing right now, read back from the tree. The one-shot clears this
    /// itself when the clip ends, so this is the truth rather than a timer.
    public bool IsActive => _tree.Get($"parameters/{LocomotionGraph.CastNode}/active").AsBool();

    public CastAnimationLayer(AnimationTree tree, AnimationPlayer player)
    {
        _tree = tree;
        _player = player;
        AnimationNodeBlendTree root = tree?.TreeRoot as AnimationNodeBlendTree;
        _oneShot = root?.GetNode(LocomotionGraph.CastNode) as AnimationNodeOneShot;
        _castClipNode = root?.GetNode(LocomotionGraph.CastClipNode) as AnimationNodeAnimation;
    }

    /// Merges the technique's cast scene into the player's library under the cast namespace, and
    /// remembers the resource to play from. The cast scene is instantiated once and freed: the
    /// Animation resources survive in the library, and the scene's own player is not left
    /// writing the skeleton behind the tree.
    public void Build(GlyphCastAnimation cast)
    {
        if (!MergeClips(cast))
            return;
        _techniqueCast = cast;
    }

    /// Merges an active glyph's cast scene into the same library. A second entry point rather
    /// than a second layer: both casts share one library and one one-shot, so a punch and an air
    /// step resolve through the same playback path and only the clip that fires differs.
    public void BuildActive(GlyphCastAnimation cast)
    {
        if (!MergeClips(cast))
            return;
        _activeCast = cast;
    }

    /// Copies <paramref name="cast"/>'s scene's clips into the player's "cast" library under their
    /// own names. Returns false, having merged nothing, when the cast has no animation or its
    /// scene cannot supply one.
    private bool MergeClips(GlyphCastAnimation cast)
    {
        if (cast == null || !cast.HasAnimation || _player == null)
            return false;

        if (!cast.Scene.CanInstantiate())
        {
            GD.PushError(
                $"{cast.ResourcePath}: the cast scene '{cast.Scene.ResourcePath}' cannot be " +
                "instantiated, so the cast animation will not play");
            return false;
        }

        Node instance = cast.Scene.Instantiate();
        AnimationPlayer source = GlyphCastAnimation.FindAnimationPlayer(instance);
        if (source == null)
        {
            GD.PushError(
                $"{cast.ResourcePath}: '{cast.Scene.ResourcePath}' holds no AnimationPlayer to " +
                "merge the cast clips from");
            instance.Free();
            return false;
        }

        // The clips go into a separate "cast" library on the main player rather than into the
        // default one: an animation name cannot contain a "/", so the namespace is a library
        // and "cast/<clip>" is the player's own library/animation path -- the same shape the
        // tree's nodes resolve clips by.
        AnimationLibrary library = _player.HasAnimationLibrary(CastLibraryName)
            ? _player.GetAnimationLibrary(CastLibraryName)
            : new AnimationLibrary();
        var names = new System.Collections.Generic.List<string>(ClipNames);
        foreach (string clip in source.GetAnimationList())
        {
            // Both casts merge into the one library, so a clip the earlier cast already brought
            // is skipped rather than re-added: AddAnimation on an existing name is an error.
            if (names.Contains(clip))
                continue;
            library.AddAnimation(clip, source.GetAnimation(clip));
            names.Add(clip);
        }
        if (!_player.HasAnimationLibrary(CastLibraryName))
            _player.AddAnimationLibrary(CastLibraryName, library);
        ClipNames = names.ToArray();
        instance.Free();

        _oneShot.FilterEnabled = true;

        // The cast clip node starts on the fallback so the tree never evaluates an animation
        // node with nothing in it; a cast switches it before it fires. Only the first cast to
        // build seeds it -- a later one must not stomp a clip already switched in.
        StringName fallback = "cast/" + cast.Clip;
        if (_castClipNode != null && _castClipNode.Animation.IsEmpty && _player.HasAnimation(fallback))
            _castClipNode.Animation = fallback;
        return true;
    }

    /// Length of the cast clip a variant key resolves to, in seconds, or 0 when the key names
    /// nothing in the merged library. The arc scaling hangs off it, the same machinery the
    /// jump clips use.
    public float ClipLength(StringName key) => ClipLengthFrom(_techniqueCast, key);

    /// Length of a specific cast's clip for a variant key, in seconds. Split out so an active
    /// cast can ask for its own clip's length without the technique's cast in the way.
    public float ClipLengthFrom(GlyphCastAnimation cast, StringName key)
    {
        if (!Playable || cast == null)
            return 0f;

        StringName clip = cast.ClipFor(key);
        if (clip == null || clip.IsEmpty)
            return 0f;

        StringName merged = "cast/" + clip;
        return _player.HasAnimation(merged) ? (float)_player.GetAnimation(merged).Length : 0f;
    }

    /// Fires the technique's cast: the clip for <paramref name="key"/>, over the bones it names,
    /// for the length it has at <paramref name="scale"/>, then back to locomotion. Returns false
    /// -- and plays nothing -- when there is no cast animation or the resolved clip is not in the
    /// merged library, so a mistyped key fails safe to the locomotion look rather than to an
    /// engine error.
    public bool Play(StringName key, float scale) => PlayFrom(_techniqueCast, key, scale);

    /// Fires a specific cast's clip. The active cast path and the technique path differ only in
    /// which GlyphCastAnimation resolves the key.
    public bool PlayFrom(GlyphCastAnimation cast, StringName key, float scale)
    {
        if (!Playable || cast == null)
            return false;

        StringName clip = cast.ClipFor(key);
        if (clip == null || clip.IsEmpty)
            return false;

        StringName merged = "cast/" + clip;
        if (!_player.HasAnimation(merged))
            return false;

        // The cast clip is switched on the node resource itself, not through a parameter:
        // an AnimationNodeAnimation's animation is not a tree parameter in 4.7, so a
        // parameters/ set is silently dropped and the node would keep playing whatever it
        // was built with. Setting the property runs its setter, which is also what marks
        // the node's cached animation stale so the tree resolves the new clip.
        _castClipNode.Animation = merged;
        _tree.Set($"parameters/{LocomotionGraph.CastSpeedNode}/scale", scale);
        _oneShot.FadeInTime = cast.BlendIn;
        _oneShot.FadeOutTime = cast.BlendOut;

        // The clip's own tracks are the filter, read off the merged animation rather than
        // from a second list: the bones taken over are the bones the clip animates.
        Animation animation = _player.GetAnimation(merged);
        for (int i = 0; i < animation.GetTrackCount(); i++)
            _oneShot.SetFilterPath(animation.TrackGetPath(i), true);

        _tree.Set($"parameters/{LocomotionGraph.CastNode}/request",
            (int)AnimationNodeOneShot.OneShotRequest.Fire);
        _currentClip = clip;
        return true;
    }

    /// Watches the one-shot and clears the cast clip when it hands back, so the next read of
    /// <see cref="CurrentClip"/> says nothing is playing and the next cast can fire.
    public void Update()
    {
        bool active = IsActive;
        if (_wasActive && !active)
            _currentClip = "";
        _wasActive = active;
    }

    /// Cuts the cast immediately, without the fade-out, so a landing -- or anything else that
    /// takes the body back -- does not leave a step pose blending out over the bones.
    public void Abort()
    {
        if (!Playable || !IsActive)
            return;
        _tree.Set($"parameters/{LocomotionGraph.CastNode}/request",
            (int)AnimationNodeOneShot.OneShotRequest.Abort);
        _currentClip = "";
        _wasActive = false;
    }
}
