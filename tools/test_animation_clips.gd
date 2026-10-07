extends SceneTree

## The animation graph must not name a clip that does not exist.
##
## LocomotionGraph.Build names each AnimationTree state after the clip it plays
## (LocomotionGraph.cs:118), and PlayerController builds that graph from
## AnimationIds.ReachableClips. So the built state machine *is* ReachableClips, reflected at
## runtime -- which is how this reads it without reaching a C# static (GDScript cannot access
## static members on a CSharpScript).
##
## Why it matters: the drift is silent in two places at once. AddNode creates a state whatever
## the name is, so a renamed clip still yields a full-looking graph, and LoopModeFor falls back
## to Linear on a null GetAnimation (LocomotionGraph.cs:93) rather than complaining. Nothing
## reports it; locomotion just stops playing that state. AnimationIds.cs:20 records exactly
## that having happened once.
##
## The clips themselves are generated -- build_stickman.gd writes Scenes/Stickman.tscn from the
## PolyOne FBX -- so this also catches the generator and the C# constants disagreeing.
##
## Clips in the library that no state names are reported, not failed: AnimationIds.cs
## documents Sitting, Yelling, the five Backward clips and the six non-forward directional
## jump clips as deliberately unreachable -- walking backwards plays the forward clip
## reversed, and every jump plays the forward clip with the body tilting instead (10-06).

const PLAYER := "res://Scenes/Player.tscn"
const ANIM_PLAYER_PATH := "Visual/Anim"
const ANIM_TREE_PATH := "AnimTree"

var phase := 0
var ticks := 0
var failed := false
var player: Node
var anim_player: AnimationPlayer
var machine: AnimationRootNode


func fail(msg: String) -> void:
	printerr("FAIL: " + msg)
	failed = true


func expect(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func _initialize() -> void:
	# Deferred, then polled: adding during _initialize races the loader on a scene this big.
	player = (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
	if player == null:
		printerr("FAIL: ", PLAYER, " did not instantiate")
		quit(1)
		return
	root.call_deferred("add_child", player)


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks < 3:
		return false

	if phase == 0:
		if not player.is_inside_tree():
			return false
		anim_player = player.get_node_or_null(ANIM_PLAYER_PATH) as AnimationPlayer
		expect(anim_player != null, "no AnimationPlayer at " + ANIM_PLAYER_PATH)
		if anim_player == null:
			verdict()
			return true

		var tree := player.get_node_or_null(ANIM_TREE_PATH) as AnimationTree
		expect(tree != null, "no AnimationTree at " + ANIM_TREE_PATH)
		if tree != null:
			machine = tree.tree_root
			# The tree root is a blend tree when the technique has a cast animation in it, and
			# the state machine sits under its "Locomotion" node; unwrap so the checks below
			# still read the machine.
			if machine is AnimationNodeBlendTree and (machine as AnimationNodeBlendTree).has_node("Locomotion"):
				machine = (machine as AnimationNodeBlendTree).get_node("Locomotion")
			expect(machine != null, "the AnimationTree has no state machine root; was the graph built?")
		phase = 1
		return false

	if phase == 1:
		check_states()
		verdict()
		return true

	return false


func check_states() -> void:
	var clips: PackedStringArray = anim_player.get_animation_list()
	expect(clips.size() > 0, "the AnimationPlayer has no clips at all")
	expect(machine != null, "nothing to check")
	if machine == null or clips.is_empty():
		return

	var states: PackedStringArray = machine.get_node_list()
	expect(states.size() > 0, "the state machine has no states, so the graph was never built")
	print("graph states: ", states.size(), "   library clips: ", clips.size())

	# The guard: every state the movement code can enter must name a clip that exists.
	#
	# Start and End are skipped: AnimationNodeStateMachine creates them as virtual entry/exit
	# nodes, so they appear in get_node_list() but are not clips. They are also reserved, which
	# is why a real clip must never be called Start or End -- hence the check below.
	var missing: Array[String] = []
	for state in states:
		if state == "Start" or state == "End":
			continue
		if not clips.has(state):
			missing.append(state)
	expect(missing.is_empty(),
		"%d animation state(s) name a clip the library does not have -- locomotion would silently play nothing: %s"
			% [missing.size(), ", ".join(missing)])

	# The state machine reserves these two names, so a reachable clip using either could never
	# get a state of its own.
	for reserved in ["Start", "End"]:
		expect(not clips.has(reserved),
			"the library has a clip named '%s', which the state machine reserves as a virtual node" % reserved)

	# A rename that collides with another reachable clip would collapse two states into one and
	# the counts would still look right, so check the states are distinct.
	var distinct := {}
	for state in states:
		distinct[state] = true
	expect(distinct.size() == states.size(),
		"the graph has duplicate state names (%d states, %d distinct): two reachable clips resolved to the same name"
			% [states.size(), distinct.size()])

	# Reported, never failed: the deliberate exclusions.
	var unused: Array[String] = []
	for clip in clips:
		if states.has(clip):
			continue
		if clip != "Start" and clip != "End":
			unused.append(clip)
	print("library clips no state names (documented as deliberate): ", unused.size())


func verdict() -> void:
	print("TEST ANIMATION CLIPS ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)