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
`Scenes/Stickman.tscn` (34 clips) via `ResourceSaver`. Never hand-edit that scene — re-run the
script.

Decision: locomotion plays **discrete per-direction clips** chosen from an explicit direction
table, and the AnimationTree is a state machine **built in code**. This replaces the old Unity
`.controller` and its five `Tools > Player` setup scripts, none of which exist any more.

| Part | Where | Role |
|------|-------|------|
| Clip names + direction table | `Scripts/Core/AnimationIds.cs` | `ClipFor(gait, direction)` resolves one of 6 ground clips per gait; `ReachableClips` is the 16 clips the graph is built from |
| Graph construction | `Scripts/Player/Animation/Movement/LocomotionGraph.cs` | 16 states where every state reaches every other — 240 transitions plus one from `Start` — generated from a uniform rule |
| What to play | `Scripts/Player/Animation/Movement/PlayerAnimator.cs` | Holds a `LocomotionGraph` rather than an `AnimationPlayer` and tells it where to go, so the rules and the mechanism can be read separately |

- **Backward plays the forward clip in reverse**, with left and right swapped. The five authored
  `Backward` clips stay unused (`BackwardClipsUsed = false`), stated rather than implied: switching
  to them changes how the character looks, and that is a call to make by eye, not in a refactor.
- **Swim uses symmetric clips**, not directional ones — `Swimming Loop` and `Swim Tread`. A breast
  stroke reads correctly from every angle.
- `ReachableClips` is the *reachable* set rather than the whole library, so a state cannot exist for
  a clip the movement code cannot ask for. `Sitting`, `Yelling` and the five `Backward` clips are in
  the library and deliberately absent.
- **The graph is not editable in the AnimationTree dock.** That is the real cost of generating it.
  The payoff is the next step: replace 16 of these states with two blend spaces, which deletes most
  of those transitions instead of maintaining them.
- **The clip list can drift from the generated library.** `tools/test_animation_clips.gd` compares
  the built graph against the real library, and `LocomotionGraph.MissingClips` reports drift once up
  front instead of one raw engine error per bad name.

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

