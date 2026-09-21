# Controls, Aiming & Hotkeys — Decisions & Design Notes

Status: one camera behavior already shipped (hold-right-click to look); the rest is
documented here so player options stay cheap. Covers input feel, the swappable aim
point, totem placement, hotkey bars/sets, skill remapping, and build order.

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

## Hotkey Toolbar (WoW-style toolbar)

- A fixed toolbar with 10 slots to put glyphs in.
- Players can rearrange which skill sits in which slot.
- Tab switches between hotkey sets
- Scroll wheel switches selected glyph
- Alternative number keys to change selected glyph
- Alternative Q & E to change select glyph (provisional decision - not sure)
- potential for player choice to rebind
- Hotkey sets are not changeable all the time.

##  Casting glyphs:

- Aim with mouse movement
- Left click will cast the glyph
- Right click will ???

## Aiming 

### Projectile glyphs:
- Most attack glyphs are simple projectiles
- Will shoot in center of screen out.
- Projectile will have to 
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

### Directional AOE glyph
- short range
- no projectile
- will cast centered on crosshairs
- channel glyphs

## Consumables

Two consumables can be bound to q and e. These can be bought. Currently one of the only things that in-game currency can be used for.

## Open questions

- What do we use currency for in the game?
  - don't want to make it game breaking
- Look-mode wording: is "hold right-click to look" plus "always follow the mouse"
  the pair of options the player picks between, or is right-click also meant to do
  *movement* (MMO-style hold-RMB-to-move-forward)? Current direction: right-click is
  look only; movement stays WASD.