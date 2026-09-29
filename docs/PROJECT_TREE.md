# Glyphwake — Project Tree (Godot 4.7, C#)

Verified structure of the project root. Unity-era items (`*.unitypackage`,
`*.asset`, `Assets/...` `.prefab`, `ProjectSettings/`, URP settings) no longer exist —
this is the Godot layout. Addon contents are counted, not listed exhaustively.

```
Glyphwake/
│
├── 📄 project.godot                 # Godot 4.7, Forward+, C#, main scene, input
├── 📦 Glyphwake.sln                 # Godot .NET solution
├── 📦 Glyphwake.csproj              # Godot.NET.Sdk/4.7.2, net8.0, UseGodotToLoose
├── 📦 Glyphwake.csproj.uid
├── 📦 Glyphwake.slnx                # Godot .NET solution (slnx bundle)
│
├── 🎮 Scenes/
│   ├── World.tscn                   # Main scene — Terrain3D island + water + player
│   ├── Player.tscn                  # CharacterBody3D player (controller + camera + stickman)
│   ├── Stickman.tscn                # Low-poly stickman model instance
│   └── TestWorld.tscn               # Scratch/test world scene
│
├── 🎨 Shaders/
│   ├── water_from_above.gdshader  # surface seen from above; angle + depth driven transparency
│   ├── water_from_below.gdshader   # Snell's window underside of the water surface
│   └── water_tint.glsl            # compositor compute pass: per-pixel underwater tint (prototype,
│                                  #   not yet wired into the scene)
│
├── 💻 Scripts/                      # C# runtime + data (the shipped game)
│   ├── Player/
│   │   ├── PlayerController.cs      # CharacterBody3D: WASD + jump + gravity + swim/wade
│   │   └── CameraController.cs      # First-person head camera (mouse look, dive look)
│   ├── World/
│   │   └── WaterZone.cs             # Area3D water trigger: surface Y, Enter/Exit water
│   └── Glyphs/                      # Pure Resource data model (1 glyph = 1 skill)
│       ├── GlyphData.cs             # Base GlyphData Resource + GlyphCategory enum
│       ├── ActiveGlyphData.cs       # Cast style, mana/cast/cooldown scaling, ScaledStat[]
│       ├── PassiveGlyphData.cs      # Passive: Array<PassiveModifier>
│       ├── GlyphTag.cs              # School/element classification tag
│       ├── PassiveModifier.cs       # Tag-filtered additive/multiplier modifier
│       ├── ScaledStat.cs            # StatKey + base + perPoint scaling
│       └── StatKey.cs               # Enum of every scalable stat
│
├── 🧩 addons/
│   └── terrain_3d/                  # Terrain3D addon (C++/GDExtension)
│       ├── terrain.gdextension
│       ├── bin/                     # libterrain.*.so/.dll/.dylib/.wasm per platform
│       ├── src/                     # Editor tooling (GDScript: toolbar, asset dock, ...)
│       ├── menu/                    # Terrain menu UI (baker, channel packer, setup)
│       ├── brushes/ (13)            # Terrain3D paint brushes (.exr)
│       ├── tools/                   # Importer / region mover
│       ├── utils/
│       └── demo/                    # Terrain3D built-in demo scenes + GDScript
│
├── 🏝️ Assets/
│   ├── Terrain/
│   │   ├── island_assets.tres       # Terrain3DAssets: noise heightmap + layer maps + materials
│   │   ├── island_data/             # Terrain3D region heightmap/map data
│   │   ├── heightmaps/              # Exported/scratch heightmaps
│   │   ├── layers/                  # Terrain3D layer color configs
│   │   ├── island_previews/         # Terrain render previews
│   │   └── splat_manifest.json      # Layer manifest
│   │
│   ├── EmaceArt/Slavic World Free/  # Slavic village + nature kit (low-poly)
│   ├── KenneyCastleKit/             # Kenney castle kit (Source/ + Textures/)
│   ├── PolyOne/Free Stickman/       # Stickman (model, animation, prefabs)
│   ├── Polytope Studio/Lowpoly_Environments + Lowpoly_Village/
│   ├── SimpleNaturePack/            # Trees, rocks, grass (Models/ + Textures/)
│   ├── Squared Snails Studios/3D Low-Poly Nature Pack/
│   └── ithappy/Fantasy_FREE/        # Fantasy props + scenes
│
├── 🎮 demo/                         # Terrain3D learning demo (GDScript)
│   ├── src/                         # Player.gd, Enemy.gd, UI.gd, CameraManager.gd, ...
│   ├── components/                  # Borders, Enemy, Environment, Player, Tunnel, UI scenes
│   ├── data/                        # terrain3d_*.res regions + nav mesh + assets.tres
│   └── (Demo.tscn, DemoScene.gd, ...)
│
├── 🛠️ tools/                        # GDScript authoring/import scripts
│   ├── import_island.gd             # Import island heightmaps → terrain
│   ├── build_world.gd               # Build/rebuild the world scene
│   ├── build_stickman.gd            # Rebuild stickman model
│   ├── import_control.gd            # Import controller setup
│   ├── test_*.gd                    # test_collision / test_spawn / test_swim / test_wade /
│   │                                #   test_plunge / test_view / test_underwater_look /
│   │                                #   test_underwater_filter / ...
│   ├── sample_control.gd
│   └── probe_*.gd                   # probe_debug / probe_swim / probe_shot / probe_above /
│                                    #   probe_effect (verifies the compositor's depth
│                                    #   reconstruction against plates of known height)
│
└── 📚 docs/                         # This documentation set (see docs/README.md)
```

## Notes
- The `demo/` folder is the Terrain3D **learning demo** (GDScript) — pre-game scratch,
  not the shipped runtime. The shipped runtime is the C# under `Scripts/`.
- Terrain is a single **Terrain3D** region (no tiles to stitch) — see
  `docs/design/TerrainDecisions.md`.
- Water surface is at **y = 80**; water interaction via `Scripts/World/WaterZone.cs`.
- The water plane is drawn twice: `Water` with `Shaders/water_from_above.gdshader` from above, and
  its child `SurfaceFromBelow` with `Shaders/water_from_below.gdshader` from underneath only. The
  top shader reads the scene depth and makes transmittance Beer-Lambert over the distance the view
  ray actually travels through water, so shallow water is clear looking down and turns to a mirror
  at a grazing angle. It declares `DEPTH_TEXTURE` as a `hint_depth_texture` uniform; 4.7 removed
  the old built-in of that name.
- `tools/probe_shot.gd` renders real frames and writes PNGs to `tools/tmp_shots/`. It needs the
  real renderer, so run it **without** `--headless`.
- The underwater tint on `CameraController` is **faded, not switched**. `Environment` stays on the
  camera at all times and its fog density is scaled by a smoothed submersion value, because
  detaching the environment on `IsUnderwater` left a frame with no filter at all on the way
  through the surface, which read as a flash. `SubmersionOn`/`SubmersionOff` set the depth the
  filter comes in at and the height above the surface it lets go at, with the gap between them as
  a dead zone that keeps the treading bob out of the tint, and `SubmersionFadeSpeed` sets how fast it
  moves between them. The density is the water haze scaled by the tint, so it is **exactly zero
  above the waterline**: the world's own environment carries 0.45 of blue aerial fog, and the
  camera carrying its own environment at zero density is the only reason that never shows up
  above water. Do not rebase the density onto the world's value — that puts a blue haze over the
  whole above-water look. `UnderwaterFogNear`/`UnderwaterFogDeep` (0.9/2.2) are instead set high
  enough for the haze to carry the tint by itself, which it has to do when looking forward and
  down, because the ceiling is edge on there and contributes nothing. `test_underwater_filter.gd`
  guards all of it, along with the swim lift that holds the eye clear of the water while treading,
  which used to teleport the eye down through the surface in one frame whenever the view was pitched
  down far enough to dive.
- Two measurement traps on this code, both hit while chasing the tint and both recorded in
  `docs/past/WORKLOG-09-28-2026.md`: reading `Camera3D.Environment` from a script returns the
  **world's** environment rather than the camera's own, so a mirror camera given that renders the
  above-water look and reports the tint as inert; and writing a C# `[Export]` float from GDScript
  reads back as having taken when the C# field never saw it, so the tint cannot be A/B'd by
  overriding those exports at runtime. Use `UnderwaterFogDensity` instead.
- `tools/probe_above.gd` measures how much of a red marker hung in the water survives the surface
  at each depth and view angle, which is how the above-water transparency was tuned. It renders
  into its own `SubViewport`: the root window only presents frames when it is on screen, and a
  hidden window hands back a stale image that silently measures the wrong frame. Also needs the
  real renderer, so run it **without** `--headless`.
