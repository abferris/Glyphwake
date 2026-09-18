# Packages & Asset Packs

Inventory of what was pulled into the project, why, and what each pack contains.
(The project targets **Unity 6000.6.0f1** with **URP 17.6.0**, so built-in-render-pipeline
shaders will not work here.)

## Unity packages (`Packages/manifest.json`)
| Package | Version | Use |
|---------|---------|-----|
| `com.unity.render-pipelines.universal` | 17.6.0 | URP — the whole project renders with this |
| `com.unity.inputsystem` | 1.20.0 | New Input System (**only** input system in use; legacy `Input.*` throws) |
| `com.unity.ai.navigation` | 2.0.14 | NavMesh, for future creatures |
| `com.unity.timeline` | 6.6.0 | Cutscenes / sequencing |
| `com.unity.postprocessing` | 3.5.4 | Volume post FX |
| `com.unity.visualscripting` | 1.9.12 | Visual scripting |
| `com.unity.ugui` | 2.6.0 | UI |
| `com.unity.ide.rider` | 3.0.38 | IDE integration |
| `com.unity.ide.visualstudio` | 2.0.26 | IDE integration |
| `com.unity.test-framework` | 1.8.0 | Tests |
| `com.unity.collab-proxy` | 2.13.6 | Unity Version Control |

Plus the standard `com.unity.modules.*` set (animation, physics, terrain, terrainphysics,
ui, uielements, particlesystem, audio, video, xr, etc.).

## Asset packs

### Kenney Castle Kit — imported (CC0)
- Source: `/mnt/c/Users/abfer/Downloads/Castle Kit by Kenney - 2pA966ztJJX`
  (SketchUp OBJ export; license **CC0**).
- Vendored to `Assets/KenneyCastleKit/` (`Source/` holds `castleKit.obj`,
  `castleKit.mtl`, and `castleKit.mtl.bak` = the original bright palette; the active
  `.mtl` is a deliberately darkened palette).
- Imported by `Tools > Assets > Import Kenney Castle Kit`
  (`Scripts/Editor/CastleKitImporter.cs`). Unity's OBJ importer merges the 159 groups, so
  the tool splits the OBJ into **71 logical pieces** and writes `Meshes/` + `Prefabs/`
  (one prefab per piece) and 11 URP/Lit materials.
- 11 materials: `wall`, `wood`, `wallDark`, `roof`, `FrontColor`, `cotton`, `dark`,
  `knightRed`, `king`, `knightBlue`, `roofRed`.
- Status: tool written and validated offline (71 pieces, 21,877 tris); **not yet run in
  Unity / not compile-tested**.

### PolyOne — Free Stickman — in use
- `Assets/PolyOne/Free Stickman/`: `Model/` (`Free Pack - Stick Man.fbx`), `Prefabs/`,
  `Animation/` (clips + `Controler/Stickman_Controler.controller` + `Directional/`),
  `Materials/`, `SplitMeshes/`, `Scene/`, `Texture/`.
- This is the **player model**. See `PlayerDecisions.md`.

### ithappy — Fantasy_FREE
- `Assets/ithappy/Fantasy_FREE/`: `Materials/`, `Meshes/` (41), `Prefabs/` (41),
  `Render_Pipeline_Convert/`, `Scenes/`, `Textures/`.
- Fantasy environment props. Two HDRP-only assets were deleted (no missing-script refs).

### EmaceArt — Slavic World Free
- `Assets/EmaceArt/Slavic World Free/`: `Materials/` (11), `Meshes/` (213),
  `Prefabs/` (238), `Texture/`, `Terrain/`, `Skybox/`, `Scene/`,
  `Post Processing_profile/`, `Plugin/`, `SourceFiles/`, `URP_Support/`.
- Large medieval/village kit. Four broken assets were deleted up front.

### Polytope Studio — Lowpoly
- `Assets/Polytope Studio/`: `Lowpoly_Environments/` (25 environment prefabs + sources),
  `Lowpoly_Village/` (5 prefabs + sources), `Lowpoly_Demos/Environment_Free/`,
  `Welcome_Screen/`.

### SimpleNaturePack
- `Assets/SimpleNaturePack/`: `Models/` (24 FBX), `Prefabs/` (24), `Materials/`,
  `Scenes/`, `Textures/`. Includes both HDRP and URP `.unitypackage` archives.
- Trees, bushes, flowers, grass, ground, mushrooms, rocks, stumps. Source for
  `NatureAssets.unitypackage` at the project root.
- Note: this is the **2020.3** edition (v1.24), older than the Unity 6 project.

### Squared Snails Studios — 3D Low-Poly Nature Pack
- `Assets/Squared Snails Studios/3D Low-Poly Nature Pack/`: `Trees/` (22), `Stones/` (11),
  `Mushrooms/` (6), `Other/` (9), `Clouds/` (4).
- Second nature set, used for island vegetation/rocks alongside SimpleNaturePack.

### Procedural Water Shader — unused / candidate to remove
- `Assets/Procedural Water Shader/`: `Shaders/ProceduralWater.shader`, `Materials/`,
  `Demo/`, plus HDRP + URP `.unitypackage`s.
- The scene uses a simple flat transparent URP/Lit material instead, so this pack is not
  wired up. Deferred delete candidate together with `Assets/Shaders/WaterSurface.shader`
  and `Assets/Materials/WaterSurface.mat`.

### TutorialInfo (URP template)
- `Assets/TutorialInfo/`: the stock URP template readme/scripts. Not game content.
