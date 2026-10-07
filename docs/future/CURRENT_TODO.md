# Work To DO

# Next Work To Do

- make some runes
    - player animation for casting
    - assets for projectiles/effects
    - make sure that animation takes over upper body and lower body when appropriate
    - attaching assets correctly
- Glyph Hotkey Toolbbar
    - Already have the base for it
    - may want to replace background
    - add selection of Glyph Set by scroll wheel
    - Do more after creating some glyphs
- Implementing Rune system
    - resolving modifiers flat -> percent -> multiply across a loadout
    - cost and passive-modifier growth still linear-only (scaling styles only on glyph stats, see GlyphDecisions.md code notes)
    - passive runes
    - active runes
    - techniques wired to locomotion (double jump done - wall jump, air dash, waterbreathing, spiderclimb left)
    - status effects
- Creating player interface
    - menus
        - player menu
        - rune setup menu
        - player options
            - casting style (click skill and click mouse vs skill smart cast where cursor is)
    - rune slot selection
- Mechanics to create
    - Slippage
        - what you can and can't climb up exists, but falling slower on less steep slopes
    - Breath
    - Health
    - Falling damage
    - casting
        - how to cast skill
        - do i have a skill range help tool?
    - aiming mechanics (point and click)
        - trajectory
        - casting on area
        - using the aiming circle for channel/timing with filling
    - input map (see docs/design/ControlsDecisions.md)
        - bind by action so nothing assumes a physical key
        - every action remappable by the player, conflict detection, reset to defaults
        - right click: tap = interact with whatever the crosshair is on, hold = look
        - cast preview on hold F: range circle, effect circle, projectile flight path
        - interact and target are separate actions, not the same key
- Rendering the distance (not started, nothing decided yet)
    - how far props, foliage and the water plane visibly carry before culling or fog takes over, and whether the stickman and the nature packs need LOD
- make some goddamn runes and their effects
- commit the remaining uncommitted work (not session 4's — see WORKLOG-10-06 Session 4): the
    other agent's HUD (`Scripts/UI/`, `Scenes/UI/`, `docs/design/UIDecisions.md`), the stone-hand
    fist work (`Scripts/Player/StoneHand.cs`, `Scenes/Player/StoneHand.tscn`, `Assets/FistCandidates/`),
    `World.tscn` island assets, `project.godot` window mode, `PROJECT_TREE.md`/`README.md`/`GlyphDecisions.md`/`ControlsDecisions.md`
## Animation
- `tools/build_stickman.gd` does not parse: `_build_ground_jumps()` is called (line ~872) but has no definition — a ground-jump rewrite was left mid-flight on 10-05 (`_step_clip` referenced in its comments does not exist either). The scenes on disk are fine and nothing regenerates them automatically, but any regeneration is blocked until the rewrite is finished or the old builder is restored.
- test_air_jump_animation fails since the Terra Strike landed: the loadout's 100-point pool refuses
    the test's `TrySetPoints(doubleJump, 100)` with the seeded Terra Strike (5) over it, so the double
    jump stays at 5 points and the second air jump is out of budget — zero the other entries first.
    Its "merged 8 cast clips" assertion is 9 now (the punch merged). (WORKLOG-10-06 Session 4)
- Replace 18 discrete locomotion states with two blend spaces (walk, run)
    - deletes most of the 306 generated transitions instead of maintaining them
    - costs the AnimationTree-dock editability that generating the graph bought
- Channeling
- Preparing to cast
- cast glpyh
    - per-glyph cast scenes for the other glyphs (fire bolt takes the hands) — the layer and the variant table exist, each new glyph is a new scene + its own variants
- playtest in-game: the jump tilt (12°, sign/magnitude first-pass) and the Terra Strike punch
    (fist size, window, blend times are all first-pass exports)

## Glyphs to code
- Ranged attack
    - projectile
    - aqua 
    - kindling
    - skillshot
- Melee attack (Terra, Kindling)
    - Kindling variant
    - swap the placeholder fist (brown sphere, `TerraFistPayload`) for the real asset —
        candidates in `Assets/FistCandidates/`, a poseable `StoneHand` rig exists at
        `Scenes/Player/StoneHand.tscn`
    - decide the numbers (damage 10 / mana 10 are placeholders)
- Healing totem
    - Anima
    - Calling
    - target terrain in range
- Passive (Shaping)
    - For now movement speed
- Air Dash
    - Technique
    - Zephyr 
    - Flowing
    - jump then run button midair
    - not recastable until hit ground
- Searing Beam, channel in a direction (Inferno, Kindling)

## Controls
- Aiming
    - When in use Crosshairs are implemented
    - When a spell is being held or charged, use a colored circle between dot and outer circle to indicate how long its being held
- Spell Preview
    - F key
    - hold to show
    - will be different for different skills
- Cast glpyh
- Select glpyh
    - Hotkey Toolbar
        - Tab to change
    - Navigating glyphs
        - scroll wheel

# Leave For Another Time
## Water UX
Make underwater visuals better for user experience.
- distance fade is too strong
## Non-Ocean Water
- rivers
- lakes
## Ledge mechanics
## Make this shit Multiplayer 
- Hosted
    - only up when I tell it to run
    - figure out what goes on the server and what is in the game that people have downloaded
