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
| `Scripts/Player/PlayerController.cs` | C# | Runtime (`CharacterBody3D`) | Reusable |
| `Scripts/Player/CameraController.cs` | C# | Runtime (`Camera3D`) | Reusable |
| `Scripts/World/WaterZone.cs` | C# | Runtime (`Area3D`) | Reusable |
| `Scripts/Glyphs/GlyphData.cs` | C# | Data (`Resource`) + enums | Reusable |
| `Scripts/Glyphs/ActiveGlyphData.cs` | C# | Data (`Resource`) + `CastStyle` | Reusable |
| `Scripts/Glyphs/PassiveGlyphData.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/GlyphTag.cs` | C# | Data (`Resource` tag) | Reusable |
| `Scripts/Glyphs/PassiveModifier.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/ScaledStat.cs` | C# | Data (`Resource`) | Reusable |
| `Scripts/Glyphs/StatKey.cs` | C# | Enum | Reusable |
| `demo/src/*.gd` (Player, Enemy, UI, Camera, ...) | GDScript | Runtime (Godot 4 demo) | Reusable (edit refs) |

## Runtime player + camera (the reusable core)

### `PlayerController.cs` (C#, runtime)
First-person `CharacterBody3D` locomotion — WASD relative to the camera, jump (Space),
manual gravity, sprint. Full swim/wade support driven by `WaterZone`: surface float,
dive (hold look-down), underwater 3D aim, wading. Exposes to the camera:
`IsSwimming`, `IsUnderwater`, `IsWading`, `BodyPitch`, `IsOnFloor`, `FaceDirection`.

Pair with `CameraController` (they read each other) + a `WaterZone`. Uses Godot input
(`Keyboard.current`), so it is a drop-in for any Godot first-person Godot project.

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

## Glyph / skill data model (runtime, data-only)

Pure `Resource` data — nothing castable or executable yet. `Scripts/Glyphs/`.

| Script | Kind | Reuse |
|--------|------|-------|
| `GlyphData.cs` | Base `Resource` + `GlyphCategory` enum (Capability / Movement / Utility / Attack / Summoning) | Reusable |
| `ActiveGlyphData.cs` | `Resource`: cast style, mana/cast/cooldown scaling, `ScaledStat` list | Reusable |
| `PassiveGlyphData.cs` | `Resource`: `Array<PassiveModifier>` | Reusable |
| `GlyphTag.cs` | `Resource`: school/element classification tag (passives match on these) | Reusable |
| `PassiveModifier.cs` | `Resource`: tag-filtered additive/multiplier modifier | Reusable |
| `ScaledStat.cs` | `Resource`: `key + baseValue + perPoint` scaling | Reusable |
| `StatKey.cs` | Enum of every scalable stat (Damage, Radius, ManaCost, CastTime, Cooldown, ...) | Reusable |

Design notes (see `GlyphDecisions.md`): 1 glyph = 1 skill (actives) or a modifier set
(passives). Effect *execution* is intentionally not here — the next layer consumes these
assets for casting and point allocation.

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
| `Scripts/Player/PlayerController.cs` | C# | ✅ usable | `CharacterBody3D` + `MoveAndSlide()` (not Rigidbody); move/slide gravity manual |
| `Scripts/Player/CameraController.cs` | C# | ✅ usable | `Camera3D` head-anchored mouse look; reads controller swim/wade state |
| `Scripts/World/WaterZone.cs` | C# | ✅ usable | `Area3D` trigger, `WaterSurfaceY = 80`; Enter/Exit water API |
| `Scripts/Glyphs/*.cs` (8 data files) | C# | ✅ usable | Pure `Resource` data model (not ScriptableObject) — reusable |
| `tools/*.gd` (build/import/probe/test) | GDScript | ✅ usable | Godot 4 GDScript, `CharacterBody3D`/`Area3D` refs, `Tools >` menus only |
| `demo/src/*.gd` + `demo/components/*.tscn` | GDScript | ✅ usable* | Terrain3D learning demo — *learning scratch, not the shipped runtime* |

Legend: ✅ = verified against disk, Godot-valid. `*` = demo is the Terrain3D learning
demo (`demo/`), deliberately separate from the C# shipped game. No Unity-era API remains.
