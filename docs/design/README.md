# Design Docs — Index

Organized notes for **Glyphwake** (Godot 4.7, C#). These docs live under `docs/design/`.
The high-level game design (world, glyphs, PvP, roadmap) stays in `docs/GAME.md`.

| Doc | Covers |
|-----|--------|
| `TerrainDecisions.md` | Island terrain: Terrain3D tiles, noise height generation, stylized layers, water placement, seam stitching |
| `PlayerDecisions.md` | Player model, first-person movement, camera, walk/run directional animation |
| `GlyphDecisions.md` | The glyph/skill data model: 1 glyph = 1 skill, active vs passive, schools, elements, targeting, 100-point pool, value-per-point scaling |
| `Packages.md` | Asset packs + addons pulled in (what/why + contents) |
| `Scripts.md` | Every script, split into reusable vs project-specific, with the interfaces each needs |
| `ControlsDecisions.md` | Input/aiming, hotkey toolbar, cast styles, crosshair targets, remapping |

Root-level files: `GAME.md` (game design), `PROJECT_TREE.md` (project tree),
`CREDITS.md` (credits), `WORKLOG.md` (session log), `README.md` (purpose + index).

## Project facts
- Godot **4.7**, **C#** (`.NET`), **Forward+** renderer; **Jolt** physics via
  `project.godot`. Windows renderer uses **D3D12**.
- Main scene: `res://Scenes/World.tscn`; player scene: `res://Scenes/Player.tscn`.
- Input: first-person WASD + mouse look (captured cursor); code reads
  `Keyboard.current` / `Mouse.current`.
- Physics: `CharacterBody3D` + `move_and_slide()`; gravity handled manually.
- Art: stylized flat-color low-poly. Flat color / no PBR textures (see `GAME.md`).
- Migration status: project is **already on Godot** (migrated from Unity); this docs set
  now describes the Godot runtime, not the old Unity one. If you diff an older doc that
  still mentions `Assets/`, URP, or `Tools > Terrain`, it is stale — see
  `docs/future/OUTDATED.md` for the outdated list and `docs/past/` for the worklog.

## Conventions
- Decision docs are written as decisions + rationale, not step-by-step tutorials.
- Editor tooling uses Godot editor menus; reusable runtime scripts live under
  `Scripts/` (C#) and `demo/src/` (GDScript learning demo).
