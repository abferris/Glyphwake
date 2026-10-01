using System.Collections.Generic;
using Godot;

namespace Glyphwake.Player;

/// One reachable clip, and how far into it its state should start playing.
public readonly struct GraphClip
{
    /// The clip's name in the AnimationLibrary. This is also the state name, so that the
    /// AnimationTree reports the same strings the AnimationPlayer used to -- the GDScript
    /// tests compare against clip names, and keeping the two identical means the tree can be
    /// introduced without rewriting what those tests assert.
    public readonly string Name;

    /// Where to start within the clip, as a fraction of its length. Always zero: a start offset
    /// on an AnimationNodeAnimation needs a custom timeline, and a custom timeline fed the
    /// clip's own length plus a non-looping node played the clip once and then held it --
    /// forward-right and backwards-left both froze halfway through. A state machine can only
    /// enter a state at its start anyway, so an offset there buys nothing the transition
    /// crossfade does not already smooth over.
    public GraphClip(string name)
    {
        Name = name;
    }
}

/// The character's AnimationTree.
///
/// This is a flat state machine with one state per reachable clip, and every state able to
/// reach every other. That looks wasteful next to a hand-authored graph, and it is: 16 states
/// means 240 transitions. It is also the honest description of what the code did before,
/// which was <c>AnimationPlayer.Play(anyClip, blend)</c> from any clip to any other. Rebuilding
/// it as a generated uniform rule keeps that behaviour identical and, more usefully, makes the
/// graph replaceable: the next step is to collapse the sixteen ground states into two blend
/// spaces, which deletes most of these transitions rather than maintaining them.
///
/// Every state is the same three-node shape -- clip, then a time scale, then out -- for one
/// reason: a state machine cannot vary playback speed per state on its own, and the
/// AnimationPlayer's own SpeedScale is ignored once a tree is driving it. The time scale node
/// is what makes the jump-clip scaling and the backwards walk reversal survive the move.
///
/// None of this is editable in the AnimationTree dock. That is the trade for generating it: at
/// 240 transitions a hand-authored resource is unreviewable, and the graph that replaces this
/// one is a small number of blend spaces rather than a large number of transitions.
public sealed class LocomotionGraph
{
    /// The state machine's implicit entry node.
    public const string StartNode = "Start";

    /// Key of the time-scale node inside every state.
    public const string SpeedNode = "Speed";

    /// Key of the clip node inside every state.
    public const string ClipNode = "clip";

    private AnimationTree _tree;
    private AnimationNodeStateMachinePlayback _playback;
    private readonly Dictionary<string, string> _speedParams = new();
    private readonly AnimationPlayer _player;

    /// The state the graph has been asked to play. This is tracked here rather than read back
    /// from the tree because the tree also reports a node *during* a crossfade, and the tests
    /// want the state that was chosen, not the one mid-blend.
    public string CurrentState { get; private set; } = "";

    /// False when there is no tree or no playback, in which case every call here is a no-op
    /// and the character animates nothing rather than throwing.
    public bool IsValid => _playback != null;

    public LocomotionGraph(AnimationPlayer player)
    {
        _player = player;
    }

    /// Length of a clip in seconds, or 0 when the library has no such clip.
    public double ClipLength(string name)
    {
        if (_player == null)
            return 0.0;
        Animation anim = _player.GetAnimation(name);
        return anim?.Length ?? 0.0;
    }

    /// Loop mode of a clip in the library, or linear when the library has no such clip.
    ///
    /// An AnimationNodeAnimation's own loop mode wins over the clip's once it has been set, and
    /// it defaults to None, so leaving it alone makes looping clips play exactly once and then
    /// hold their last pose. The clip resource knows the truth, so read it from there.
    public Animation.LoopModeEnum LoopModeFor(string name)
    {
        if (_player == null)
            return Animation.LoopModeEnum.Linear;
        return _player.GetAnimation(name)?.LoopMode ?? Animation.LoopModeEnum.Linear;
    }

    /// Builds the state machine and starts it on the first clip.
    ///
    /// <paramref name="blend"/> and <paramref name="treadBlend"/> are the ordinary and
    /// prone-water crossfade times. Prone treaded water is a large pose change, so a transition
    /// that touches <paramref name="treadClip"/> gets the longer one -- the same distinction the
    /// old code made when it chose its blend time.
    public void Build(
        AnimationTree tree,
        IReadOnlyList<GraphClip> clips,
        float blend,
        float treadBlend,
        string treadClip)
    {
        if (tree == null || clips == null || clips.Count == 0)
            return;

        _tree = tree;
        _speedParams.Clear();

        var machine = new AnimationNodeStateMachine();
        for (int i = 0; i < clips.Count; i++)
        {
            machine.AddNode(
                clips[i].Name,
                BuildState(clips[i]),
                // Laid out on a grid purely so the generated graph is readable if it is ever
                // opened in the editor.
                new Vector2(200f + (i % 4) * 190f, 100f + (i / 4) * 90f));
            _speedParams[clips[i].Name] = $"parameters/{clips[i].Name}/{SpeedNode}/scale";
        }

        for (int from = 0; from < clips.Count; from++)
        for (int to = 0; to < clips.Count; to++)
        {
            if (from == to)
                continue;
            machine.AddTransition(
                clips[from].Name,
                clips[to].Name,
                new AnimationNodeStateMachineTransition
                {
                    XfadeTime = CrossfadeFor(clips[from].Name, clips[to].Name, blend, treadBlend, treadClip),
                    SwitchMode = AnimationNodeStateMachineTransition.SwitchModeEnum.Immediate,
                    // Play() restarted the clip every time it was called, so every transition
                    // restarts its destination rather than resuming partway through.
                    Reset = true,
                });
        }

        machine.AddTransition(
            StartNode,
            clips[0].Name,
            new AnimationNodeStateMachineTransition
            {
                XfadeTime = 0f,
                SwitchMode = AnimationNodeStateMachineTransition.SwitchModeEnum.Immediate,
                Reset = true,
            });

        _tree.TreeRoot = machine;
        _tree.Active = true;

        _playback = _tree.Get("parameters/playback").As<AnimationNodeStateMachinePlayback>();
        if (_playback == null)
            return;

        _playback.Start(clips[0].Name, true);
        CurrentState = clips[0].Name;
    }

    /// Moves to <paramref name="state"/> and sets how fast that state plays.
    ///
    /// The speed is written for the *incoming* state before the transition, so the new clip
    /// never spends a frame at the previous state's rate. Re-selecting the state that is
    /// already playing only updates the speed, matching the old code, which did not restart a
    /// clip that was already playing.
    public void TravelTo(string state, float speed)
    {
        if (_playback == null)
            return;

        if (_speedParams.TryGetValue(state, out string param))
            _tree.Set(param, speed);

        if (state == CurrentState)
            return;

        _playback.Travel(state);
        CurrentState = state;
    }

    private static float CrossfadeFor(string from, string to, float blend, float treadBlend, string treadClip)
        => from == treadClip || to == treadClip ? treadBlend : blend;

    private AnimationNodeBlendTree BuildState(in GraphClip clip)
    {
        var anim = new AnimationNodeAnimation { Animation = clip.Name, LoopMode = LoopModeFor(clip.Name) };

        var state = new AnimationNodeBlendTree();
        state.AddNode(ClipNode, anim, new Vector2(0f, 0f));
        state.AddNode(SpeedNode, new AnimationNodeTimeScale(), new Vector2(220f, 0f));
        state.ConnectNode(SpeedNode, 0, ClipNode);
        state.ConnectNode("output", 0, SpeedNode);
        return state;
    }
}
