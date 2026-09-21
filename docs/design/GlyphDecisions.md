# Glyphs & Skills — Decisions & Design Notes

Status: data model implemented (`Assets/Scripts/Glyphs/`, data-only — nothing castable
yet). Covers how Glyphs map to skills, how they classify, and how points scale them.

## Core model

- Every glyph activates something. 
- Major glyph types
    - Passive
    - Active
    - Modifiers
- 100 points to allocate to all glyphs
  - more points to a rune will make it stronger
- Must have 1 point to be active  that can be put in hotbar for casting

## Activation & point scaling

- Total pool is 100 points
  - Allows for theory crafting
  - Can have round numbers applied for easy builds without effort
- Glyph strength will be dependent on how many points you put into it
  - Basic Guidepost for how strong a glyph is in a build
    - 1 point: Its there, but not important 
    - 3 points: Useful secondary glyph
    - 5 points: Regularly used, decently impactful, not super hard hitting
    - 10 points: Primary used glyph in build
    - 15 points: This is probably what your build is built around
    - 20+ points: Specialist - have sacrificed other options to make this very powerful.
- Activation threshold = 1 point 
  - When setting up glyphs, if there are no points in a glyph you cannot place it in your toolbars
  - If all points are removed from a glyph, the glyph will be removed from all hotkey toolbars on save
- Extra points in a glyph will scale the strength of it
  - Different glyphs will scale differently
    - Not locked in to flat scaling or exponential scaling
    - For active glyphs, skill shot glyphs will scale harder
    - For passive glyphs, specialized glyphs will scale harder 
      - EX: Zephyr Glyph Damage Buff vs Basic Glyph Damage Buff
        - Zephyr would start at a higher number, and more points would give a larger boost
  - Should only change numbers of said glyph, not what it does or how it works
  - While extra points will strengthen a rune, there are no breakpoints to add functionality
- No cap per Glyph
  - You may sink the whole 100-point pool and make a incredibly powerful attack
  - Over investment in one skill leaves you vulnerable to simple counterplay 
  - May need to add mechanics to make sure this isn't abused to destroy mobs.
- When allocating glyphs, you will be given numbers
- glyphs base power must be fine without passives buffs.
  - Passives are a tailoring layer for specific playstyles, not a requirement for viability.

## Classification

Classifications are key to the system. Some passive skills are specific to particular
types of glyphs. We will be heavily reliant on these tags.

### Usage

- Active Glyph
  - Add a skill which can be bound to hotkey groups 
  - Can be used in the Game 
  - Will have a cost
    - Usually mana
    - Some may cost health
  - not allowed in safe zones
  - Examples
    - Heal
    - Firebolt
    - Summon Elemental
- Passive Glyph
  - Do not add a skill. 
  - usable in safe zones
  - Modify things 
    - Glyphs
      - Some may change numbers
        - Damage
        - Mana cost
      - Some may alter how a skill works
        - Number of Projectiles
        - Area of Effect
        - Number of Targets
        - Projectile speed
      - May target specific glyph classification
    - Base Stats
- Techniques
  - Do not add a skill to the skill bar
  - Add new capabilities
  - Will have a cost when used
  - Examples:
    - double jump
    - wall jump

### Schools of magic

A glyph's school is the essence of how it effects the world around it. This has nothing to do with
its element, target, shape, and cast/effect time. This is originally an idea from Dungeons & Dragons
which has been modified to fit my needs.

- Kindling 
  - channeling energy to create an effect
  - Example:
    - fireball
    - Stone Wall
    - healing
    - life-drain
- Warding 
  - protecting and gaurding target from effects
  - create barriers 
  - absorb glyph effects 
  - dispel/counter
  - silence (this is a stretch)
- Calling 
  - spirit-binding
    - shape changing is considered a form of binding a spirit to oneself
    - Could bind to totem
  - summoning 
- Seeking 
  - Using power to gain knowledge
  - detect players
  - detect monster 
  - get knowledge of other player's build 
- Flowing
  - Using power to modify movement
  - feather-fall
  - double jump
  - Wall jump
  - dash
  - haste
  - slow
  - teleport
- Shaping 
  - Using power to alter properties
  - mostly passive 
  - in game altering your own substance/body 
  - tougher skin 
  - altered glyphs

### Elements

An element is the energy type a glyph channels — the character the mana takes,
independent of its school, target, shape, and cast/effect time. Element is optional. Example of a glyphs without elements are town portal.

- Inferno
  - analogous elements
    - fire 
  - damage type
    - heat
  - extra effects
    - burning effect
  - element hallmarks
    - typically more damage
    - less effected by gravity (straighter skill shots)
    - damage over time

- Aqua
  - analogous elements
    - water + ice 
  - damage type
    - piercing (ice) 
    - bludgeoning (crushing water) 
    - slashing
    - cold
  - status effects
    - slow 
    - stun 
    - root effect
  - element hallmarks
    - crowd control
    - effected by gravity
- Terra
  - analogous elements
    - earth 
  - damage type
    - bludgeoning 
    - piercing 
    - slashing
  - status effects
    - knockback 
    - stun 
    - root
  - element hallmarks
    - slower attacks
    - more damage
- Zephyr
  - analogous elements
    - air 
  - damage type
    - slashing 
    - piercing
  - status effects
    - knockback effect
  - element hallmarks
    - Faster Projectiles
    - no effect by gravity
    - reliable to hit
    - dissipates over range
- Anima
  - analogous elements
    - life + death (+ body/physical attributes) 
    - poison
  - damage/effect types 
    - healing
    - necrotic damage
  - status effects
    - weakness
    - mana burn
- Lux
  - light + shadow 
  - damage type
    - Radiant damage
  - status effect
    - Blind 
  - element hallmarks
    - not damage based
    - visual effects

### Element principles (decided)

- Damage type does not mean element type. Damage type is how the 
- Anima covers "physical" body effects. A gauntleted punch and a thrown rock are both
  Terra (earth); body/self effects are Anima. So a double jump is Zephyr + Anima
  (wind + body), not a separate "physical" type.
- Multi-element is allowed. A glyph may carry several elements:
  - Meteor = Inferno + Terra
  - Lightning = Zephyr + Inferno
  - Fire punch = Inferno (the element carries the damage; not a hybrid)
  - Double jump = Zephyr + Anima (non-damaging)
- Split damage equally among a glyph's damaging elements (temporary rule).
- Element is more than flavor: it decides what the glyph is resisted by.
- Life-force exception: a few Anima glyphs spend health instead of mana (blood
  magic) as deliberate outliers.

Open: whether specific mixes get a formal combo table (with named rules) or stay
descriptive.

### Resources
This section covers what a glyph's cast will cost. Sometimes a cost is a one time thing. For channelling and some togglable aura effects, the cost of use will be per time its used. For effect over time, the cost will be a one time
- mana
  - raw innate magical energy
  - used for almost every glyph
- health
  - some glyphs may use health
    - can be the full cost
    - could be a partial cost
    - can use a passive glyph to convert part of the glyph cost into health
- stamina
  - typically used for running
  - some glyphs may use it
    - double jump
    - air dash

### Recovery of Resources

- Health and mana have a slow passive regeneration at all times.
- In safe zones regeneration is boosted
- Resting can boost regeneration
- Passive Glyphs can be boost regeneration, cut costs, or grant on-kill refill
- maybe some channel effects can massively boost regeneration

### Active Glyph Targeting

Target type — what the glyph addresses:

- Self 
  - applied to / centered on the caster 
  - Shield, Dash, Healing Aura 
- Single 
  - targets one entity 
  - magic missile 
  - buff a target
- Projectile
  - emits single shot
- area/point on the ground
  - targets terrain
- direction
  - dragon's breath

### Active Glyph Affects — who the target/area is allowed to affect (independent of target type):

- Enemies 
  - must be in range
- Allies 
  - only allies (and possibly the caster) 
  - must be in range
- Self 
  - only the caster 
  - sometimes effected by # of targets glyph to include party members
    - additional targets are in range
- terrain
  - must be in range

### Cast time (commitment)


- Impulse 
  - none — fires immediately 
  - does not effect movement  
- Focus 
  - wind-up; length varies (short or long) 
  - does not effect movement  
  - not interruptable except by stun or silence
- Channel 
  - must keep casting
  - might have a wind up before it takes effect 
  - glyph use stops when done casting ends it 
  - does not effect movement (might change to slows movement)
  - interruptable by stun or silence 
- Ritual 
  - long casting time
  - cannot move  
  - interruptable by damage

### Effect time (persistence)

This is how long the effects of the glyph last. It might be multiple, like direct damage then a slow or burn
- Instant 
  - resolves now; nothing persists 
- Channel 
  - effect exists only while you keep casting 
- Anchored 
  - persists while its physical thing exists (totem, summon, ward) 
- Over time 
  - lasts a set duration 


### Status effects

Some glyphs apply a lingering status to what they hit — slow, burning, dazed, etc. Only
a minority of glyphs do. 
- burn
- slow
- root
- stun
- knockback
  - not status effect but might put you in the air
- mana burn

### About passives

- Targets
  - Self 
    - your own stats/state 
    - health
    - mana 
    - regen 
    - speed 
  - glyphs 
    - All 
    - Classification 
      - element 
      - School 
      - anything talked about above
- Glyph modifications
  - On-hit / trigger effects
    - burn
    - slow
    - poison
  - Cooldowns 
  - mana cost pool → Self.
  - Adding a target to a glyph 
    - will probably nerf the damage of the glyph for more targets
- always positive for the caster
Summons, allies, and enemies are reached through the targeted glyph's Affects, never as
a passive's own target.

### Techniques

Techniques are an action/capability that rides an existing input and consumes mana. These
do not create glyphs placable in the hotkey toolbar, so it is not and active. The do add extra functionality
that did not exist before, so they are not passive glyphs. Extra points in the glyph will scale it
Examples:
- Double jump (press jump again while airborne) — scaled distance; needs mana.
- Wall jump (press jump while against a wall) — scaled force.
- Waterbreathing — no breath timer; you spend mana instead, and start drowning when it runs out.
- Spiderclimb — climb while mana lasts; points scale climb speed.

When points are in them, they are always on

### Modifier math & stacking

When several modifiers touch the same stat, resolve in three stages: flat → percent →
multiply.

- Flat — added first (e.g. +10 damage).
- Percent — all percents add together, then apply as one (two +10% = +20%).
- Multiply — applied last, multiplicatively (x2, x1.5).

This is predictable and easy to balance. (`PassiveModifier` currently has `Add`/`Multiply`
only and will need a percent operation.)


### Unresolved passives (unresolved)

- Luck
- money
- loot drop

## Not built yet (next layers)

- Just about everything
- Casting/execution of skills (needs the AimSource → AimTarget pipeline)
- Status effects on glyphs (slow, burning, dazed, ...)
- Techniques (mana-driven passive abilities: double jump, wall jump, waterbreathing,
  spiderclimb)
- Mana pool, regen, and the mana-refill Channel glyph
- Point allocation + the 100-point pool
- Unlocks via missions, reset in safe zones, hotbar binding (see `ControlsDecisions.md`)
- Remap anywhere vs safe-zone-only (above).