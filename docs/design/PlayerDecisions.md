# Player & Animation — Decisions & Design Notes

Status: first-person movement + camera working; walk/run directional animation and
swimming tooling in place (see `SwimmingDecisions.md` for the water specifics).

## Model
- Model: PolyOne "Free Pack - Stick Man".
  - FBX: `Assets/PolyOne/Free Stickman/Model/Free Pack - Stick Man.fbx`
  - Prefab: `Assets/Free Pack - Stick Man.prefab` (a copy also sits under
    `Assets/PolyOne/Free Stickman/Prefabs/`).
- Hierarchy: the root carries an `Animator` + `Stickman_Controler`; the child mesh
  `SM_StickMan` also has an `Animator` whose avatar/controller are null. Always
  fetch the Animator with `GetComponentInChildren<Animator>()`, never the root directly.
- The prefab instance sits at `localPosition.y = -1.07` (mesh offset within the rig).

## Movement
- WASD to move, Space to jump. Movement is camera-relative — you move where
  you look.
- Physics: CharacterController, not Rigidbody. Capsule settings: height 2,
  radius 0.5, center (0,0,0), slope limit 55, step offset 0.3,
  skin width 0.08.
- Gravity is applied manually. Note: `CharacterController.isGrounded` is cleared by
  `Move()`, so read/cache it right after moving (this has bitten the wading logic).
- Script: `Assets/Scripts/PlayerController.cs`.

## Camera (first-person)
- Script: `Assets/Scripts/CameraController.cs`. Mouse look with the cursor locked;
  the player body turns to face the look direction, so WASD is view-relative.
- Lens: near clip 0.3, far clip 1000, and FOV forced to 70 in `Start`.
- The eye follows the body's *actual* facing (`PlayerController.BodyPitch`), not the raw
  look pitch, so the camera eases between standing/diving instead of snapping.
- Ground/wall handling: `cameraFloorClearance` keeps the eye from clipping the lakebed;
  a sphere-cast from the capsule centre (`CameraPivot` -> eye) is a backstop for walls.
  Full water-camera behaviour is in `SwimmingDecisions.md`.

## Animations
Controller: `Assets/PolyOne/Free Stickman/Animation/Controler/Stickman_Controler.controller`.

Decision: Walk/Run gaits use 8-way directional blend trees; swimming uses a single
symmetric clip (no directional clips) because a breast stroke reads correctly from every
angle. All of this is set up by the `Tools > Player` menu, in this order:

| Tool | Script | What it does |
|------|--------|--------------|
| Generate Directional Walk Clips | `DirectionalWalkGenerator.cs` | Bakes 8 directional clips into `Assets/PolyOne/Free Stickman/Animation/Directional`, blending the leg channels of `Walk.anim` / `Run.anim` (`CrossOverStrength` 0.35). |
| Set Up Directional Movement | `DirectionalControllerSetup.cs` | Adds `MoveX` / `MoveZ` parameters and the 8-way blend square. |
| Add Idle-Walk-Run Transitions | `StickmanAnimatorSetup.cs` | Adds the `Speed` parameter and Idle -> Walk -> Run transitions (thresholds 0.1 / 6). |
| Set Up Locomotion Transitions | `LocomotionTransitionSetup.cs` | Adds `Speed` + `IsGrounded` parameters and Idle/Walk/Run + `Jumping Up` transitions (thresholds 0.1 / 6). |
| Set Up Swim Animations | `SwimAnimationSetup.cs` | Adds `IsSwimming` / `IsUnderwater` / `SwimSpeed` (default 1), bakes the looping `Swimming Loop.anim`, and wires AnyState -> Swimming -> Idle. |

- Order matters: generate clips -> directional movement -> transitions -> swim.
- Source clips available under `Assets/PolyOne/Free Stickman/Animation/`: `Idle`, `Walk`,
  `Run`, `Run Fast`, `Jumping Up`, `Sitting`, `Yelling`, `Swimming`, and the baked
  `Swimming Loop`.
- Known fix: the Idle/Walk/Run states previously had null (`{fileID: 0}`) transitions from
  the old transition tools. These were repaired in the controller, and the tools now clear
  the transition array before destroying so a re-run can't reintroduce them.

# Swimming - Decisions & Design Notes

Status: water look done; basic water interaction (float / dive / underwater swim) implemented;
swim animations wired via tooling (pending in-editor playtest).

## Steps
1. **Water look** - done: a URP/Lit transparent material on the scene's Water plane. (The
   project runs URP 17.6, so built-in-RP water shaders do not work here.)
2. **Water volume** - run `Tools > Terrain > Set Up Water Zone` once, then save the scene. It
   removes the solid MeshCollider, turns the BoxCollider into a deep trigger whose top face is
   the surface, and adds WaterZone (which records the world-space surface Y).
3. **Swim animations** - run `Tools > Player > Set Up Swim Animations`: it adds the
   `IsSwimming` / `IsUnderwater` / `SwimSpeed` params, bakes a looping `Swimming Loop.anim`
   from the one-shot `Swimming.anim` (the source has Loop Time off, so it plays once and
   freezes), puts it on the `Swimming` state (playback speed driven by `SwimSpeed`), and
   wires AnyState -> Swimming (`IsSwimming`) / Swimming -> Idle.

## Swimming mechanics decisions (from earlier design)
- Swim lookup: player enters/traverses the water the same way as walking — first-person
  movement relative to the camera, with WASD + diagonals for 8-way directional travel.
- Surface swimming: player floats at the water surface; WASD moves camera-relative around the
  surface. No "directional" animation needed at the surface (just symmetric breast-stroke).
- Underwater: player moves fully camera-relative in 3D - use the camera's pitch to aim. Look
  down = dive deeper, look up = surface. Horizontal WASD + camera yaw for lateral swimming.
- Breast stroke (symmetric) is the anim to use underwater; NOT crawl. It plays the one
  symmetric `Swimming.anim` for every direction, sped up while actively stroking
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
  angle, so a single looping clip is used. (The Walk/Run gaits still use the 8-way blend trees
  built by DirectionalWalkGenerator.)
- The `Idle`/`Walk`/`Run` states had null ({fileID: 0}) transitions (the old transition tools
  destroyed before clearing). Repaired in `Stickman_Controler.controller`; the tools now clear
  the array before destroying so a re-run cannot null them again.

## Tuning knobs (PlayerController, "Swimming" header in the Inspector)
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

