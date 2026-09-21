# Glyphwake — Docs

Root index for the **Glyphwake** project docs. Project purpose, how the docs are
organized, and where things live.

## Purpose

This is a project to learn the basics of game development and to learn C#. I started it
in Unity and migrated to **Godot 4.7 (C#)** on advice from peers — the skills transfer,
and Godot is open source, which I lean toward whenever possible. These docs describe the
**Godot** project. If a doc still describes Unity (`Assets/`, URP, `Tools > Terrain`,
`CharacterController`), it is stale — see the outdated list below.

## Reading order

| File | What it is |
|------|-----------|
| `design/README.md` | Index of design decision docs |
| `GAME.md` | Game design document (concept, glyphs, world, PvP, roadmap) |
| `PROJECT_TREE.md` | Project tree (verified, Godot layout) |
| `CREDITS.md` | Credits — original idea: **Craig Macomber** |
| `design/Scripts.md` | Script catalogue (reusable vs project-specific) |
| `design/TerrainDecisions.md` | Terrain + water decisions (Terrain3D) |
| `design/PlayerDecisions.md` | Player + camera decisions |
| `design/GlyphDecisions.md` | The glyph/skill data model |
| `future/OUTDATED.md` | **Outdated-file tracker** — lists docs that still describe the old Unity state |
| `future/CURRENT_TODO.md` | Current todo |
| `past/WORKLOG-09-20-2026.md` | Worklog — this session's changes to the docs set |
| `past/WORKLOG.md` | Earlier session log (Unity-era migration log) |

## Decision: outdated-file tracking + worklog convention

To keep the doc set from silently rotting after the Unity → Godot migration, we track
stale files explicitly instead of fixing them in place silently:

- **`future/OUTDATED.md`** is the authoritative list of docs that still describe the old
  Unity state and therefore need updating. When a doc is fixed, it is removed from that
  list — so the list only ever contains genuinely stale files.
- **Completed changes are reported in `docs/past/WORKLOG-mm-dd-yyyy.md`** — one file per
  session, named by the date, describing what changed in each doc. Old worklogs are kept,
  not overwritten.
- **Any update to `future/CURRENT_TODO.md` is always logged in the day's worklog**
  (`docs/past/WORKLOG-mm-dd-yyyy.md`) — the todo is not edited without recording it.
- Migration prompt note: the old `MIGRATION_PROMPT.md` has served its purpose (the
  project is now on Godot) and is no longer referenced here.

See the [session worklog](past/WORKLOG-09-20-2026.md) for what this session changed.

## Current state (verified)

- Godot **4.7**, **C#** (`.NET`), **Forward+** renderer; **Jolt** via `project.godot`;
  Windows renderer is **D3D12**.
- Main scene `res://Scenes/World.tscn`; player `res://Scenes/Player.tscn`
  (`CharacterBody3D` + `move_and_slide()`, gravity manual, first-person camera).
- Terrain: Terrain3D island (`Assets/Terrain/island_assets.tres`), water plane at
  **y = 80** (`Scripts/World/WaterZone.cs`).
- Scripts: C# under `Scripts/` (Player, World, Glyphs) + GDScript learning demo under
  `demo/` + Terrain3D addon under `addons/terrain_3d/`.
- Not tracked here by design: large binary asset pack folders (see `PROJECT_TREE.md`).
