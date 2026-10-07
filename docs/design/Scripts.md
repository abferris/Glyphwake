# Scripts — Reuse Guide

Catalogue of every script in this **Godot 4.7 (C#)** project, split into what can travel to
other projects and what is bound to Glyphwake's rig / asset paths. This replaces the old
Unity-era `Scripts.md` (see `OUTDATED.md`).

Legend:
- **Reusable** — another Godot project can use it as-is (only Inspector settings).
- **Reusable (edit paths)** — the technique is generic but paths/names/colors are hardcoded.
- **Project-specific** — tied to the Stickman rig, this controller, or the island scene.

## Summary

| Script | Lang | Kind | Reuse |
|--------|------|------|-------|
| `Scripts/Player/Data/PlayerController.cs` | C# | Runtime (`CharacterBody3D`) | Reusable |
| `Scripts/Player/Data/PlayerResources.cs` | C# | Runtime (`Node`) — resource pools | Reusable |
| `Scripts/Player/Data/PlayerTechniques.cs` | C# | Runtime (`Node`) — technique wiring | Reusable |
| `Scripts/Player/Cameras/CameraController.cs` | C# | Runtime (`Camera3D`) | Reusable |
| `Scripts/World/WaterZone.cs` | C# | Runtime (`Area3D`) | Reusable |
| `Scripts/Core/CollisionLayers.cs` | C# | Static layer/mask constants | Reusable |
| `Scripts/Core/AnimationIds.cs` | C# | Static clip names + direction table | Reusable (must edit) |
| `Scripts/Player/Animation/Movement/PlayerAnimator.cs` | C# | Runtime (`Node`) — picks the clip | Reusable |
| `Scripts/Player/Animation/Movement/LocomotionGraph.cs` | C# | Builds the AnimationTree state machine | Reusable (must edit) |
| `Scripts/Glyphs/Framework/GlyphData.cs` | C# | Data (`Resource`) base | Reusable |
| `Scripts/Glyphs/Framework/GlyphCatalog.cs` | C# | Data (`Resource`) — which glyphs exist | Reusable |
| `Scripts/Glyphs/Framework/GlyphCastAnimation.cs` | C# | Data (`Resource`) — a cast animation as its own scene + clip + directional variants, with a `Validate` | Reusable |
| `Scripts/Glyphs/Framework/GlyphCastVariant.cs` | C# | Data (`Resource`) — one variant (key → clip) + the closed key vocabulary | Reusable |
| `Scripts/Player/Animation/Movement/CastAnimationLayer.cs` | C# | Cast playback as a filter layer in the locomotion tree — cast clips merged into a `cast` library, a one-shot runs the clip over the bones it names | Reusable |
| `Scripts/Glyphs/Framework/GlyphSchool.cs` | C# | Enum | Reusable |
| `Scripts/Glyphs/Framework/GlyphElement.cs` | C# | Enum | Reusable |
| `Scripts/Glyphs/Active/ActiveGlyphData.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Technique/TechniqueGlyphData.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Passive/PassiveGlyphData.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Framework/GlyphTag.cs` | C# | Data (`Resource` tag) | Reusable |
| `Scripts/Glyphs/Framework/GlyphLoadout.cs` | C# | Runtime (`Node`) — player-owned points | Reusable |
| `Scripts/Glyphs/Framework/GlyphLoadoutEntry.cs` | C# | Data (`Resource`) — one glyph + points | Reusable |
| `Scripts/Glyphs/Framework/SelfStatModifier.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Framework/GlyphModifier.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Passive/PassiveTrigger.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Framework/GlyphCost.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Framework/CostResource.cs` | C# | Enum | Reusable |
| `Scripts/Glyphs/Framework/GlyphCastMode.cs` | C# | Enum | Reusable |
| `Scripts/Glyphs/Framework/GlyphEffectMode.cs` | C# | Enum | Reusable |
| `Scripts/Glyphs/Framework/GlyphTargetType.cs` | C# | Enum | Reusable |
| `Scripts/Glyphs/Framework/GlyphAffects.cs` | C# | Flags enum | Reusable |
| `Scripts/Glyphs/Framework/StatValue.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Framework/GlyphScaling.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/Framework/GlyphScalingStyle.cs` | C# | Enum | Reusable |
| `Scripts/Glyphs/Framework/GlyphStats.cs` | C# | Static helper | Reusable |
| `Scripts/Glyphs/Framework/StatKey.cs` | C# | Enum | Reusable |
| `demo/src/*.gd` (Player, Enemy, UI, Camera, ...) | GDScript | Runtime (Godot 4 demo) | Reusable (edit refs) |

## Runtime player + camera (the reusable core)

### `PlayerController.cs` (C#, runtime)
First-person `CharacterBody3D` locomotion — WASD relative to the camera, jump (Space),
manual gravity, sprint. Full swim/wade support driven by `WaterZone`: surface float,
dive (hold look-down), underwater 3D aim, wading. Exposes to the camera:
`IsSwimming`, `IsUnderwater`, `IsWading`, `BodyPitch`, `IsOnFloor`, `FaceDirection`.

Pair with `CameraController` (they read each other) + a `WaterZone`. Uses Godot input
(`Keyboard.current`), so it is a drop-in for any Godot first-person Godot project.

### `PlayerResources.cs` (C#, runtime)
The player's resource pools — what a glyph's `GlyphCost` is paid out of. Mana / health /
stamina, each with a max and the slow passive regeneration that runs at all times (safe
zones, resting and regen passives boost it later). `TrySpend` refuses a cost the pool
cannot pay and refuses negative amounts, so a cost cannot become a refund by accident.
Health and stamina have no spender yet; the pools exist so a cost entry's resource is
enough to reach one when their glyphs arrive.

### `PlayerTechniques.cs` (C#, runtime)
The technique layer: turns points in a `TechniqueGlyphData` into a capability the
locomotion code can ask for. `TryAirJump(airJumpsUsed, normalJumpHeight)` is the atomic
check-pay-compute — trigger, activation threshold, jump budget, cost, spend, height —
returning the height or -1 when nothing fired (a float rather than an out parameter so
the GDScript tests call the same path the body does). The air-jump height curve is the
decade design (see `GlyphDecisions.md`, "Techniques"). One technique at a time; the next
ones get their own export rather than a list with a kind field.

Pair with `GlyphLoadout` + `PlayerResources` as named children of the same body — they
resolve each other by path in `_Ready` (the `PlayerRig` pattern), not by exported node
references.

### `CameraController.cs` (C#, runtime, ~100 lines)
First-person head-anchored camera on the `Player` scene: mouse look (captured cursor),
pitch clamped ±85° (stretched in water so you can look straight down/up to dive), a
spring `_currentLift` that raises the eye above the surface while floating so you can see
the island, and a `Head` bone anchor so the camera stays in front of the model's face.

Depends on: `PlayerController` on the same body (reads `IsSwimming` / `IsUnderwater` /
`BodyPitch` / `DesiredEye` / `CameraPivot`). Copy the pair together.

### `WaterZone.cs` (C#, runtime, ~33 lines)
An `Area3D` trigger zone over the water volume that reports the world-space **surface Y
(`WaterSurfaceY`)** and calls `EnterWater(float)` / `ExitWater()` on entering
`PlayerController`s. Re-asserts on stay, so spawning inside the volume still works.
Drop-in for any Godot controller exposing `EnterWater(float)` / `ExitWater()`.

### `AnimationIds.cs` + `PlayerAnimator.cs` + `LocomotionGraph.cs` (C#, runtime)
The animation pair. `AnimationIds` holds the clip-name constants, `ClipFor(gait, direction)`
(resolves one of 6 ground clips per gait; backward plays the forward clip **reversed**) and
`JumpClipFor(lead foot)` (the forward jump for every direction — direction reads as a body
tilt), and `ReachableClips` — the 18 clips the graph is built from. `PlayerAnimator` holds a
`LocomotionGraph` rather than an `AnimationPlayer` and tells it where to go, so the rules and
the mechanism read separately.

**Reusing these means editing them.** `ReachableClips` must name clips that exist in *your*
`AnimationPlayer` library, and each state is named after its clip. Drop the whole thing into a
project with different clip names and the graph still builds — `AddNode` creates a state whatever
it is called — but the states play nothing. `LocomotionGraph.MissingClips` reports that once up
front, and `tools/test_animation_clips.gd` fails on it, so run that test after swapping clips.

The graph is generated rather than authored (16 states, every state reaching every other), which
means it is **not editable in the AnimationTree dock**. Per-state playback speed is an
`AnimationNodeTimeScale` addressed as `parameters/<state>/Speed/scale`, not `AnimationPlayer.speed_scale`
— the latter is silently ignored once a tree drives the player. `PlayerDecisions.md` has the
measured details.

### `CollisionLayers.cs` (C#, static constants)
The project's 3D physics layers and the two masks that are load-bearing. Layer 1 `World`
(terrain, rocks, trees), 2 `PlayerBody` (the movement capsule), 3 `PlayerHitbox` (reserved for
skeleton-derived combat shapes), 4 `Projectile` (reserved). The names are mirrored in
`project.godot`'s `[layer_names]` so the editor shows the same thing.

Two things to know before reusing it:

- **The capsule's layer and the water zone's mask must change together.** `WaterZone` finds the
  player with `GetOverlappingBodies()`, which matches the zone's mask against the capsule's
  layer. They sit in two different scene files (`Player.tscn`, `World.tscn`), so changing one and
  missing the other turns water entry off with no error anywhere — it presents as a locomotion
  regression, not a config mistake. `tools/test_collision_layers.gd` asserts the pairing at
  runtime.
- **The player masks `World` only.** Derived combat hitboxes (layer 3) must not block movement.
  A future skillshot that forgets to opt into a layer hits terrain rather than players, which is
  the failure you want.

Copy it with the scene-layer pairing intact, or `test_collision_layers.gd` will tell you
immediately if the copy dropped it.

## Glyph / skill data model (runtime, data-only)

Pure `Resource` data plus the player-owned loadout. `Scripts/Glyphs/`. Nothing castable
yet — the technique layer (`PlayerTechniques.cs`) is the first consumer.

| Script | Kind | Reuse |
|--------|------|-------|
| `GlyphData.cs` | Abstract base `Resource`: DisplayName/Description/Icon, `GlyphSchool`, `GlyphElement[]`, `GlyphTag[]`, `GlyphCastAnimation CastAnimation`, `StatValue[]` base stats + `GlyphScaling[]`, the point-budget guideposts, `IsActiveAt` / `StatAt` / `TryStatAt` / `HasElement` / `HasTag` | Reusable |
| `GlyphCastAnimation.cs` | `Resource`: `PackedScene Scene` + `StringName Clip` (the fallback an unknown key resolves to) + `GlyphCastVariant[] Variants` (the directional table, `ClipFor(key)`) + `BlendIn`/`BlendOut`, `HasAnimation`, and a `Validate` that instantiates the scene to confirm it holds the named clip and every variant. Carried as a scene rather than a clip name so `AnimationIds.ReachableClips` stays locomotion-only — see `GlyphDecisions.md` |
| `GlyphCastVariant.cs` | `Resource`: `StringName Key` + `StringName Clip`, one entry in a cast animation's variant table; the closed key vocabulary (`forward_l` … `backward_r`) and `KeyFor(direction, lead foot)` with the gait clips' family folding | Reusable |
| `GlyphSchool.cs` | Enum: Kindling / Warding / Calling / Seeking / Flowing / Shaping | Reusable |
| `GlyphElement.cs` | Enum: None / Inferno / Aqua / Terra / Zephyr / Anima / Lux | Reusable |
| `GlyphTag.cs` | `Resource` free-form tag with a stable `StringName Id`; matching is by `Id`, never resource identity | Reusable |
| `GlyphLoadout.cs` | `Node` (player-owned): `GlyphLoadoutEntry[]` keyed by resource path, `TotalPoints` / `PointsFor` / `IsActive` / `TrySetPoints` against the shared 100-point pool | Reusable |
| `GlyphLoadoutEntry.cs` | `Resource`: one glyph + the points that player put in it | Reusable |
| `ActiveGlyphData.cs` | `Resource`: cast/effect mode, target type + affects, `GlyphCost[]`, `PackedScene Payload`, `PackedScene ImpactPayload`. Numbers (CastTime, Cooldown, Duration, Range) are base stats scaled by its `Scalings` | Reusable |
| `TechniqueGlyphData.cs` | `Resource`: `TechniqueTrigger`, `GlyphCost[]`. A capability, not a castable skill — no hotbar slot, on whenever points are in it; stats inherited from `GlyphData` | Reusable |
| `PassiveGlyphData.cs` | `Resource`: `SelfStatModifier[]`, `GlyphModifier[]`, `PassiveTrigger[]` | Reusable |
| `SelfStatModifier.cs` | `Resource`: `StatKey` + Add/Percent/Multiply + `ValueAt(points)` on the caster's own stat | Reusable |
| `GlyphModifier.cs` | `Resource`: same maths, filtered by schools / elements / tag ids; empty filter means all glyphs | Reusable |
| `PassiveTrigger.cs` | `Resource`: `TriggerEvent`, optional triggering-school filter, `PackedScene Payload`, own `StatValue[]` + `GlyphScaling[]` | Reusable |
| `GlyphCost.cs` | `Resource`: one resource spend — `AmountAt(points)` up front and `PerSecondAt(points)` while a channel runs | Reusable |
| `CostResource.cs` | Enum: Mana / Health / Stamina | Reusable |
| `GlyphCastMode.cs` | Enum: Impulse / Focus / Channel / Ritual (commitment, movement, interruptibility) | Reusable |
| `GlyphEffectMode.cs` | Enum: Instant / Channel / Anchored / OverTime (persistence) | Reusable |
| `GlyphTargetType.cs` | Enum: Self / Single / Projectile / GroundPoint / Direction | Reusable |
| `GlyphAffects.cs` | Flags enum: Enemies / Allies / Self / Terrain | Reusable |
| `StatValue.cs` | `Resource`: one base statistic — `StatKey` + base value. Absence of an entry is how "zero for that mode" is expressed | Reusable |
| `GlyphScaling.cs` | `Resource`: one scaling entry — `StatKey` + `GlyphScalingStyle` + `Value`; growth past activation is defined by the glyph's own entries | Reusable |
| `GlyphScalingStyle.cs` | Enum: Linear / Quadratic / SquareRoot / Step | Reusable |
| `GlyphStats.cs` | Static `StatAt` / `TryStatAt` over base stats + scalings, shared by glyphs and `PassiveTrigger` | Reusable |
| `StatKey.cs` | Enum of every scalable stat, split into the glyph's own numbers (Damage, Radius, Range, ...) and the caster's (MaxHealth, ManaRecovery, ...) | Reusable |

Design notes (see `GlyphDecisions.md`): 1 glyph = 1 skill (active), 1 capability
(technique), or 1 modifier set (passive). The three axes that were missing from the earlier
data model are all separate enums now, because each answers a different question: school is
what the glyph *is*, element is what it is *resisted by*, and target type / affects is what it
*addresses* and who that is *allowed to land on*.

`GlyphData` is immutable and shared: a `.tres` is one object, so allocated points must never
be stored on it. Points live in `GlyphLoadout.cs`, a player-owned loadout keyed by resource
path against the shared 100-point pool.

Effect *execution* is intentionally not here — `ActiveGlyphData.Payload` and
`PassiveTrigger.Payload` name the node to spawn, and the payload's own script decides what it
does. The first authored glyph is `Resources/Glyphs/Techniques/DoubleJump.tres` (glyphs are
grouped by type under `Resources/Glyphs/`); casting (the aim →
spawn pipeline for actives) is still the next layer.

## Demo (GDScript — scratch / learning)

`demo/` holds the pre-migration Godot demo scenes: `demo/src/Player.gd`, `Enemy.gd`,
`UI.gd`, `CameraManager.gd`, `RuntimeNavigationBaker.gd`, `CaveEntrance.gd`,
`CodeGenerated.gd`, `DemoScene.gd`, and `demo/components/` scenes (Player, Enemy, Borders,
Tunnel, UI). These are learning experiments and should **not** be treated as the shipped
game; the current Glyphwake work is the C# runtime above.

## Audit — still usable in Godot? (verified 09-20-2026)

Ground-truth check across **every script on disk** (C# + GDScript) for Unity-era API:
`UnityEngine/UnityEditor`, `CharacterController`/`Rigidbody`, `TerrainData`, URP,
`.unitypackage`/`.prefab`, `Input.GetKey`, `StartCoroutine`, `ScriptableObject`,
`CharacterController`/`Move`, `Assets/` paths, `move_and_slide()` (GDScript-only —
C# uses `MoveAndSlide()`), `Rigidbody` (C# uses `CharacterBody3D`).

**Result:** no Unity markers in any shipped script. Every file uses Godot 4 API.

| Script/group | Lang | Verdict | Why |
|--------------|------|---------|-----|
| `Scripts/Player/Data/PlayerController.cs` | C# | ✅ usable | `CharacterBody3D` + `MoveAndSlide()` (not Rigidbody); move/slide gravity manual |
| `Scripts/Player/Cameras/CameraController.cs` | C# | ✅ usable | `Camera3D` head-anchored mouse look; reads controller swim/wade state |
| `Scripts/World/WaterZone.cs` | C# | ✅ usable | `Area3D` trigger, `WaterSurfaceY = 80`; Enter/Exit water API |
| `Scripts/Glyphs/**` (Framework + Active/Passive/Technique) | C# | ✅ usable | Pure `Resource` data model (not ScriptableObject); `GlyphCatalog.tres` lists them so scenes don't — reusable |
| `tools/*.gd` (build/import/probe/test) | GDScript | ✅ usable | Godot 4 GDScript, `CharacterBody3D`/`Area3D` refs, `Tools >` menus only |
| `demo/src/*.gd` + `demo/components/*.tscn` | GDScript | ✅ usable* | Terrain3D learning demo — *learning scratch, not the shipped runtime* |

Legend: ✅ = verified against disk, Godot-valid. `*` = demo is the Terrain3D learning
demo (`demo/`), deliberately separate from the C# shipped game. No Unity-era API remains.
