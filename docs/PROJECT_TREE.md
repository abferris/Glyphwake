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
│   ├── test_*.gd                    # test_collision / test_spawn / test_swim / test_wade / ...
│   ├── sample_control.gd
│   └── probe_*.gd                   # probe_debug / probe_swim
│
└── 📚 docs/                         # This documentation set (see docs/README.md)
```

## Notes
- The `demo/` folder is the Terrain3D **learning demo** (GDScript) — pre-game scratch,
  not the shipped runtime. The shipped runtime is the C# under `Scripts/`.
- Terrain is a single **Terrain3D** region (no tiles to stitch) — see
  `docs/design/TerrainDecisions.md`.
- Water surface is at **y = 80**; water interaction via `Scripts/World/WaterZone.cs`.
