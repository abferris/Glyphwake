# Scripts — Reuse Guide

Catalogue of every script written for this project, split into what can travel to other
projects and what is bound to Glyphwake's rig/asset paths.

Legend:
- **Reusable** — another Unity project can use it as-is (only Inspector settings).
- **Reusable (edit paths)** — the technique is general but paths/names/colors are hardcoded.
- **Project-specific** — tied to the Stickman rig, this controller, or the castle kit.

## Summary

| Script | Kind | Menu | Reuse |
|--------|------|------|-------|
| `PlayerController.cs` | Runtime | — | Reusable |
| `CameraController.cs` | Runtime | — | Reusable |
| `WaterZone.cs` | Runtime | — | Reusable |
| `StitchTerrainWindow.cs` | Editor | `Tools > Terrain > Terrain Seam Stitch...` | Reusable |
| `PlacePlayerWindow.cs` | Editor | `Tools > Place Player at Coordinates...` | Reusable |
| `SwimSetupTool.cs` | Editor | `Tools > Terrain > Set Up Water Zone` | Reusable (edit paths) |
| `CreateTerrainLayers.cs` | Editor | `Tools > Terrain > Create Stylized Terrain Layers` | Reusable (edit paths) |
| `LocomotionTransitionSetup.cs` | Editor | `Tools > Player > Set Up Locomotion Transitions` | Reusable (edit paths) |
| `DirectionalControllerSetup.cs` | Editor | `Tools > Player > Set Up Directional Movement` | Project-specific |
| `DirectionalWalkGenerator.cs` | Editor | `Tools > Player > Generate Directional Walk Clips` | Project-specific |
| `StickmanAnimatorSetup.cs` | Editor | `Tools > Player > Add Idle-Walk-Run Transitions` | Project-specific |
| `SwimAnimationSetup.cs` | Editor | `Tools > Player > Set Up Swim Animations` | Project-specific |
| `CastleKitImporter.cs` | Editor | `Tools > Assets > Import Kenney Castle Kit` | Project-specific |

## Glyph / skill data model (runtime, data-only)

Pure `ScriptableObject` data — nothing castable or executable yet. `Assets/Scripts/Glyphs/`.

| Script | Kind | Reuse |
|--------|------|-------|
| `GlyphData.cs` | Base SO + `GlyphCategory` enum | Reusable |
| `ActiveGlyphData.cs` | SO: cast style, mana/cast/cooldown scaling, `ScaledStat` list | Reusable |
| `PassiveGlyphData.cs` | SO + `PassiveModifier` struct (tag-filtered additive/multiplier) | Reusable |
| `GlyphTag.cs` | SO: school/element classification tags (passives match on these) | Reusable |
| `ScaledStat.cs` | Serializable `key + baseValue + perPoint`; exactly the numbers the allocation UI prints | Reusable |
| `StatKey.cs` | Enum of every scalable stat (damage, radius, mana cost, speed, ...) | Reusable |

Reuse notes: 1 glyph = 1 skill (actives) or a modifier set (passives). Effect *execution*
is intentionally not here — the next layer consumes these assets for casting and
point allocation.

---

## Reusable

### `PlayerController.cs` (runtime, 376 lines)
First-person `CharacterController` locomotion with jump, sprint, and full swim/wade:
surface float (damped spring), dive, 3D underwater aim, wading, and a floor-clearance
clamp so the eye never clips the lakebed.

Depends on: `CameraController` (found on `Camera.main`), `WaterZone` (calls
`EnterWater`/`ExitWater`), and an `Animator` reached via `GetComponentInChildren`.

Animator interface it drives — rename these params or change the strings to reuse:
`Speed` (float), `MoveX`/`MoveZ` (float), `IsGrounded` (bool), `IsSwimming` (bool),
`IsUnderwater` (bool), `SwimSpeed` (float).

Reuse notes: pair with `CameraController` (they read each other) and `WaterZone` (or a
collider that calls the same methods). Uses the **New Input System** (`Keyboard.current`)
directly, so it is not a drop-in for a legacy-input project. Tuning lives in the
"Swimming" Inspector header — see `SwimmingDecisions.md`.

### `CameraController.cs` (runtime, 172 lines)
First-person head-anchored camera: mouse look via an Input System action (`<Mouse>/delta`,
which avoids the locked-cursor drift of raw `Mouse.current.delta`), auto-locks the cursor,
auto-finds the humanoid Head bone, and eases a `swimCameraLift` while floating at the
surface. A sphere-cast from the capsule centre is a wall backstop.

Depends on: `PlayerController` on `target` (calls `FaceDirection`, reads `BodyPitch`,
`IsSwimming`, `IsUnderwater`, `IsWading`, `CameraPivot`, `DesiredEye`). The two scripts are a
**pair** — copy them together. Generic enough for any first-person game once `target` is set.

### `WaterZone.cs` (runtime, 80 lines)
A trigger volume that marks water and reports its world-space surface Y. Requires a
`Collider` (auto-set to trigger) + kinematic `Rigidbody`; re-asserts on stay so spawning
inside the volume still works; has a `Snap Surface To Collider Top` context menu and scene
gizmos.

Depends on: a `PlayerController` in the entering collider's hierarchy. Drop-in for any
project whose controller exposes `EnterWater(float)` / `ExitWater()`.

### `StitchTerrainWindow.cs` (editor, 182 lines)
Matches the shared edges/corners of adjacent Terrain tiles (read all -> average seams ->
write all) with 1–5 iterations, on all terrains or the selection. Reports max border
deviation before/after in metres. Tile neighbours are inferred from tile size, so it works
on any grid of equal-sized terrains.

Reuse notes: fully generic multi-tile terrain tool. Requires all target terrains to share
heightmap resolution and X/Z size (it errors clearly if not).

### `PlacePlayerWindow.cs` (editor, 78 lines)
Finds an object by name (default `Player`) and drops it on the terrain at typed world X/Z
using `Terrain.SampleHeight`, offsetting by the `CharacterController.height` so it spawns
standing. Generic editor helper — drop-in.

---

## Reusable (edit paths)

### `SwimSetupTool.cs` (editor, 80 lines)
One-shot scene setup that turns the `Water` plane into a swimmable volume: removes the
solid `MeshCollider`, builds a deep (200 world-unit) trigger `BoxCollider` whose top face is
the surface, adds a kinematic `Rigidbody` + `WaterZone`, and records `waterSurfaceY`. Undo-
aware and safe to re-run.

To reuse elsewhere: generalize the `"Water"` object name and the 200-unit depth (currently
constants), and ship it with `WaterZone.cs`. Everything else is generic.

### `CreateTerrainLayers.cs` (editor, 80 lines)
Generates four flat-color `TerrainLayer` assets (Grass / Sand / Dirt / Rock) in
`Assets/Materials/TerrainLayers`, each backed by a 4×4 flat PNG, and adds the Grass layer to
the active/first terrain.

The palette and output folder are hardcoded to Glyphwake's look. The **technique**
(build a 1-color texture -> `TerrainLayer` -> assigned to the terrain) is the reusable part;
edit the `CreateLayer` calls for another game's palette.

### `LocomotionTransitionSetup.cs` (editor, 127 lines)
Wires `Idle <-> Walk <-> Run` by the `Speed` parameter (thresholds 0.1 / 6) plus
`Idle/Walk/Run -> Jumping Up` on `IsGrounded == false`, and repairs null transition slots by
clearing the array before destroying (the bug that previously corrupted the controller).

Reuse notes: the **pattern** is generic for any `Speed`/`IsGrounded` locomotion rig; only
the hardcoded `ControllerPath` and the state names `Idle`/`Walk`/`Run`/`Jumping Up` tie it to
the Stickman controller. Parameterizing the path + state names would make it fully reusable.

---

## Project-specific

These are built around this project's Stickman rig, its controller at
`Assets/PolyOne/Free Stickman/Animation/Controler/Stickman_Controler.controller`, the
PolyOne clip paths, or the Kenney castle source. Copying them to another project needs real
edits (paths, bone/muscle channel names, state names).

### `DirectionalWalkGenerator.cs` (editor, 229 lines)
Bakes 8 directional walk/run/swim clips by rotating the four thigh channels of the source
gait and re-writing them, with a cross-over bias so the far leg steps over the planted one.
Hardset to the PolyOne clips and to Unity's humanoid muscle channel names
(`Left/Right Upper Leg Front-Back` / `In-Out`).

Reusable core: the channel-rotation algorithm. Not reusable as-is.

### `DirectionalControllerSetup.cs` (editor, 107 lines)
Builds the `SimpleDirectional2D` blend trees for the `Walk` and `Run` states on `MoveX`/
`MoveZ`, loading the generated clips. Calls `DirectionalWalkGenerator.Generate()` first.
Hardcoded to the Stickman controller, state names, and clip filenames.

### `StickmanAnimatorSetup.cs` (editor, 90 lines)
Adds `Idle <-> Walk <-> Run` by `Speed`. **Largely superseded by
`LocomotionTransitionSetup.cs`**, which does the same plus the jump transition — keeping both
is redundant; consider retiring this one (or keeping it only for a jump-less rig).

### `SwimAnimationSetup.cs` (editor, 172 lines)
Adds the `IsSwimming` / `IsUnderwater` / `SwimSpeed` (default 1) parameters, bakes the looping
`Swimming Loop.anim` from the one-shot `Swimming.anim`, and wires `AnyState -> Swimming` and
`Swimming -> Idle`. Hardcoded to the Stickman controller and clip paths. The "bake a looping
copy and drive speed via a parameter" technique is portable.

### `CastleKitImporter.cs` (editor, 336 lines)
Splits Kenney's combined SketchUp OBJ into one mesh + prefab per logical piece (159 groups
-> 71 pieces), recenters each on its footprint, and creates 11 URP/Lit materials from the
`.mtl`. Hardcoded to `Assets/KenneyCastleKit` source/paths and the castle's material names.
The OBJ group-splitting + recentering logic could be generalized into a reusable importer.

---

## Suggested follow-up
Nothing is physically reorganized yet — the split above is documentation only. The clean
move would be folders `Assets/Scripts/Reusable/` and `Assets/Scripts/Project/` (or promoting
the reusable set to a local UPM package), then parameterizing the hardcoded paths in
`SwimSetupTool`, `CreateTerrainLayers`, and `LocomotionTransitionSetup` so they graduate out
of "edit paths".
