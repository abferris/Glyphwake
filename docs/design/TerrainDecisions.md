# Terrain — Decisions & Design Notes

Status: island exists as editable terrain tiles; layers + water volume tooling in place.
This file covers how the terrain is built/edited (the "mapping" work). Water
*interaction* is covered separately in `SwimmingDecisions.md`.

## World scale / layout
- One island, roughly a 300 m radius, with terrain rising to about 169 m and a sea
  floor about 20 m below sea level around the edges (see `GAME.md`).
- The terrains are lifted so their base sits at **y = 50**; the water plane is at
  **y = 55**, which is what reads as sea level in the scene.

## How the terrain is made (history + decision)
- It was originally produced by an automatic island generator
  (`IslandGenerator.cs` + `IslandGeneratorWindow.cs`, menu `Tools > Island Generator...`).
  That built a **4x4 grid of 250x250 tiles** with `heightmapResolution = 513`.
  The generator and its window have since been **deleted**.
- **Decision:** the island is now kept as authored/editable terrain tiles rather than
  regenerated on demand. The tiles live under `Assets/Terrain/` as `Tile_*.asset`
  (`TerrainData`) — currently **391 tile assets**.
- The old generator had a seam bug caused by `[y, x]` indexing of the tile grid, which is
  why a dedicated stitch tool exists (below).
- Cleanup note: there are also **48 `TerrainData_*.asset` files loose at the `Assets/`
  root** plus a few `New Terrain*.asset` / `NewBrush*.brush` / `NewLayer*.terrainlayer`
  scratch assets. These are older/scratch data and are not referenced by the scene.

## Seam stitching
- Menu: `Tools > Terrain > Terrain Seam Stitch...` (`Scripts/Editor/StitchTerrainWindow.cs`).
- It smooths the shared edges of neighbouring tiles so heights line up, so the seams
  are invisible from above.
- Options: **1–5 iterations**; run on **all terrains** or the current **selection**.
- Tiles must share a matching heightmap resolution and size, otherwise they are skipped
  with a warning in the Console.
- Run it after any height edits that cross a tile boundary. 1–3 iterations is usually
  enough; more iterations smear more of the surrounding height into the seam.

## Surface painting (layers)
- Menu: `Tools > Terrain > Create Stylized Terrain Layers`
  (`Scripts/Editor/CreateTerrainLayers.cs`).
- It creates four **flat-color URP/Lit** materials in `Assets/Materials/TerrainLayers`:

  | Layer | Color (RGB)          |
  |-------|----------------------|
  | Grass | 0.42, 0.62, 0.32     |
  | Sand  | 0.82, 0.75, 0.55     |
  | Dirt  | 0.52, 0.40, 0.28     |
  | Rock  | 0.45, 0.44, 0.42     |

- Flat colors (no textures) are deliberate — they match the low-poly art style, where
  realistic/PBR textures are rejected as too detailed (see `GAME.md`).
- Paint them with Unity's terrain **Paint Texture** tool. The `NewLayer*.terrainlayer`
  assets loose at the `Assets/` root are scratch, not the real set.
- The old `WORKLOG.md` said these layers had not been created; they now exist, so that
  note is out of date.

## Water placement / volume
- The water is the scene's **`Water` plane** with a transparent teal URP/Lit material at
  **y = 55**. Per current direction the material must **not** be altered.
- Menu: `Tools > Terrain > Set Up Water Zone`
  (`Scripts/Editor/SwimSetupTool.cs`). Run it **once**, then **save the scene**.
  It removes the solid `MeshCollider`, turns the `BoxCollider` into a deep trigger
  (200 world units) whose top face is the surface, and adds the `WaterZone` component
  that records the world-space surface Y.
- Menu location note: this used to be under `Tools > Player`; it now lives under
  `Tools > Terrain` so all terrain setup is together.

## Player placement
- Menu: `Tools > Place Player at Coordinates...`
  (`Scripts/Editor/PlacePlayerWindow.cs`).
- Finds the object named **`Player`** and drops it onto the terrain at the typed X/Z
  using `Terrain.SampleHeight`, so you can spawn at a landmark without flying there.

## Gotchas
- Terrains are all at base **y = 50**; the water surface is **y = 55**; the player spawns
  at approximately **(50, 59.62, -1025)**.
- A tile and its `.meta` file are large (~549 KB each). Do not enumerate the whole
  `Assets/Terrain/` folder in logs; see `PROJECT_TREE.md` for the summarized listing.
