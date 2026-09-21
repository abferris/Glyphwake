# Terrain — Decisions & Design Notes

Status: island exists as a **Terrain3D** island, generated from a noise heightmap with
stylized flat-color layers and a water volume. This file covers how terrain is built/edited
(the "mapping" work). Water *interaction* is covered separately in `ControlsDecisions.md`.

World-space facts come from `Scenes/World.tscn` (Godot 4.7, C#):

| Thing | Value |
|-------|-------|
| Terrain node | `Terrain3D` (from the `terrain_3d` addon) |
| Terrain assets | `res://Assets/Terrain/island_assets.tres` |
| Terrain data dir | `res://Assets/Terrain/island_data` |
| Terrain size | one 9000×9000 region, `vertex_spacing = 1.953125` |
| Water surface | a `MeshInstance3D` plane at **y = 80** (teal transparent Standard material) |
| Water volume | `WaterZone` `Area3D` (script `Scripts/World/WaterZone.cs`) at y = 80 |
| Player spawn | `Scenes/Player.tscn`, spawned at ~(1000, 88, -1130) |

This replaces the old Unity-era terrain file (which described `Assets/Terrain/`,
`TerrainData` tile assets, and Unity menu tools) — that project is gone. See
`docs/future/OUTDATED.md` and `docs/past/WORKLOG-09-20-2026.md`.

## How the terrain is made (history + decision)
- The island was originally authored with a custom Unity island generator built from a
  4×4 grid of 250×250 terrain tiles, which had a `[y, x]` seam bug. That project was
  migrated to Godot and the terrain was rebuilt here as a **single Terrain3D island**.
- **Decision:** terrain is now a single Terrain3D node authored in the Godot editor (and
  via the `demo/` Terrain3D scenes), stored as heightmap data under
  `Assets/Terrain/island_data` with a region config in `island_assets.tres`.
- Because it's one continuous region instead of tiled `TerrainData`, the old tile **seam
  stitching** problem no longer applies. Heightmap and LOD are handled by Terrain3D.

## Surface painting (layers / materials)
- Terrain3D paints depth/height/color onto the island using **maps** generated from
  sub-resources in `island_assets.tres`: a `FastNoiseLite` height noise, a `Gradient`
  color ramp, and a `NoiseTexture2D` for macro variation.
- The look is flat layers of beige/earth tones — deliberately **flat color, no PBR
  textures**, matching the low-poly art style (see `GAME.md`).
- Terrain material: `Terrain3DMaterial` via the addon's autoshader; texture maps are
  baked/buildable with the addon's importer (`Tools > Terrain3D`).

## Water placement / volume
- The water is the scene's **`Water`** `MeshInstance3D` plane at **y = 80** with a
  transparent teal `StandardMaterial3D`. The material should **not** be altered.
- Script: `Scripts/World/WaterZone.cs` — an `Area3D` trigger zone over the water volume.
  It reports the world-space **surface Y (`WaterSurfaceY = 80.0`)** and calls
  `EnterWater(float)` / `ExitWater()` on entering `PlayerController`s, re-asserting on
  stay so spawning inside the volume still works.
- Water interaction (swimming, diving, wading) is driven by the player controller — see
  `PlayerDecisions.md` and `ControlsDecisions.md`.

## Player placement
- The player is `res://Scenes/Player.tscn` (a `CharacterBody3D` with `PlayerController`
  + head-anchored `CameraController`), instance-placed in `World.tscn` at roughly
  (1000, 88, -1130). Start in the editor by opening `Scenes/World.tscn` and pressing
  **Play**. Editor tool scripts in `Scripts/Editor/` (if present) handle authoring-only
  helpers; runtime movement/camera/swim live in `Scripts/Player/` / `Scripts/World/`.

## Gotchas
- The old docs wrote water at **y = 55** and player at y ≈ 59.6 — those numbers were from
  the Unity scene. The Godot scene uses the water plane at **y = 80** and the player
  spawning above it at y ≈ 88cars.
- Terrain region+data files live under `Assets/Terrain/` (see `PROJECT_TREE.md`);
  `demo/` holds the Terrain3D learning demo (nodes, navigation, baking).
