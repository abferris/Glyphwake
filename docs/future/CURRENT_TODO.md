# Work To DO

# Next Work To Do
## Rune System
- Implementing Rune system
    - passive runes
    - active runes
    - some of this might have been started by
- Creating player interface
    - menus
        - player menu
        - rune setup menu
        - player options
            - camera
                - mouse to rotate
                    - aim on center screen
                - right click to rotate
                    - aim on cursor
            - wasd vs up down right left
            - casting style (click skill and click mouse vs skill smart cast where cursor is)
    - rune hud in game
    - rune slot selection
- Mechanics to create
    - Slippage
    - Breath
    - Mana
    - Health
    - Falling damage
    - casting
        - how to cast skill
        - do i have a skill range help tool?
    - skill selection
    - aiming mechanics (point and click)
    - input map (see docs/design/ControlsDecisions.md)
        - bind by action so nothing assumes a physical key
        - every action remappable by the player, conflict detection, reset to defaults
        - right click: tap = interact with whatever the crosshair is on, hold = look
        - cast preview on hold F: range circle, effect circle, projectile flight path
        - interact and target are separate actions, not the same key
- Rendering the distance (not started, nothing decided yet)
    - how far props, foliage and the water plane visibly carry before culling or fog takes over, and whether the stickman and the nature packs need LOD
- make some goddamn runes and their effects
## Animation
- Channeling
- Preparing to cast
- cast glpyh
- Melee Glpyh
    - punching

## Glyphs to code
- Ranged attack
    - projectile
    - aqua 
    - kindling
    - skillshot
- Melee attack (Terra, Kindling)
    - punching animation
    - Terra
    - Maybe add a stone fist on hand when casting
    - Target Direction
- Healing totem
    - Anima
    - Calling
    - target terrain in range
- Passive (Shaping)
    - For now movement speed
- Double jump 
    - Technique
    - Zephyr 
    - Flowing
    - jump button twice
    - not recastable until hit ground
- Air Dash
    - Technique
    - Zephyr 
    - Flowing
    - jump then run button midair
    - not recastable until hit ground
- Searing Beam, channel in a direction (Inferno, Kindling)

## Controls
- Aiming
    - Translucent dot in middle of screen with a small circle
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
## Non-Ocean Water
- rivers
- lakes
## Ledge mechanics