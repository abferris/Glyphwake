# Project Worklog — Glyphwake

Documentation of work done so far on this Unity project. Last updated: 2026-09-17. This was all before the migration to godot, and the initiation of git.

## Project Facts
- Unity 6.6 (6000.6.0f1), URP.
- Project path: `C:\Projects\My project\` (note the space).
- **New Input System only** — legacy `Input.*` throws. Player code uses `Keyboard.current.` / `Mouse.current.`.
- Unity log lives at `Logs/Editor.log` (project-relative).
- CharacterController `isGrounded` is cleared by any `Move()` — snapshot it at the top of `Update()`.

## What We've Built So Far

### Player + Camera
- `Assets/Scripts/PlayerController.cs` — third-person movement (WASD), rotate with mouse, jump with space, gravity via `CharacterController`.
- `Assets/Scripts/CameraController.cs` — follow camera with mouse (horizontal/vertical), zoom on mouse wheel.
- `Assets/Scripts/Editor/PlacePlayerWindow.cs` — **Tools > Place Player at Coordinates** window: enter X/Z, it positions the player on the terrain surface.

### Island Generator (auto-generated multi-tile terrain)
- `Assets/Scripts/Editor/IslandGenerator.cs` + `Assets/Scripts/Editor/IslandGeneratorWindow.cs` — **Tools > Island Generator...** window.
  - Generates a 4x4 grid of 250x250 terrain tiles sized/wrapped around a center point.
  - Height based on: island radius, distance from center, sea-floor depth, water level, island height, roughness/random seed, shoreline + inland curvature.
  - Runtime sizes quick summary: template `heightmapResolution=513`, tiles named `Terrain (r, c)`.
- Fixed a major seam bug: **Unity heightmap arrays are indexed `[y,x]` (first index = Z, second = X)**. Generator now reads `oldHeights[j,i]` and writes `newHeights[j,i] = rel[i,j]` instead of transposing every tile.
- Generator diagnostics added:
  - Tile-grid dump (each tile's name, position, resolution, size) on every run.
  - Duplicate-tile cleanup: if two Terrains share the same grid slot, extras are destroyed and their TerrainData assets deleted.
  - Border audit (`AuditBorders`): reports worst shared-edge height deviation in meters.
- `EnsureBeigeMaterial()`: creates `Assets/Materials/TerrainBeige.mat` + a beige checker texture and assigns it to every tile (URP Terrain/Lit with fallback to Nature/Terrain/Standard).

### Seam Stitcher (hand-sculpting helper)
- `Assets/Scripts/Editor/StitchTerrainWindow.cs` — **Tools > Terrain Seam Stitch...**.
  - Idea: instead of smoothing each shared edge one side at a time (which can break the other side), it reads all tiles, averages every shared edge and corner at once, writes them all back, and can repeat (iterations 1–5).
  - Can run on all Terrains in the scene or just the selection.
  - Logs max border deviation in meters before and after.

### Terrain Layers (flat-color, stylized)
- `Assets/Scripts/Editor/CreateTerrainLayers.cs` — **Tools > Create Stylized Terrain Layers**.
  - Creates 4 flat-color TerrainLayers under `Assets/Materials/TerrainLayers/`: Grass, Sand, Dirt, Rock.
  - Auto-adds Grass to the selected terrain.
  - **NOTE: not run yet** — `Assets/Materials/` currently only contains `TerrainBeige.png`; the `TerrainLayers/` folder does not exist yet. Until it's run, the "Add Layer" list in Paint Texture will be empty.

### Imported Asset Packs
- `SimpleNaturePack_2020.3_SRP_v1.24.unitypackage` and `NatureAssets.unitypackage` copied into the project root, then imported:
  - `Assets/SimpleNaturePack/` — Models + Prefabs (tree_01–05, bush, grass, rock_01–05, mushroom, branch, flowers), texture atlas.
  - `Assets/Squared Snails Studios/3D Low-Poly Nature Pack/` — OakTree/Pine/BluePine/Poplar/SmallSpruce FBX trees, stone1–10 FBX, mushrooms, clouds.
- These packs are 3D models only (no terrain ground brushes). For painting land color we use the flat-color TerrainLayers from the tool above.
- Pack materials are 2020 built-in SRP — may appear pink until the URP converter is run if they use shaders that don't exist.

### Manual (hand) island building — current direction
- Abandoned the auto generator for the island itself; currently sculpting terrain by hand.
- Terrain tiles hand-created: Heightmap Resolution 513, size 250x250, edge-to-edge at multiples of 250, all assigned **Grouping ID = 1** so adjacent tiles render continuous.
- Water plane added manually (Plane, positioned at water height, URP transparent blue material).

## Important Gotchas (learned the hard way)
- **Terrain tiles render continuous via Grouping ID, but each tile owns its own heightmap** — painting/smoothing one tile does NOT affect its neighbor; stitch with the Seam Stitch tool or smooth both sides.
- Seam mismatch was NOT caused by roughness/shoreline variability/inland variability — it was the heightmap transposition bug above.
- Paint Texture "Add Layer" shows nothing until at least one TerrainLayer asset exists.
- TerrainLayer colors come from a **Base Map texture**, not a color picker.
- Don't delete terrain assets blindly: the scene references specific TerrainData (e.g. `IslandTerrain.asset`, guid `ee125dfd4b5607e45a0cc311736271cd`) — verify references before deleting or you lose the island geometry (and Unity can respawn duplicate `TerrainData_*.asset` files).

## Design, Naming & Migration Prep (2026-09-17)

### Glyph system (docs-first, in `Assets/Docs/GlyphDecisions.md`)
- Renamed **Rune → Glyph** everywhere: folder `Assets/Scripts/Runes/` → `Assets/Scripts/Glyphs/`; files `GlyphData.cs`, `ActiveGlyphData.cs`, `PassiveGlyphData.cs`, `GlyphTag.cs` (`.meta` renamed, GUIDs preserved); identifiers `GlyphData` / `GlyphCategory` / `GlyphTag` / `ActiveGlyphData` / `PassiveGlyphData`; `CreateAssetMenu` now `Glyphs/...`; `RunesDecisions.md` → `GlyphDecisions.md`. Left `"RuneScape-like"` (GAME.md) and third-party `PT_Runes_02.png`.
- Documented the passive model: targets **Self / Spell / Element / School** (combinable as filters); kinds **Modifier** (always-on stat/effect) and **Technique** (mana-driven action on an existing input). Modifier stacking = **flat → percent (percents add) → multiply**; `PassiveModifier` still needs a percent operation.
- Documented **mana as neutral, elementless essence**: all actives cost per cast, basic attack free, channels/techniques drain while held, slow regen + safe-zone refill, a lockout channel spell for fast refill, a few Anima spells spend health instead.
- Status effects (slow/burning/dazed) live on spells, not passives. Passives are strictly positive (no drawbacks).

### Naming
- Chose the game name **Glyphwake**. Docs updated: `README.md`, `GAME.md` (title + working tagline), `WORKLOG.md`, `Assets/Docs/README.md`, `Assets/Docs/Scripts.md`.
- Availability so far: no game/trademark hit found and `glyphwake.com` does not resolve; official checks (USPTO/EUIPO, registrar, Steam page) still to do.

### Credits
- Added `CREDITS.md`: **original game idea by Craig Macomber**. Also a `## Credits` section in `GAME.md` and a link in `README.md`. Must appear in in-game/store/trailer/marketing credits and survive migration.

### Migration prep
- Saved `MIGRATION_PROMPT.md` (Unity → Godot 4): class mapping table, file inventory, canonical glyph/mana rules, and a clause to preserve `CREDITS.md` / Craig Macomber. Linked from `README.md`.
- Project stays on Unity for now; rename folder `My project/` → `Glyphwake/` during the migration.

## Suggested Next Steps
1. Run **Tools > Create Stylized Terrain Layers** (creates Grass/Sand/Dirt/Rock), then paint terrain with them.
2. Run **Tools > Terrain Seam Stitch...** after sculpting/painting to re-align shared borders.
3. If imported materials look pink: run URP converter.
4. Spawn player in the scene, paint trees/rocks using the imported prefabs, polish water material, lighting/fog.
5. Resume paused glyph design: elemental **combo table**, **resistance depth** (flat vs weaknesses/counters), and the mana-refill **Channel** spell name/school.
6. When ready, run the `MIGRATION_PROMPT.md` port to Godot 4 (renaming the folder to `Glyphwake`).