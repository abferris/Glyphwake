# UI Decisions

Notes about the in-game UI (HUD, reticle, dial) and how it's structured.

## HUD container

- The HUD lives in `Scenes/UI/Hud.tscn` as a `CanvasLayer` (`Hud`) containing the aim reticle and the glyph dial.
- This is instanced in `Scenes/Player.tscn` so UI changes don't tangle with player rig/anim edits.
- UI nodes have `mouse_filter = Ignore` so they never intercept input.
- All values are read-only from the player state.

## Aim reticle

- A central crosshair/dot drawn on a full-rect Control (`AimReticle`) so the aim point is always visible (first-person).
- Shared aim point for casting (LMB) and interaction (RMB). See ControlsDecisions for verbs.
- Drawn in code (not a texture) to keep it cheap and easy to tweak.

## Glyph dial (corner hexagon)

- Flat-topped hexagon pinned to the lower-right screen corner. Right edge along screen right, bottom edge flush with screen bottom; the bare bottom and lower-right edges form the wedge pointing into the corner.
- Bars run along the hexagon's own edges, inside the shape, no gaps. Health on bottom-left and upper-left edges; mana on top and upper-right edges. Empty tracks render along those edges.
- Bars fill toward the top-left (screen-centre-facing) corner and deplete toward the screen-edge ends.
- Thin black outline around the hexagon and around each filled bar for clarity (no interior diagonal divider).
- Selected glyph graphic centered inside the hexagon; auto-sizes if `GlyphSize` <= 0 (fits the inner region), else uses the export. If no icon authored (`GlyphData.Icon` empty), falls back to `DisplayName` shrunk to fit.
- Data sourced read-only: health/mana from `PlayerController.Techniques.Resources`, glyph from `PlayerController.Techniques.Loadout` (currently the first active glyph). Redraws only when values or glyph change.
- Exports: `HexWidth`, `BarWidth`, `GlyphSize`, `GlyphNameSize`, colors (`HealthColor`, `ManaColor`, `EmptyColor`, `BackColor`, `GlyphNameColor`, `BorderColor`).


## Asset recommendations (stone-like UI)

For the lower-right hexagon frame/background and potential bar borders, consider these free, Godot-friendly sources:

- Kenney Fantasy UI Borders (CC0): https://opengameart.org/content/fantasy-ui-borders - 9-slice-friendly borders/frames; good base to cut a hexagon frame or tint stone-grey.
- Pixel UI Fantasy Free (CC-BY-4.0): https://godotengine.org/asset-library/asset/5492 - parchment/RPG UI, includes panels, 9-slice pieces; can recolor to stone/metal.
- Pixel UI Free (CC-BY-4.0): https://godotengine.org/asset-library/asset/5494 - clean pixel UI, theme-based.
- Universal Pixel UI & HUD Pack (free sample available): https://obssidian-art.itch.io/universal-pixel-ui-hud-pack-godot-4-ready - modular 9-slice panels, HUD pieces.
- Hearthframe UI Free Sample (commercial-friendly sample): https://oussamaouafik.itch.io/hearthframe-ui - SVG/PNG, editable, good for stone/brass frames.
- Summer Engine Frames & Borders: https://www.summerengine.com/asset-store/c/frames-borders - curated free frames, CC0-ish (check per asset).
- Hexagon Buildings Pack (CC0): https://www.summerengine.com/asset-store/pack/hexagon-buildings-pack - has stone parts (rings, walls) but mostly building tiles; useful for stone trim inspiration.
- Hexagonal Paths/Tiles (various licenses on itch): for stone hexagon tile backgrounds.
- 9-Slice Editor tool: https://nerulio.com/en/game/9-slice-editor/ - helps extract margins if cutting a custom hexagon frame.

Notes:
- For a hexagon frame, pure rectangular 9-slice distorts angled corners; better: use a TextureRect with a hand-authored hexagon frame texture (or mask), or NinePatchRect only if frame has straight edges. Alternatively draw via `_Draw()` (current approach) and layer a stone border texture on top.
- Use CC0 for no attribution hassle; CC-BY requires credit in game credits.
- All above are 2D PNGs; Godot 4 works well with Nearest filtering for pixel art, Linear for hand-painted.
