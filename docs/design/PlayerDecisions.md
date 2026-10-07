# Player & Animation — Decisions & Design Notes

Status: first-person movement + camera working; walk/run directional animation and
swimming in place (the swimming design is folded into this file, further below).

## Model
- Model: PolyOne "Free Pack - Stick Man".
  - FBX: `res://Assets/PolyOne/Free Stickman/Model/Free Pack - Stick Man.fbx`
  - Clip manifest: `res://Assets/PolyOne/Free Stickman/Animation/stickman_clips.json`
  - Texture: `res://Assets/PolyOne/Free Stickman/Texture/T_Stickmans_Color.png`
  - The `Assets/` folder is the imported art source inside this Godot project — the name is
    carried over from the Unity days, not a leftover reference to it.
- Hierarchy: the FBX is instantiated by `tools/build_stickman.gd` into `Scenes/Stickman.tscn`
  (do not hand-edit that file). In `Scenes/Player.tscn` it is the `Visual` child, which owns the
  `Skeleton3D`, the `Anim` `AnimationPlayer`, and the `SurfaceSwimPose` `SkeletonModifier3D`. The
  `AnimTree` is a direct child of the player root, pointed at `Visual/Anim`.
- `Visual` sits at `y = 0.7` relative to the body origin.

## Movement
- WASD to move, Space to jump. Movement is camera-relative — you move where
  you look.
- Physics: `CharacterBody3D`, not a rigid body. The capsule is a `CapsuleShape3D` on a
  `CollisionShape3D` — radius **0.2**, height **1.79**, offset `y = 0.006`
  (`Scenes/Player.tscn`). The slope limit is not a shape setting: `PlayerController._Ready` sets
  `FloorMaxAngle` from the `SlopeMaxAngleDeg` knob (**60**), and `SlopeFullSpeedDeg` (**35**) is
  where uphill starts costing speed.
- Gravity is applied manually in `_PhysicsProcess`, and `IsOnFloor()` is read after the move —
  `MoveAndSlide` clears the grounded flag, so reading it earlier reports the previous frame (this
  has bitten the wading logic).
- Scripts: `Scripts/Player/Data/PlayerController.cs` (body), `Scripts/Core/LocomotionState.cs`
  (what it is doing), `Scripts/Core/PlayerRig.cs` (nodes, bones, capsule).

## Camera (first-person)
- Script: `Scripts/Player/Cameras/CameraController.cs`. Mouse look with the cursor locked;
  the player body turns to face the look direction, so WASD is view-relative.
- Lens: `FieldOfView` 70 applied in `_Ready` (the scene's own `fov = 45` is overridden at
  runtime), near clip 0.1 from the scene, and the far clip left at Godot's default. Pitch is
  clamped to `MinPitch`/`MaxPitch` (±85, stretched to ±90 in water). The camera implements
  `ILookSource` and publishes its pitch, so the body reads the camera and nothing reaches back.
- The eye follows the body's *actual* facing (`PlayerController.BodyPitch`), not the raw
  look pitch, so the camera eases between standing/diving instead of snapping.
- Ground/wall handling: `cameraFloorClearance` keeps the eye from clipping the lakebed;
  a sphere-cast from the capsule centre (`CameraPivot` -> eye) is a backstop for walls.
  Full water-camera behaviour is in the Swimming section below.

## Animations
The clip library is **generated**: `tools/build_stickman.gd` imports the PolyOne FBX and writes
`Scenes/Stickman.tscn` (42 clips: the 33 FBX clips, the synthesized `Swim Tread`, and 8
synthesized directional ground jumps) via `ResourceSaver`, and writes the air-step cast clips to
`Scenes/AirStep.tscn` the same way. Never hand-edit either scene — re-run the script.

Decision: locomotion plays **discrete per-direction clips** chosen from an explicit direction
table, and the AnimationTree is a state machine **built in code**. This replaces the old Unity
`.controller` and its five `Tools > Player` setup scripts, none of which exist any more.

| Part | Where | Role |
|------|-------|------|
| Clip names + direction table | `Scripts/Core/AnimationIds.cs` | `ClipFor(gait, direction)` resolves one of 6 ground clips per gait; `JumpClipFor(lead foot)` resolves the forward jump for every direction — direction reads as a body tilt instead; `ReachableClips` is the 18 clips the graph is built from |
| Graph construction | `Scripts/Player/Animation/Movement/LocomotionGraph.cs` | 18 states where every state reaches every other — 306 transitions plus one from `Start` — generated from a uniform rule; optionally wraps the machine with the cast's one-shot |
| What to play | `Scripts/Player/Animation/Movement/PlayerAnimator.cs` | Holds a `LocomotionGraph` rather than an `AnimationPlayer` and tells it where to go, so the rules and the mechanism can be read separately; exposes the gait phase |
| Cast playback | `Scripts/Player/Animation/Movement/CastAnimationLayer.cs` | Plays a glyph's cast animation as a layer in the same tree: clips merged into a `cast` library, a one-shot runs the clip over the bones its tracks name |

- **Backward plays the forward clip in reverse**, with left and right swapped. The five authored
  `Backward` clips stay unused (`BackwardClipsUsed = false`), stated rather than implied: switching
  to them changes how the character looks, and that is a call to make by eye, not in a refactor.
- **Swim uses symmetric clips**, not directional ones — `Swimming Loop` and `Swim Tread`. A breast
  stroke reads correctly from every angle.
- `ReachableClips` is the *reachable* set rather than the whole library, so a state cannot exist for
  a clip the movement code cannot ask for. `Sitting`, `Yelling`, the five `Backward` clips and the
  six non-forward directional jump clips are in the library and deliberately absent (the jump
  clips since 10-06, see the jumping section below).
- **The graph is not editable in the AnimationTree dock.** That is the real cost of generating it.
  The payoff is the next step: replace 16 of these states with two blend spaces, which deletes most
  of those transitions instead of maintaining them.
- **The clip list can drift from the generated library.** `tools/test_animation_clips.gd` compares
  the built graph against the real library, and `LocomotionGraph.MissingClips` reports drift once up
  front instead of one raw engine error per bad name.

### The air-step cast, and the gait phase it reads (10-03, session 5)

The double jump is the first glyph with a working cast animation, and it settles the questions the
attachment work left open:

- **A cast plays as a layer in the same tree, not from a second AnimationPlayer.** A second
  AnimationPlayer writing the same `Skeleton3D` as the locomotion tree is a second writer, and
  which one wins is process order — the two-writer question in `CURRENT_TODO.md`. The answer that
  dissolves the question: the cast's clips are merged into a separate `cast` library on the main
  player, and a `AnimationNodeOneShot` in the tree runs the clip once, fades in and out, and hands
  back. The one-shot's **filters** decide which tracks the cast overrides — set from the clip's own
  track list at cast time — so locomotion keeps playing underneath on every other bone. One writer,
  per-bone takeover, no ordering assumption. Pinned by `tools/test_air_jump_animation.gd`, which
  asserts the locomotion state stays `Jumping Up` while a step is playing.
- **An `AnimationNodeAnimation`'s clip cannot be switched through a parameter.** In Godot 4.7 the
  `animation` property is not a tree parameter, so a `parameters/<node>/animation` set is silently
  dropped and the node keeps playing whatever it was built with — the cast clip node stayed empty,
  the one-shot's shot ended instantly, and nothing fired. The clip is switched on the node resource
  itself (`CastAnimationLayer` holds the reference), which runs the setter and marks the node's
  cached animation stale so the tree resolves the new clip.
- **The gait phase is read back from the tree, not accumulated.** No gait phase existed: the
  locomotion system is discrete with no cycle position exposed. `LocomotionGraph` now exposes
  `PlayPosition`/`PlayLength` (the state machine playback's own position), and `PlayerAnimator`
  wraps it into `GaitPhase` (0..1). A jump off the leading foot continues the stride the walk cycle
  is actually in.
- **The lead foot boundary is measured, not guessed.** The left foot is forward for roughly the
  first half of the stride: 0.03–0.52 of the walk cycle and 0–0.45 of the run, measured by sampling
  the two ankles' positions through the cycles (`tools/probe_walk_phase.gd`). A single boundary
  (`PlayerAnimator.GaitLeadPhase = 0.5`) sits within a hair of both; it is the only thing to move
  if a playtest disagrees.
- **The ground jump leads from the gait; the air jump alternates.** A ground jump latches the
  direction (from held input) and the lead foot (from the gait phase), and clears them on any
  grounded frame — so a fall off a ledge, which is not a jump, keeps the bare `Jumping Up` clip
  through the descent. Standing still has no stride to lead with and keeps `Jumping Up` too. An air
  jump continues the stride: the first step leads with the foot that was *not* leading at takeoff,
  and every jump after alternates from there.
- **Every jump plays the forward clip; direction reads as a body tilt (10-06).** The eight
  directional jump clips (four families × two lead feet) were tried and the non-forward ones read
  as weird rather than as jumps, and the forward one read as marching — so the direction is no
  longer carried by a ground-jump clip at all. On the same pass, playtest showed the same
  problem in the **air-step cast**: the strafe variant abducted the legs sideways and the
  backward one drove them behind, reading as limbs flopping rather than a step. So both the
  ground jumps and the air steps play one forward leap — `JumpClipFor` and the air-step cast
  both take only the lead foot — and the direction shows as a lean of the visual instead:
  `PlayerController` latches the fired input as `_jumpTilt` with the jump (swung to the held
  input on a steered air jump, cleared on any grounded frame), and `UpdateLean` pitches/rolls
  the body `JumpTiltDeg` (12°) toward it at `JumpTiltSpeed` (90°/s) for as long as the body is
  airborne. The sign convention is the swim lean's. The lead-foot alternation is untouched —
  it still picks `Jump Forward L/`Air Step Forward L` vs the R row. The ground clip set shrank:
  the six non-forward jump clips left `ReachableClips` (still in the generated library, just no
  state for them), and the six non-forward air-step variants stay in `DoubleJump.tres`/`AirStep.tscn`
  but are never selected.
- **Eight air-step clips, synthesized, as jumps rather than stair steps.** The air steps are built
  from scratch like the `Swim Tread` synthesizer; the synthesized ground jumps share the same
  **push-off beats** (`_push_beats`): the legs **load** (the plant knee
  bends, the pelvis dips) then **push** (the plant leg extends with the toe down, the lead
  knee reaches its peak **at the same time** -- the thigh to horizontal, the shin tucked
  105° -- and the arms drive up, the arm opposite the lead leg higher). The **pelvis dips and
  rises with the pair** (a root Y track, the run bob's machinery): the leg motion alone never
  moves the body, so the surface being pushed off has to show in the hips -- without it every
  jump read as walking up stairs. The **secondary jumps are strenuous, not casual**: each air
  step has the full jump cycle -- the plant foot **flexes, compresses then pushes up** (the
  raised knee stays folded through the coil -- it never straightens mid-step, which is the
  stair-step read -- then the knee bends deeper as the body sinks and only straightens when
  the leg explodes off the surface), the **pelvis sinks 0.18 m in the coil and rises 0.22 m on
  the push**, the **lead knee snaps up fast** (its peak by 0.2 of the step, holding -- "not
  being fast enough" was the read), the **arms counter-move** (back on the coil, up on the
  push) and the spine curls on the coil. The **chamber itself is fast**: it runs over the front
  fifth of the step (`ASTEP_COIL_START` 0.02, `ASTEP_COIL_SPAN` 0.20) with the push following
  immediately (`ASTEP_PUSH_START` 0.14) -- a jump chambers and fires, it does not load, hold and
  release, and the slow coil was the read ("needs to happen faster").
  **The plant leg's push-off is an explosive extension that overshoots** ("make the pushing down
  leg go faster with more power"). The thigh drops out of horizontal over `ASTEP_DESCENT_SPAN`
  0.30 and the knee fires straight over `ASTEP_PUSH_SPAN` 0.20, both inside the front third, and
  a **`drive` envelope then carries the leg *past* extension**: the thigh 26° into hip
  extension, the knee 8° through straight, the toe 22° through flat. Overshoot is what reads as
  power -- a leg that stops dead at extension has merely arrived at a pose, a leg that snaps
  through it has thrown off the ground. The drive is a **bell that returns**, not a hold, and
  that is structural rather than cosmetic: the clips chain by swapping legs, so a step's plant
  leg *is* the next step's lead leg and the clip's end pose is the next clip's start pose, bone
  for bone; a held overshoot would end the plant leg in hip extension and snap the swap. The
  return eases off instead -- slower out than back (`ASTEP_DRIVE_BIAS` 0.35), so the snap reads
  faster than the relax. Every envelope saturates and returns before the clip ends, so the pose
  the next step chains from does not depend on these timings.
  The air-step arms are the walk's own stroke resampled
  onto the half-cycle whose arm swing matches the leg leading, **amplified around the
  stroke's own mean** (1.6×) -- measured from the rig's T-pose bind pose instead, the
  extrapolation pivots the swing asymmetrically and throws the hands above the head at the
  swing's extremes.
  Numbers: the lead hip 90°/knee 105°, the plant coil knee +20°, the coil curl 8°, the
  pelvis 0.18/0.22 m; the plant leg's drive-through 26°/8°/22°; the beat boundaries
  (`ASTEP_COIL_START` 0.02, `ASTEP_PUSH_START` 0.14, `ASTEP_LEAD_PEAK` 0.2,
  `ASTEP_DRIVE_START` 0.30) and all magnitudes are first-pass tuning to be checked by eye
  (`tools/probe_restyle_check.gd` samples the arcs' key poses so a retune can be read off the
  clips without playing). The structure (four families × two lead feet) is the decision.
- **`AirJumpRedirect` is 0.5** (a 45° swing through a right angle). It was retuned to 0.3 for the
  step-jump pass and reverted the same day at the user's request — the redirect capability stays,
  and the number lives in one obvious place on the body
  (`PlayerController.AirJumpRedirect`, with a marker comment). `tools/test_double_jump.gd`
  reads the expected turn off the body rather than hardcoding it, so the next retune cannot stale
  the test.
- **One step is scaled to the arc it actually flies**, the same `PredictAirTime` machinery the jump
  clips use, so one authored step covers a half-height air jump as well as a doubled one.


### Three measured things about AnimationTree
None of these are guessable, and the first two assumptions made about them were both wrong.
- `AnimationPlayer.speed_scale` is **ignored** once a tree drives it — measured at 1.0, 2.0, 0.5 and
  -1.0, all of which played at 1.0x. Per-state speed is an `AnimationNodeTimeScale` inside each
  state, addressed as `parameters/<state>/Speed/scale`. Measured: 2.0 → 1.88x, 0.5 → 0.505x,
  -1.0 → -1.035x, 0.0 pauses. **Negative is load-bearing** — backward walking is the forward clip in
  reverse, and the jump clip is scaled to the arc it actually flies.
- `AnimationNodeTimeScale.scale` appears in **neither** `get_property_list`, nor the C# bindings, nor
  the class reference. It is registered as an AnimationTree *parameter*, so it has to be found by
  reading the tree's parameter list rather than by looking at the node class.
- `AnimationNodeAnimation.start_offset` is **ignored** unless `use_custom_timeline` is also set, and
  the custom timeline must be set to the clip's *own length* or the clip is time-warped to fit it.
  Measured: `start_offset` alone left the hand pose identical (0.308, 0.809, 0.133); with a
  real-length custom timeline it moved to (0.357, 0.822, 0.09). That is what keeps
  `Walk Diagonal Forward Right` starting halfway through its clip.

### Testing notes
- A driven `AnimationPlayer` reports `current_animation` as `""` and a fixed speed of 1.0, so
  `PlayerController` exposes `AnimationState` / `AnimationSpeed` and the tests read those instead.
- `test_stickman`'s first two stages compare authored poses by driving the `AnimationPlayer`
  directly, which a driven player ignores — so the tree is switched off for those two stages and back
  on once physics starts driving the character.

# Swimming - Decisions & Design Notes

Status: water look done; basic water interaction (float / dive / underwater swim) implemented;
swim clips generated and wired (pending in-editor playtest).

## Steps
1. **Water look** - done: a transparent material on the scene's Water plane, plus a per-camera
   underwater tint (`test_underwater_look`).
2. **Water volume** - built by `tools/build_world.gd`: it removes the solid MeshCollider, turns the
   BoxCollider into a deep trigger whose top face is the surface, and adds `WaterZone` (which records
   the world-space surface Y). Water surface is y = 80.
3. **Swim clips** - generated by `tools/build_stickman.gd` into `Scenes/Stickman.tscn`. The looping
   stroke is a baked clip (`Swimming Loop`), since the source clip has looping off and would
   otherwise play once and freeze; playback speed is driven by the time-scale parameter described
   under [Three measured things about AnimationTree](#three-measured-things-about-animationtree).

## Swimming mechanics decisions (from earlier design)
- Swim lookup: player enters/traverses the water the same way as walking — first-person
  movement relative to the camera, with WASD + diagonals for 8-way directional travel.
- Surface swimming: player floats at the water surface; WASD moves camera-relative around the
  surface. No "directional" animation needed at the surface (just symmetric breast-stroke).
- Underwater: player moves fully camera-relative in 3D - use the camera's pitch to aim. Look
  down = dive deeper, look up = surface. Horizontal WASD + camera yaw for lateral swimming.
- Breast stroke (symmetric) is the anim to use underwater; NOT crawl. It plays the one
  symmetric `Swimming Loop` clip for every direction, sped up while actively stroking
  (`swimVigorousSpeed`) so movement reads as vigorous and idle stays calm.
- Underwater the whole body rotates to follow the camera (pitch + yaw), so swimming down
  looks like a dive. At the surface the body stays upright and only yaws.
- The first-person camera is anchored to the body's *actual* facing (PlayerController.BodyPitch),
  not the raw look pitch. The lens therefore eases in front of the face as you look down to
  dive (no snap between surface/submerged formulas, and it never cuts through the crown).
  `bodyPitchSpeed` controls how quickly that dive-in transition plays.
- The eye never clips through the lakebed. Because the body pitches underwater, the head (and the
  eye, `faceReach` out from the face) swings well outside the standing collision capsule, so the
  CharacterController can't keep the lens out of the floor on its own. Rather than collide the
  camera, the body simply isn't allowed to get that close: each frame PlayerController mirrors
  the camera's eye and raycasts down beneath it; if the eye is within `cameraFloorClearance` of
  the ground, the body is pushed straight up until it clears. The camera also has a sphere-cast
  probe (`CameraPivot` -> eye) as a backstop for walls; water triggers are ignored either way.

## Surface lean & head (Session 4)
NOTE: supersedes the earlier "at the surface the body stays upright and only yaws" note above.
- At the surface the *body* leans, not just yaws: pressing W pitches the body forward up to
  `maxSwimForwardPitchDeg` (40) and strafing rolls it up to `maxSwimStrafeRollDeg` (45), both
  eased with `swimLeanSpeed`. **Vertical camera aim no longer rotates the model** — only
  horizontal yaw does (the camera-pitch `lookDown` coupling was removed).
- The lean is rotated about the `Head` bone (`_visual.Position = headInBody − R·headPivot`),
  so the head keeps its world position while the body swings below it. This is the failed
  Attempt C pivot, now completed by a head leveler (below).
- A `SkeletonModifier3D` (`Scripts/Player/Animation/Movement/SurfaceSwimPose.cs`, node `Visual/Skeleton3D/
  SurfaceSwimPose`) cancels the lean on the `Head` bone each pass by writing the live
  world-level pose `playerBasis · flipY · headBonePose` back with `SetBoneGlobalPose`
  (NOT the deprecated `SetBoneGlobalPoseOverride` — see WORKLOG Session 4). Skeleton3D rolls
  the modified pose back after skinning, so the write never accumulates. The head stays level
  and faces forward while the body pitches/rolls below — forward swim stays head-first, strafe
  tilt doesn't submerge the head.
- Consequence: `SimulateSwim`'s surface float no longer needs the `headDip` lift; it floats the
  body origin so the head sits `surfaceHeadHeight` above the water while idle/level.

## Implementation notes
- WaterZone is a trigger volume; it calls PlayerController.EnterWater/ExitWater and reports
  waterSurfaceY. It re-asserts on stay, so spawning inside the volume still works.
- PlayerController decides surface vs. submerged from the actual camera eye's depth below the
  surface (with hysteresis). It uses the camera transform, not the head bone: the body pitches
  with the look, so looking up lays the body back and drops the head bone even after your eye
  has broken the surface. Using the real eye means swimming up while looking up switches to the
  surface camera as soon as the eye clears the water. Surface = camera-yaw-relative stroking
  plus a damped spring holding the
  body at the float line; looking down while pressing W dives. Submerged = full 3D camera-aimed
  movement (camera pitch aims up/down). Standing on the lakebed with your head above water is
  treated as wading at a reduced speed.
- Water shallow enough to stand in (`wadeDepth`) stays wading even while airborne, so jumping
  while wading keeps ground movement, the walk/jump animation, and the normal camera. Without
  this a wade-jump left the ground for a frame, flipped to the surface float (swim pose +
  `swimCameraLift`), then flipped back on landing - a visible pop.
- Swim does NOT use directional clips: the symmetric breast stroke reads correctly from every
  angle, so a single looping clip is used. (The Walk/Run gaits use discrete per-direction clips
  from the direction table in `AnimationIds.ClipFor`.)
- The old Unity transition tools destroyed states before clearing, leaving null (`{fileID: 0}`)
  transitions on Idle/Walk/Run. That is Unity-only history and does not recur here: the graph is
  generated whole, and `test_animation_clips.gd` asserts the state names are distinct, so two
  reachable clips renaming into the same name would be caught.

## Tuning knobs
All on `PlayerController` (`Scripts/Player/Data/PlayerController.cs`) unless noted. There is no
`Swimming` header in the Inspector — the swim fields are a contiguous `[Export]` block after
`AirJumpRedirect`, each documented by a prose comment above it in the source. `swimCameraLift` and
the `collision*` camera fields are on `CameraController`.

| Field | Purpose |
|---|---|
| swimSpeed | underwater stroke speed |
| surfaceSwimSpeed | horizontal speed while floating at the surface (normal walk speed; pitch-independent) |
| surfaceHeadHeight | how far the head floats above the waterline when idle |
| swimCameraLift (CameraController) | extra camera height while floating at the surface, so the eyeline clears the water. Not applied while wading; it gives way only once you look down past ~10 deg to dive (so floating / surfacing always restores it) and drops with no lag so the crown never shows |
| surfaceSpring / surfaceDamping | how firmly the body holds the float line (more damping = less bob) |
| diveDelay | how long you hold forward + look-down before a surface dive begins |
| submergedThreshold / surfaceHysteresis | when the eye counts as underwater, and the anti-flicker gap |
| maxSwimVerticalSpeed | cap on dive / climb speed |
| wadeSpeedFactor | slow-down while wading through shallow water |
| wadeDepth | water depth above the lakebed below which it always counts as wading (keeps a wade-jump from popping into the swim pose / camera lift) |
| swimVigorousSpeed | swim-stroke playback multiplier while actively moving (1 = idle pace) |
| bodyPitchSpeed | how fast the body pitches to follow the camera when underwater (higher = the dive-in view catches up faster) |
| cameraFloorClearance | minimum gap kept between the underwater eye and the lakebed; the body is pushed up to hold it (raise if the lens still grazes the floor) |
| groundMask | layers treated as the lakebed for the floor-clearance check |
| collisionRadius / collisionSkin / minCameraDistance / collisionMask (CameraController) | wall backstop: the eye's sphere-cast probe from the capsule centre (keep radius >= the 0.3 camera near clip) |

