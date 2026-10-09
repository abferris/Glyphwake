# Work To DO

# Next Work To Do

- make some runes
    - player animation for casting
    - assets for projectiles/effects
    - make sure that animation takes over upper body and lower body when appropriate
    - attaching assets correctly
    - Rune animations should trump other animations.
    - In some instances it will limit movement of player to cast
    - Currently working on terra strike
        - make a large earthen fist around your hands and punch
        - Getting the fist asset together
        - Stone fist is size of model's head
        - holding will cast punch repeatedly one after another.
            - Cast animation starts with adding stone fists on the end of model's arms
                - stone fists will stay for 4 seconds after cast
                - stone fists will not need to rerender if recast in time
                - stone fists will go away if selected glyph is changed.
            - if recast within 1 second of the end of last terra strike should alternate punching arm
            - Cannot recast until punch is finished.
- Glyph Hotkey Toolbbar
    - Already have the base for it
    - may want to replace background
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
- Replace 18 discrete locomotion states with two blend spaces (walk, run)
    - deletes most of the 306 generated transitions instead of maintaining them
    - costs the AnimationTree-dock editability that generating the graph bought
- Channeling
- Preparing to cast
- cast glpyh
    - per-glyph cast scenes for the other glyphs (aqua, and the future ones) — the layer and
        the variant table exist, each new glyph is a new scene + its own variants; Cinder
        Shot's gather-and-push is the second authored cast scene
- playtest in-game: the jump tilt (12°, sign/magnitude first-pass), the airborne head level
    and upper-back damp (the jump clips tuck the spine; `AirbornePose` holds the head upright
    and takes `UpperBackDamp` 0.8 of the shoulder girdle's curl — both first-pass), the
    Terra Strike punch
    (fist size, window, blend times are all first-pass exports), and Cinder Shot
    (the gather-and-push cast reads: ReleaseAt 0.55 of the 0.5 s clip; LaunchSpeed 20,
    damage base 10 +5/point, mana 10 — all placeholders; the red sphere is the stand-in mesh)

## Glyphs to code
- Ranged attack
    - projectile — the payload pattern exists (Cinder Shot: `CinderShotPayload`, the
        Projectile layer's first user); a new ranged glyph is a new .tres + payload scene
    - aqua 
    - kindling — Cinder Shot is the first (Inferno element, Kindling school)
    - skillshot — the aim reticule + gravity arc exist in basics: the aim reads the head
        camera's centre ray at cast time, the arc falls, terrain contact resolves
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
