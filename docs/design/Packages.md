# Packages & Asset Packs

Inventory of what is in the project, why, and what each pack contains.

The project is **Godot 4.7** with the **C# (.NET) build**, Forward+ renderer
(`project.godot`: `config/features=PackedStringArray("4.7", "C#", "Forward Plus")`).

> Rewritten from the Unity inventory. Everything Unity-specific has been removed, and the
> `Assets/` folder name is carried over from Unity — it is the imported art source *inside* this
> Godot project, not a leftover reference to the old one.

## Engine + addons

| Component | Version | Use |
|-----------|---------|-----|
| Godot | 4.7 (.NET) | Renderer is Forward+ |
| C# / .NET | — | All runtime code under `Scripts/` |
| `addons/terrain_3d` | 1.0.2 | Terrain3D — the island is a single region, no tiles to stitch |

There is no input-plugin story to record: Godot's own input map is the only one, and the C# reads
`Keyboard`/`Mouse` through it.

## Asset packs

Counts are models (`.fbx` / `.obj`) and textures actually present on disk. **In use** means a
scene or build tool reads the pack; the rest are vendored source art, kept for later and currently
referenced by nothing.

| Pack | Path | Models | Textures | Status |
|------|------|-------:|---------:|--------|
| PolyOne — Free Stickman | `Assets/PolyOne/Free Stickman/` | 2 | 1 | **In use** — the player |
| Terrain3D island | `Assets/Terrain/` | — | — | **In use** — the island |
| ithappy — Fantasy_FREE | `Assets/ithappy/Fantasy_FREE/` | 41 | 1 | Vendored, unused |
| EmaceArt — Slavic World Free | `Assets/EmaceArt/Slavic World Free/` | 213 | 12 | Vendored, unused |
| SimpleNaturePack | `Assets/SimpleNaturePack/` | 24 | 1 | Vendored, unused |
| Squared Snails — 3D Low-Poly Nature | `Assets/Squared Snails Studios/3D Low-Poly Nature Pack/` | 47 | 5 | Vendored, unused |
| Polytope Studio — Lowpoly | `Assets/Polytope Studio/` | 30 | 34 | Vendored, unused |
| Kenney Castle Kit (CC0) | `Assets/KenneyCastleKit/` | 1 | 3 | Vendored, unused |

### Notes per pack
- **PolyOne — Free Stickman**: the player model. `Model/Free Pack - Stick Man.fbx`,
  `Animation/stickman_clips.json` (the clip manifest), `Texture/T_Stickmans_Color.png`. Read by
  `tools/build_stickman.gd`, which bakes it into `Scenes/Stickman.tscn` — so no scene references
  the FBX path directly. See `PlayerDecisions.md`.
- **Terrain3D island**: `heightmaps/island.r16`, `island_data/`, `layers/`, `island_assets.tres`,
  and `splat_manifest.json`. Built by `tools/import_island.gd` / `tools/build_world.gd`; the one
  pack a scene (`Scenes/World.tscn`) references by path. See `TerrainDecisions.md`.
- **Kenney Castle Kit** (CC0): SketchUp OBJ export, kept under `Source/` + `Textures/`. The
  darkened `.mtl` trick from the Unity importer is gone — there is no importer script any more,
  and the pack is not wired into the world.
- **Nature packs** (SimpleNaturePack, Squared Snails): candidates for island vegetation.

## Already cleaned up
The Unity-only artifacts have been deleted across the packs — no `.prefab`, `.mat`, `.asset`,
`.unitypackage`, `Prefabs/`, or `Render_Pipeline_Convert/` remains under `Assets/`. So the old
"41 prefabs" / "238 prefabs" style counts no longer describe anything.

## Water
Not a pack: `Shaders/water_from_above.gdshader` (drawn from above) and
`Shaders/water_from_below.gdshader` (drawn from underneath only), plus `Shaders/water_tint.glsl`
for the per-camera underwater tint. These are first-party and documented in `PROJECT_TREE.md`.

The old `Assets/Procedural Water Shader/` pack and the URP `Assets/Shaders/WaterSurface.shader`
are **gone** — they were never wired up, and the two `gdshader` files replaced them.