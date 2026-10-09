# Controls, Aiming & Hotkeys — Decisions & Design Notes

Status: mouse look currently has **no button gating at all** — it is always-on while the
cursor is captured, and hold-right-click-to-look was removed from the codebase rather than
shipped. Nothing in the input map below is implemented; the rest is documented here so player
options stay cheap. Covers input feel, the swappable aim point, totem placement, hotkey
bars/sets, skill remapping, and build order.

**Most of what follows is tentative.** These are defaults chosen so the game is playable,
not commitments — and per *Remapping* every one of them is a player setting anyway. The
right-click split and the preview key are the least settled numbers in this doc; if
playtesting disagrees, they change first.

## Philosophy

- The game is skill-shot based — aim matters more than stat checks
- Mechanics for skills are always going to be line of sight focus.
- The game is first person
- Skills are customizable, and any number of abilities can be selected
- Skills can be toggled between

## Camera Movement

- Mouse always turns the view; cursor locked and hidden. 
- Will have crosshairs on screen
  - Need to decide when to activate crosshairs

## Base reticle (implemented)

- A translucent dot with a small circle around it sits at the exact center of the screen
  whenever the player can aim
-  LMB casts at reticle
- RMB interacts with  what is closest to reticle
- always visible (for noww)
  will fill with color to signify cast time (or something else)
- Drawn, not a texture
- Lives in the HUD scene — `Scenes/UI/Hud.tscn`, a `Hud` CanvasLayer instanced once by
  `Player.tscn` — not in World.tscn: it belongs to the first-person rig the same way the
  camera does, so every world that instances Player.tscn carries it. The HUD is its own
  scene (scripts under `Scripts/UI/`) rather than inline nodes in Player.tscn so UI
  changes never reopen the player scene — the same reason the glyph runtime was pulled
  out of it — and the menus and toolbar coming later have a home.
- Radii, width and colours are exports on the script — taste values, not decisions; tuned in the inspector.

## Glyph dial — health/mana HUD (implemented, display-only)

- A flat-topped hexagon pinned into the lower right corner of the screen: 
-  right corner touches right screen edge 
- bottom edge is flush with the screen bottom
- Width has default value but can be scaled with ui options
- The resource bars run inside hexagon's edges
- numerical values can be revealed with the ` key
- Mana and health grow towards the top-left corner
- stamina on bottom goes right to left.
- The selected glyph's graphic sits in the hexagon's centre
- Drawn, not a texture, on the same `Hud` CanvasLayer as the reticle (`Hud/GlyphDial` in
  `Scenes/UI/Hud.tscn`, script `Scripts/UI/GlyphDial.cs`), on a full-rect Control with the
  pinning computed from the viewport each draw, so window resizes reposition it. Width,
  bar width, colours and glyph size are exports — taste values, not decisions.
- UI reads, and doesnt write information
- Selected Glyph is from glyph hotkey toolbar

## Hotkey Toolbar (WoW-style toolbar)

- A fixed toolbar with 10 slots to put glyphs in.
- Players can rearrange which skill sits in which slot.
- Tab switches between hotkey sets
- Scroll wheel switches selected glyph
- Alternative number keys to change selected glyph
- tab changes which set of glpyhs are in the toolbar

## Input map (tentative defaults)

Every binding here is a **default, not a decision** — see *Remapping*. This table exists so
the defaults are written down in one place and can be changed without hunting the prose.

| Action | Default | Notes |
|---|---|---|
| Look | Mouse move | Cursor locked and hidden, always-on |
| Cast selected glyph | LMB | |
| Interact | RMB tap | Context-sensitive on the crosshair |
| Fine aim / slow look | RMB hold | Was in the codebase once, since removed |
| Preview cast | F hold | Middle mouse is the fallback default |
| Sprint | Shift | |
| Jump | Space | |
| Consumable 1 / 2 | Q / E | |
| Cycle glyph set | Tab | |

## Casting glyphs:

- Aim with mouse movement
- Left click will cast the glyph
- Right click interacts with whatever the crosshair is on, and holds to look

## Interacting (tentative)

Right click is the world-interaction verb, not a second cast button. Note that look is
currently always-on rather than RMB-gated, so RMB is free to take this role — but see the
open question on what hold-right-click means once interact owns the tap.

- The mouse is locked and hidden, so "interact" means whatever the crosshair is on,
  using the same raycast that aims glyphs. One aim model, two verbs: LMB casts at it, RMB
  interacts with it.
- Context-sensitive, and deliberately one verb covering several outcomes: talk to an NPC,
  loot a corpse, pick up an item, open a chest or door, hand in a quest.
- Crosshair on nothing: RMB does nothing. No fallback, no nearest-object snap — a silent
  snap is how you open the wrong chest.
- **Interact and target stay separate.** Interacting is instant and situational; *targeting*
  a unit is sticky, and is what group content, threat and nameplates need. Targeting gets
  its own key, so interacting never silently changes who is marked.

## Aiming 

- glyphs will repeat cast if mouse is held down
  - not for channel glyphs
  - not for held glyphs (holding a spell to release)
  - will be an option to disable in player options
  - not for ritual glyphs
### Projectile glyphs:
- Most attack glyphs are simple projectiles
- Will shoot in center of screen out.
- Some will be able to hold rmb for either more "oomph" or ready to release cast
- Crosshairs provided in combat (not sure how to trigger)
- Certain glyphs may have recast for secondary. 
  - Must be on same skill to recast
- Projectiles should be effected by gravity
- Potentially holding the cast button will increase projectile speed (idea)

### Location Casting glyphs
- glyphs that take a specific area of effect without projectile
  - Example: totems, summons
- Location glyphs will have a max range.
- Will cast on target location in the crosshairs
- If not aimed at surface within range, will cast on ground in direction at the end of range.
- Hold the cast button will highlight 
- Will show a circle of range where you can cast it
- Will show a highlighted portion of the ground for area it will effect.
- These are the same two decals the standalone preview draws (see *Cast preview*), not a
  second visual dialect. One "where does this land" language for both.

### Directional AOE glyph
- short range
- no projectile
- will cast centered on crosshairs
- channel glyphs

## Cast preview (tentative)

Hold **F** to preview the selected glyph's cast; release to cancel.

- Projectile glyphs: the flight path from the caster to the aim point.
- Location glyphs: a shaded effect circle inside a larger shaded cast-range circle, drawn
  with the same decals the location-glyph hold already describes.
- Holding F and pressing LMB together commits the cast while still previewing, which is
  what placing a totem mid-fight needs.
- Rejected — **overloading right-click's hold.** It is already the look key, and gating it
  on "nothing interactable under the crosshair" would cost the player the ability to look
  around whenever an NPC is nearby. In an MMO that is most of the time, and looking around
  is exactly what you are doing in a town.
- Rejected — **hold Ctrl.** A modifier held through combat is pinky fatigue, it turns every
  other key into a combo, and Ctrl is the genre's conventional slot for target/nameplate
  info, which this game will want.
- Middle mouse is the fallback default, since it is the only other button with room under
  the right hand.
- Open: whether F should also toggle rather than only hold, so a placement glyph can be
  lined up and dropped repeatedly without re-aiming every time.

## Consumables

Two consumables can be bound to q and e. These can be bought. Currently one of the only things that in-game currency can be used for.

## Remapping (a requirement, not tentative)

Most imputs should be remappable. The defaults above are conveniences so the
game is playable before anyone opens the options; nothing in the design depends on them.

- Bind by *action*, not by key, so gameplay code can never assume a physical key.
- The right-click tap/hold split is two remappable actions sharing one physical button. If
  the player separates them, the hold threshold and cancel-on-release behavior travel with
  the action, not the key.
- Conflict detection on assignment, plus a reset-to-defaults.
- Not built yet — the input map itself is a todo.

## Open questions

- What do we use currency for in the game?
  - don't want to make it game breaking
- Does holding right-click on an NPC also interact with it? RMB is now one button split
  into tap (interact) and hold (look), and the press/release behaviour has to be picked:
  fire on press, which is simple but makes accidental talks, or wait for a release under
  the threshold, which silently cancels a long-press on an NPC. Most MMO-likes take a
  long press as a valid interact; leaning that way, with a short hold threshold (~120 ms).
- Now that interact owns the RMB tap, is a hold-to-look variant still wanted? Look is
  always-on today, and it works, so hold-RMB-look is a *precision* mode (slower or zoomed
  turn) rather than the only way to look. It could also just be dropped in favour of the
  F-hold preview, which already asks the player to hold a key while aiming.
- Look-mode wording: is "hold right-click to look" plus "always follow the mouse"
  the pair of options the player picks between, or is right-click also meant to do
  *movement* (MMO-style hold-RMB-to-move-forward)? Current direction: right-click is
  look only; movement stays WASD.