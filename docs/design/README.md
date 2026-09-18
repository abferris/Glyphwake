# Design Docs — Index

Organized notes for **Glyphwake**. Design docs live here
(`Assets/Docs/`) for now; this location may change later. The high-level game design
(world, glyphs, PvP, roadmap) stays in the root `GAME.md`.

| Doc | Covers |
|-----|--------|
| `TerrainDecisions.md` | Island terrain: tiles, seam stitching, painted layers, water placement, player placement |
| `PlayerDecisions.md` | Player model, first-person movement, camera, walk/run directional animation |
| `SwimmingDecisions.md` | Water interaction: float / dive / underwater swim, water camera, tuning knobs |
| `ControlsDecisions.md` | Input/aiming options (hold-right-click vs always-look), swappable aim point, hotkey bars + scroll-wheel hotkey sets, totem placement, smart/click-cast, where skill remapping happens |
| `GlyphDecisions.md` | Glyph/skill data model: 1 glyph = 1 skill, active vs passive, targeting / cast time / effect time, schools of magic, elements, 0-points-inactive activation, value-per-point scaling |
| `Packages.md` | Unity packages (`manifest.json`) and the imported asset packs (what/why + contents) |
| `Scripts.md` | Every script, split into reusable vs project-specific, with the interfaces each needs |

Root-level files: `GAME.md` (game design), `WORKLOG.md` (session log), `README.md`
(purpose), `PROJECT_TREE.md` (project tree).

## Project facts
- Unity **6000.6.0f1**, **URP 17.6.0**.
- Input: **New Input System only** (legacy `Input.*` throws).
- Physics: `CharacterController`, not Rigidbody; gravity applied manually.
- Art: stylized flat-color low-poly. Realistic/PBR textures rejected.
- Code rule: do **not** use `[Obsolete]` Unity APIs (e.g. `FindObjectsOfType`); use the
  current replacements (`FindObjectsByType<T>()`, etc.). This is enforced by the global
  opencode skill `unity-deprecated-apis`.

## Conventions
- Decision docs are written as decisions + rationale, not step-by-step tutorials.
- Editor tooling is grouped by menu: `Tools > Terrain > ...`, `Tools > Player > ...`,
  `Tools > Assets > ...` (grouping is set in code via `[MenuItem]`, not by folder).
