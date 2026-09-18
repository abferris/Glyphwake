# Controls, Aiming & Hotkeys — Decisions & Design Notes

Status: one camera behavior already shipped (hold-right-click to look); the rest is
documented here so player options stay cheap. Covers input feel, the swappable aim
point, totem placement, hotkey bars/sets, skill remapping, and build order.

## Philosophy

- The game is **skill-shot based** — aim matters more than stat checks, and line of
  sight decides whether you can target something (`GAME.md`).
- **Player choice is a first-class option, not a fixed pick.** Aiming style, look
  style, and cast style are all toggles. The reason this stays cheap is a single
  rule (below): the *aim point is computed once* and every skill consumes it.

## Aiming — the swappable aim point

**Decision:** any cast, shot, dash, blink, or totem placement consumes a single
computed **aim target** (a world point, direction, screen ray, and optional hit).
**Skills never compute their own aim** — they only range-check, LOS-check, and apply
an effect to the target handed to them.

Aim sources (interchangeable because every one produces the same aim target):

| Source | How it aims | Use cases |
|--------|-------------|-----------|
| **Cursor aim** | ray through the mouse cursor (`ScreenPointToRay`) | totem placement, talk-to-NPC, targeted spells, dashes/blinks toward a point |
| **Crosshair aim** | center-of-screen ray | shoot "down your nose"; classic FPS feel for pure skill-shots |
| **Smart-cast** | auto-picked target near the crosshair/cursor | quick-cast without precise aiming |

Rationale: the play style only changes how the aim target is *found*, never what
happens after. That makes "give the player whichever they prefer" a settings toggle
instead of a rewrite of every skill.

## Camera / mouse-look modes (player option)

- **Hold-to-Look:** cursor is free and visible normally (menus, hotbar, NPCs,
  click-to-place). Hold **right-click** to turn the view; release returns the cursor
  and the view stops. WASD stays relative to the last facing. **Implemented** in
  `CameraController.cs`.
- **Always-Look:** mouse always turns the view; cursor locked and hidden. FPS muscle
  memory, strongest for pure first-person skill-shots. **Planned**; to be exposed as
  the same option toggle.

Rationale: the whole point of a free cursor is that pointing (menus, conversation,
totem placement) never has to fight the camera. The two modes share the same aim
pipeline, so the look style and the cast style are independent choices.

## Totems / ground placement

- Click somewhere on the screen to place a totem (which emits an aura).
- The cursor ray hits a world point; if that point is **out of range**, tell the
  player ("out of range") and do not place.
- Same pipeline as a skill cast, just ground-targeted.

## Hotkey bar (WoW-style toolbar)

- A fixed toolbar whose slots bind to hotkeys (e.g. `1`–`9`).
- Players can **rearrange which skill sits in which slot**.
- **Scroll wheel** switches between **sets** of hotbar bindings (Stardew-style tool
  switching), e.g. combat set / utility set / summon set.
- Hotbar sets are pure serialized data (slot → skill binding lists), so this is
  UI/save work, not gameplay work, and is independent of the aiming code.
- Some skills have their own UI (aiming reticles, placement previews).

## Skill cast modes (player option)

- **Click-cast:** aim with cursor/crosshair, trigger the skill.
- **Smart-cast:** cast at the best target under the aim point without manually
  confirming. Built as a mode on top of the shared aim-target pipeline.

## Where skill mapping can change

- **Decision:** skill mapping / hotbar remapping happens in **safe zones**, through an
  interaction — an NPC or a workbench. This mirrors the existing "reset glyph points in
  a safe zone" rule (`GAME.md`), keeping the starting area a true noncombat hub.
- **Open question:** should players also be able to remap *anywhere* outside safe
  zones, or only in the hub? Pending — bears on PvP (mid-fight build switching) and
  on how much identity the safe zone carries.

## Build order (keeping the options cheap)

1. **Glyph/Skill data model** (ScriptableObjects): the 100-point glyph mechanic, the
   skills they unlock, and effect scaling. Hotbar/menus display this data, so it
   comes first.
2. **Aim/interaction foundation**: the aim-source → aim-target pipeline (the piece
   that is expensive to retrofit later).
3. **Thin HUD**: health/mana/points + one placeholder hotbar — enough to playtest.
4. **Minimal mission loop**: visit a landmark → complete a mission → unlock a Glyph
   (roadmap item in `GAME.md`).
5. **Full UI**: hotbar rearrangement, scroll-wheel sets, aim/look mode options,
   smart-cast toggle, safe-zone remap UI.

## Open questions

- Remap anywhere vs safe-zone-only (above).
- Scroll wheel is reserved for hotkey sets — does it conflict with scrolling UI
  panels/menus? (needs a rule when the HUD exists)
- Look-mode wording: is "hold right-click to look" plus "always follow the mouse"
  the pair of options the player picks between, or is right-click also meant to do
  *movement* (MMO-style hold-RMB-to-move-forward)? Current direction: right-click is
  **look only**; movement stays WASD.