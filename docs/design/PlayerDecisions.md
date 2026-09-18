# Player & Animation — Decisions & Design Notes

Status: first-person movement + camera working; walk/run directional animation and
swimming tooling in place (see `SwimmingDecisions.md` for the water specifics).

## Model
- Model: PolyOne **"Free Pack - Stick Man"**.
  - FBX: `Assets/PolyOne/Free Stickman/Model/Free Pack - Stick Man.fbx`
  - Prefab: `Assets/Free Pack - Stick Man.prefab` (a copy also sits under
    `Assets/PolyOne/Free Stickman/Prefabs/`).
- Hierarchy: the root carries an `Animator` + `Stickman_Controler`; the child mesh
  `SM_StickMan` also has an `Animator` whose **avatar/controller are null**. Always
  fetch the Animator with `GetComponentInChildren<Animator>()`, never the root directly.
- The prefab instance sits at `localPosition.y = -1.07` (mesh offset within the rig).

## Movement
- **WASD** to move, **Space** to jump. Movement is **camera-relative** — you move where
  you look.
- Physics: **CharacterController**, not Rigidbody. Capsule settings: height **2**,
  radius **0.5**, center **(0,0,0)**, slope limit **55**, step offset **0.3**,
  skin width **0.08**.
- Gravity is applied **manually**. Note: `CharacterController.isGrounded` is cleared by
  `Move()`, so read/cache it right after moving (this has bitten the wading logic).
- Script: `Assets/Scripts/PlayerController.cs`.

## Camera (first-person)
- Script: `Assets/Scripts/CameraController.cs`. Mouse look with the **cursor locked**;
  the player body turns to face the look direction, so WASD is view-relative.
- Lens: **near clip 0.3**, **far clip 1000**, and **FOV forced to 70** in `Start`.
- The eye follows the body's *actual* facing (`PlayerController.BodyPitch`), not the raw
  look pitch, so the camera eases between standing/diving instead of snapping.
- Ground/wall handling: `cameraFloorClearance` keeps the eye from clipping the lakebed;
  a sphere-cast from the capsule centre (`CameraPivot` -> eye) is a backstop for walls.
  Full water-camera behaviour is in `SwimmingDecisions.md`.

## Animations
Controller: `Assets/PolyOne/Free Stickman/Animation/Controler/Stickman_Controler.controller`.

Decision: **Walk/Run gaits use 8-way directional blend trees**; **swimming uses a single
symmetric clip** (no directional clips) because a breast stroke reads correctly from every
angle. All of this is set up by the `Tools > Player` menu, in this order:

| Tool | Script | What it does |
|------|--------|--------------|
| Generate Directional Walk Clips | `DirectionalWalkGenerator.cs` | Bakes 8 directional clips into `Assets/PolyOne/Free Stickman/Animation/Directional`, blending the leg channels of `Walk.anim` / `Run.anim` (`CrossOverStrength` 0.35). |
| Set Up Directional Movement | `DirectionalControllerSetup.cs` | Adds `MoveX` / `MoveZ` parameters and the 8-way blend square. |
| Add Idle-Walk-Run Transitions | `StickmanAnimatorSetup.cs` | Adds the `Speed` parameter and Idle -> Walk -> Run transitions (thresholds 0.1 / 6). |
| Set Up Locomotion Transitions | `LocomotionTransitionSetup.cs` | Adds `Speed` + `IsGrounded` parameters and Idle/Walk/Run + `Jumping Up` transitions (thresholds 0.1 / 6). |
| Set Up Swim Animations | `SwimAnimationSetup.cs` | Adds `IsSwimming` / `IsUnderwater` / `SwimSpeed` (default 1), bakes the looping `Swimming Loop.anim`, and wires AnyState -> Swimming -> Idle. |

- Order matters: **generate clips -> directional movement -> transitions -> swim**.
- Source clips available under `Assets/PolyOne/Free Stickman/Animation/`: `Idle`, `Walk`,
  `Run`, `Run Fast`, `Jumping Up`, `Sitting`, `Yelling`, `Swimming`, and the baked
  `Swimming Loop`.
- Known fix: the Idle/Walk/Run states previously had null (`{fileID: 0}`) transitions from
  the old transition tools. These were repaired in the controller, and the tools now clear
  the transition array before destroying so a re-run can't reintroduce them.

## Water interaction
See `SwimmingDecisions.md` for the float / dive / swim design, the camera-in-water rules,
and the tuning knobs.
