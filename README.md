# Glyphwake

A first-person prototype in **Godot 4.7 (C#)** — swimming, wading, and walking a Terrain3D
island, with a headless test suite that pins the movement down.

Everything the game needs is in this repository: scenes, C# scripts, shaders, the Terrain3D
addon and its native binaries, and the terrain's 196 tile data files. Cloning gives you the
whole thing.

---

## Requirements

Two things are easy to get wrong, and the first one is the reason most people cannot open this
project at all:

1. **Godot 4.7.x — the .NET build, not the standard one.** This is a C# project. The standard
   (non-.NET) Godot cannot open it and will not offer to load the C# scripts. Grab the
   **.NET** variant from <https://godotengine.org/download>. The Windows build ships as two
   executables in one folder; either works, but the tests want the `*_console.exe` one so their
   output reaches your terminal.
2. **The .NET 8 SDK.** `Glyphwake.csproj` targets `net8.0` and pulls `Godot.NET.Sdk/4.7.2`.
   Godot restores this for you on first open if the SDK is installed.

Also worth knowing: the renderer is **Forward+**, physics is **Jolt**, and on Windows the
rendering driver is set to **D3D12**.

## Running it

```
git clone https://github.com/abferris/Glyphwake.git
```

Open `project.godot` in the Godot editor and press **F5**. The main scene is already set to
`res://Scenes/World.tscn`, so there is nothing to choose.

**First open takes a few minutes.** Terrain3D has 196 tiles to turn into collision meshes and
shader variants from scratch, and the editor looks completely frozen while it does. This is
normal and it only happens once — `.godot/` is not in the repository, so every fresh clone pays
it.

## Controls

The game reads **physical keys directly**. There is no InputMap yet (it is on the todo), so
these are not rebindable and will not respond to a remapped layout.

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` | move |
| Mouse | look (captured and hidden on start) |
| `Shift` | sprint |
| `Space` | jump |
| `F1` | toggle first/third person — **remove before shipping**, the game is first person |
| `F2` | toggle a debug log of locomotion + camera state, written to `user://swim_debug.txt` |
| `F3` | toggle the debug chase camera |
| `Esc` | toggle mouse capture (releases the pointer, press again to recapture) |

## Tests

The tests are headless `SceneTree` scripts. They instantiate the real `World.tscn`, drive the
player by injecting physical key events, and assert against what the body actually did — they
read the island's real geometry rather than assuming it, which is why several of them scan for
suitable water depth or dry ground first.

Run one from the command line:

```
godot --headless --path /path/to/Glyphwake --script res://tests/test_wade.gd
```

Use the `*_console.exe` binary, or the `print` output goes nowhere and the script appears to
hang. Exit code is 0 for pass, 1 for fail, and each test prints a `TEST <NAME> OK` line when it
is happy.

Current state — 11 of the assertion tests above pass, 2 fail, and `test_collision` /
`test_spawn` run silently without a verdict:

| Test | Covers |
| --- | --- |
| `test_wade` | wade drag curve against submersion, and the shoulder handover |
| `test_swim` | the surface float holds the head clear |
| `test_swim_entry` | entering the water from a jump |
| `test_plunge` | a fall into the water stays a fall until the float arrests it |
| `test_plunge_hold` | the float holds the plunge pose |
| `test_ledge_wade` | swimming into a rising ledge climbs out and hands over to wading |
| `test_swim_slope` | a bank too steep to climb does not sink the body; a climbable one does |
| `test_slope_speed` | uphill speed bands: full to 35°, slower but walkable to 60°, blocked past |
| `test_walkstop` | releasing the keys mid-stride keeps the gait it was already playing |
| `test_view` | the camera and debug chase camera hand the viewport over cleanly |
| `test_underwater_look` | per-pixel depth reconstruction and the tint split at the waterline |
| `test_stickman` | **failing** — treading pose and the eye at the waterline |
| `test_underwater_filter` | **failing** — that the water haze alone can carry the tint |
| `test_collision` | *(older diagnostic — prints nothing)* |
| `test_spawn` | *(older diagnostic — prints nothing)* |

The two known failures are deliberate and pre-existing, not new breakage:

- **`test_stickman`** — three treading/camera failures. The eye averages 3.43 against a 4.18
  waterline, sits underwater for all 217 treading frames, and the body never rises above 3.73.
  `IsUnderwater` pitches the body to -90°, which drops the head bone from 0.56 to 0.08 above the
  origin, and the camera lift that holds the eye clear is gated on *not* being underwater — so
  the eye dips, the lift switches off, and the eye drops further. It needs hysteresis, the same
  way the underwater tint has.
- **`test_underwater_filter`** — asserts the water haze is strong enough to carry the tint by
  itself (needs > 0.5, currently 0.063–0.102). The density was retuned by hand from 0.9/2.2 and
  the original argument for the stronger pair is preserved rather than rewritten.

## Documentation

`docs/` holds the design decisions and the day-by-day worklog. Start at:

- [`docs/README.md`](docs/README.md) — doc index and the project's verified current state
- [`docs/design/`](docs/design/) — the decisions behind controls, glyphs, the player, terrain,
  and packages. `ControlsDecisions.md` and `GlyphDecisions.md` are the active ones.
- [`docs/past/`](docs/past/) — worklogs, one file per day

## Repository layout

```
Scenes/     World.tscn (main), Player.tscn, Stickman.tscn
Scripts/    C# — Player, World, Glyphs, Core
Shaders/    water_from_above / water_from_below .gdshader
Assets/     Terrain3D island data, heightmaps, layer textures
addons/     terrain_3d, including the native binaries
tools/      headless authoring/import scripts and the test harness
tests/      the headless test suite (test_*.gd)
demo/       GDScript learning demo
docs/       design decisions and worklogs
```

Note that `tools/` is a mix: `audit_*.gd` are one-off inspection scripts with no assertions
that nothing imports, `probe_*.gd` render measurements and write to `logs/`, and
`build_stickman.gd` regenerates `Scenes/Stickman.tscn`. The real suite lives in `tests/`, with
`tools/run_tests.sh` as its harness. Captured Godot runs go in `logs/`, one subdirectory per
kind (`logs/console/`, `logs/import/`, `logs/probe/`).