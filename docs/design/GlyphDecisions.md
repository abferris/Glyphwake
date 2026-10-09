# Glyphs & Skills — Decisions & Design Notes

Status: data model implemented (`Scripts/Glyphs/`), the player-owned loadout and the
resource pools exist, and the first glyph is live: Double Jump (technique). Covers
how Glyphs map to skills, how they classify, what they cost, and how points scale them.
Updated 10-02: the loadout (`GlyphLoadout.cs`), the pools (`PlayerResources.cs`) and the
technique layer (`PlayerTechniques.cs`) consume the data; the first `.tres` is
`Resources/Glyphs/Techniques/DoubleJump.tres`. See "Code notes" at the end for where
the code deliberately departs from this document.
Updated 10-03: glyphs are listed in one catalog (`GlyphCatalog.tres`) rather than enumerated
in `Player.tscn`, and a technique is looked up by its trigger instead of being wired per
technique. Both are departures with engine constraints recorded under "Code notes".

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
  - Exception (decided 10-02): Double Jump's points buy mid-air jumps — one every 10 points.
    Breakpoints that add capability exist where the design calls for them; this is the only
    glyph with one so far.
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
- Technique Glyph
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

Techniques are an action/capability that rides an existing input and consumes a resource --
the one the glyph's own cost entry declares, so a movement technique can pay stamina while
the others pay mana. These
do not create glyphs placable in the hotkey toolbar, so it is not and active. The do add extra functionality
that did not exist before, so they are not passive glyphs. Extra points in the glyph will scale it
Examples:
- Double jump (press jump again while airborne) — scaled distance; needs stamina (moved
  off mana 10-07; see the stamina list under Resources).
- Wall jump (press jump while against a wall) — scaled force.
- Waterbreathing — no breath timer; you spend mana instead, and start drowning when it runs out.
- Spiderclimb — climb while mana lasts; points scale climb speed.

When points are in them, they are always on

Double Jump (decided 10-02) — the first technique built:

- Points ≥ 1: on. Press jump again while airborne: one mid-air jump at half the normal
  jump's height, steering the arc slightly toward the held direction.
- Every 10 points: +1 mid-air jump. 11 → third jump, 21 → fourth, ... 91 → eleventh; at
  the full pool, ten mid-air jumps. Each starts at half the normal jump's height and
  reaches twice it over its decade, then caps — further points buy new jumps, not growth.
- More points also spend less stamina (linear decrease, flooring at 0). The cost entry
  declares Stamina, and the payer reads that declaration rather than assuming mana
  (10-07, was mana decided 10-02).
- The chain resets when you land.

### Modifier math & stacking

When several modifiers touch the same stat, resolve in three stages: flat → percent →
multiply.

- Flat — added first (e.g. +10 damage).
- Percent — all percents add together, then apply as one (two +10% = +20%).
- Multiply — applied last, multiplicatively (x2, x1.5).

This is predictable and easy to balance. (`ModifierOperation` has `Add`/`Percent`/`Multiply`;
resolving three modifiers in that order is the consumer's job, not built yet.)


### Unresolved passives (unresolved)

- Luck
- money
- loot drop

## Code notes

Where the code deliberately differs from this document, and why.

- **`GlyphSchool` / `GlyphElement` are enums, not tags.** The `Tags` list is still there for
  classification neither set covers, but anything another glyph filters on has to be a closed
  set — resistance tables, combo rules and passive filters all need to enumerate it. Tags are
  free-form and matched by a stable `GlyphTag.Id` rather than resource identity, because the
  old `Array.Contains` compared the resource instance and a tag authored in the editor would
  not have matched one built in code.
- **The old `GlyphCategory` enum is gone.** Its five values (Capability / Movement / Utility /
  Attack / Summoning) predated this document and overlapped School. Three classification axes
  was one more place for them to disagree.
- **`StatKey` is split by owner**, into the glyph's own numbers (Damage, Radius, Range, …) and
  the caster's (MaxHealth, ManaRecovery, …). Keeping one enum for both is what allowed mana
  cost to exist twice: as a float on `ActiveGlyphData` and as a `StatKey`, each with its own
  scaling path.
- **Cost is a list of `GlyphCost`, not a float.** Per the Resources section above, a cast can
  pay mana up front *and* stamina per second while it channels, and some glyphs spend health.
  `CostResource` is Mana / Health / Stamina; `PerSecond` is what makes a channel able to
  drain, which the old single `ManaCost` float could not express.
- **Passive targets are three typed lists**, not one list with a kind field. `SelfStatModifier`
  (your own stat), `GlyphModifier` (other glyphs, filtered by school/element/tag) and
  `PassiveTrigger` (an event that spawns a payload) are different shapes; one list would let
  every entry carry fields that cannot apply to it.
- **Techniques are a third subclass, not a flag on actives.** `TechniqueGlyphData` has a
  `TechniqueTrigger` instead of a hotbar slot and an aim direction, because a technique rides
  an existing input and adds a capability — that is what separates it from an active on one
  side and a passive on the other. When points are in it, it is on.
- **Behaviour is a `PackedScene` payload**, on both `ActiveGlyphData` and `PassiveTrigger`. The
  data describes *what a glyph is and how strong*; the payload node is what actually happens in
  the world. Keeping that out of the resource is what lets effects be ordinary Godot scenes
  the artist tunes in the editor.
- **Scaling is base stats plus per-glyph scaling entries, not a shared formula.** Every glyph
  holds `StatValue[]` base statistics and a `GlyphScaling[]` array; a scaling entry points at a
  `StatKey`, names a `GlyphScalingStyle` (Linear / Quadratic / SquareRoot / Step) and carries a
  value. The old `PerPoint` fields (`ScaledStat`, `CastTimePerPoint`, `CooldownPerPoint`,
  `DurationPerPoint`, trigger `DurationPerPoint`) were linear-only and hardcoded, so one glyph
  could not scale differently from another. CastTime, Cooldown, Duration and Range are now base
  stats like any other number — absence of an entry is how "zero for that mode" is expressed
  (an Impulse has no CastTime, a Self target has no Range). The lookup is shared
  (`GlyphStats.StatAt` / `TryStatAt`); `TryStatAt` exists because 0 is a legitimate value and
  only the boolean can tell "no entry" from "explicit 0". `PassiveTrigger` carries its own
  base stats + scalings (one passive can fire several payloads with different needs) through
  the same helper.
- **Cost and passive-modifier growth are still linear-only.** `GlyphCost`'s
  `AmountPerPoint`/`PerSecondPerPoint` and the modifiers' `PerPoint` predate the scaling styles
  and have not been migrated; per the Activation & point scaling section above, "different
  glyphs scale differently" currently holds only for glyph stats.

## Code notes (10-02 additions)

- **The double jump's growth is a breakpoint curve, expressed in two pieces.** The jump
  COUNT is the glyph's own `JumpCount` stat: base 1 with a `Step` scaling, Value 1 per
  `StepSize` 10 points — `StatAt(JumpCount)` reads exactly the number of mid-air jumps the
  points buy. The per-jump HEIGHT depends on which jump you are on as well as the point
  count, so it cannot be a pure scaling entry: it lives in the consumer
  (`PlayerTechniques.AirJumpHeightAt`), relative to the body's normal jump height. This
  departs from "no breakpoints to add functionality" above — the design now adds jumps at
  breakpoints (decided 10-02), and the linear ramp inside each decade is a judgement call
  the document does not settle.
- **Node references resolve by path in `_Ready`** (the `PlayerRig` pattern), not by exported
  node references. A C# `[Export]` node reference serialized into a hand-written `.tscn`
  (`X = NodePath("...")`) did not resolve under 4.7: the property stayed null with no error
  and no warning, and only a probe found it. Resource exports (`X = ExtResource(...)`)
  resolve fine — the trap is node-typed exports only.

## Code notes (10-03 additions)

- **Which glyphs exist lives in `GlyphCatalog`, not in the scene.** `Player.tscn` used to carry
  an `ext_resource` per glyph, a `GlyphLoadoutEntry` sub_resource per glyph and a
  `Technique = ExtResource(...)` export per technique — a scene whose length tracked the content
  and that had to be reopened every time a glyph landed. It now references
  `Resources/Glyphs/GlyphCatalog.tres` once, so adding a glyph is a new `.tres` plus one line in
  the catalog. The grouping is three typed lists (`Techniques` / `Actives` / `Passives`) for the
  reason given above for passive targets, and the master catalog that a separate per-type file
  would have needed is not built yet: nothing consumes "every glyph" until the rune setup menu
  does.
- **Godot does not preserve the element type of an exported C# array.** `[Export]
  Array<SomeCSharpClass>` reaches Godot as `Array[Resource]`: `get_typed_class_name()` reports
  `Resource`, the `.tres` saves with no type marker, and a type written into the file by hand
  (`Array[TechniqueGlyphData]([...])`) is discarded on load. Pushing from GDScript is refused by
  Godot's own typed-array check — but it refuses *everything*, including a correctly-typed glyph,
  and `Actives` refused even its own type while `Techniques` and `Passives` accepted theirs. So
  the typed arrays are worth keeping for C#-side compile-time and cast safety and for making the
  grouping legible, but they do **not** give an editor-side type filter. `GlyphCatalog.Validate`
  is the substitute: it reports any glyph that is not in the list its own subclass belongs to, and
  `GlyphLoadout` refuses to seed off a catalog that fails it. Pinned by
  `tests/test_glyph_catalog.gd`, which will report the day a Godot upgrade changes it.
- **`GlyphCatalog.tres` is generated, not hand-written**, by `tools/build_catalog.gd` through
  `ResourceSaver`. A hand-written catalog would be guessing the serialized form of the typed
  arrays, which is the exact failure mode the previous bullet describes. Re-run that script after
  adding a glyph.
- **A technique is resolved by `TechniqueTrigger`, not by a per-technique export.** The trigger
  is already the thing that distinguishes one technique from another — a technique rides an
  existing input — so `PlayerTechniques` asks the catalog for "the Airborne technique" and the
  catalog decides which `.tres` answers. Wall jump, air dash, waterbreathing and spiderclimb each
  ride a different trigger, so each is a catalog entry and no change in code or scene. The
  property stays settable because `tests/test_glyph_loadout.gd` hands it a glyph directly instead
  of standing up a catalog.
- **The loadout seeds itself; the scene no longer authors an allocation.** `Entries` is
  player-owned runtime state and was serialized into `Player.tscn` as a 5-point sub_resource.
  `GlyphLoadout._Ready` now seeds any catalog glyph with no entry from `DefaultSeedPoints` (5),
  leaving an existing entry alone so a restored save — or a deliberate zero — survives. One value
  for every glyph is a simplification, not a design: nothing needs per-glyph starting points yet,
  and the rune setup menu replaces this along with save-loaded allocations.

## Code notes (10-03 attachments, session 4)

- **A glyph carries an animation, as its own scene rather than as a clip name.**
  `GlyphData.CastAnimation` is a `GlyphCastAnimation` (`PackedScene` + `StringName` clip +
  blend times), on the base class so an active, a technique and a passive trigger all get it.
  The reason it is a scene and not a name in the player's library is
  `AnimationIds.ReachableClips`: that list is the closed set of clips movement can ask for, and
  `LocomotionGraph` gives every state every transition, so 16 clips is already 240 transitions
  and the rule is quadratic. Adding one state per glyph would turn a fixed cost into a per-glyph
  one that grows faster than the glyph count — the opposite of what the catalog work bought.
  Carrying the animation in its own scene keeps `ReachableClips` locomotion and lets any number of
  glyphs each own theirs.
- **A separate AnimationPlayer over the same skeleton is the reason this is opt-in.**
  The locomotion tree already drives the player's `Skeleton3D`. A second `AnimationPlayer` writing
  the same bones is a second writer, and which one wins is a question about process order rather
  than something this resource answers. It is left to whoever implements playback to settle, and
  recorded as an open question in `CURRENT_TODO.md`.
- **A glyph's landing effect is a second slot, not part of the projectile scene.**
  `ActiveGlyphData.ImpactPayload` sits beside `Payload` because the two are instantiated in
  different places — `Payload` at the caster and it travels, `ImpactPayload` where the payload
  resolves. It is also what lets one impact be shared by every glyph that uses it instead of every
  projectile scene carrying its own copy.
- **"Animation, model, or a mix" is not a question the model has to answer.** Both new slots are
  `PackedScene`, so a fire blast's projectile is a scene holding a `MeshInstance3D` and a script,
  and its impact is a scene holding whatever combination of mesh, `GPUParticles3D` and light the
  effect needs. That was already the reasoning behind `Payload`; this session gave the impact the
  same treatment rather than inventing a new vocabulary for it.
- **Nothing read any of this at the time, and that was the honest state.** `Payload`, `ImpactPayload`,
  `CastAnimation`, `CastMode` and `CastTime` all had zero consumers — the cast pipeline below is
  still unbuilt, so these are attachment points with tests, not working features. `CastAnimation`
  has since got its playback (session 5, below); the rest still wait on the cast pipeline. Pinned by
  `tests/test_glyph_payloads.gd`, which round-trips all three through a real save and load and
  checks `GlyphCastAnimation.Validate` catches a clip name the scene does not hold and a scene
  with no `AnimationPlayer` — the two mistakes the editor cannot catch, since `Scene` accepts any
  scene. Same failure shape `LocomotionGraph.MissingClips` reports for a renamed locomotion clip.
- **Godot finding: `PackedScene.pack()` silently drops a child whose `owner` is unset.** A scene
  assembled in code rather than authored in the editor saves as its root alone, which made the
  nested-`AnimationPlayer` case of that test read as "no AnimationPlayer in the scene" instead of
  as the broken fixture it was. Recorded in the test; an editor-authored scene has owners set, so
  it only bites scripted scene building.

## Not built yet (next layers)

- Casting/execution of active glyphs (needs the AimSource → AimTarget pipeline, and a spawner
  for `Payload` + `ImpactPayload`; `CastAnimation` now has its player — see the session 5 note)
- Status effects on glyphs (slow, burning, dazed, ...) — `PassiveTrigger` has the event, but
  no status concept to fire
- Resolving modifiers flat → percent → multiply, and aggregating them across a loadout
- Boosted recovery (safe zones, resting, regen passives) — the pools and the floor regen exist
- Point-allocation UI (the rune setup menu) — `GlyphLoadout` has the allocation model and the
  inspector is the debug allocator
- Remaining techniques wired to locomotion (wall jump, air dash, waterbreathing, spiderclimb)

## Code notes (10-03 air-step cast, session 5)

- **The two-writer question is answered, and the answer removed the second writer.** The double
  jump's cast plays through `Scripts/Player/Animation/Movement/CastAnimationLayer.cs`: the cast
  scene's clips are merged into a separate `cast` library on the main player, and a
  `AnimationNodeOneShot` in the same tree runs the clip once, fades in and out, and hands back. Its
  filters — set from the clip's own track list at cast time — decide which bones the cast takes
  over, so locomotion keeps playing underneath on every other bone. No second `AnimationPlayer`
  writes the skeleton; the cast scene's own player is instantiated once at build, merged, and freed.
  The mechanism is general: the next glyph with a cast animation (a fire bolt taking the hands)
  points at its own scene and works through the same layer.
- **The variant table is what makes one cast animation directional.** `GlyphCastVariant` entries
  (key → clip) on `GlyphCastAnimation.Variants`, keyed by the closed vocabulary in
  `GlyphCastVariant` (`forward_l` … `backward_r`, lower case because they are authored more often
  than read). An unknown key falls back to `Clip` rather than to silence, so a typo fails safe to
  the default pose; `Validate` checks every variant clip against the scene. The double jump carries
  all eight, and `CastAnimationLayer` resolves the key from the direction held and the foot the gait
  phase says is leading. See `PlayerDecisions.md` for the alternation and the measured boundary.
- **Playback is keyed by the cast's own variant table, and the merge is a library, not names.** An
  animation name cannot contain a `/`, so the namespace is a separate `cast` `AnimationLibrary` on
  the main player and `cast/<clip>` is the player's own library/animation path. The locomotion graph
  and the tests never mistake a cast clip for a reachable one.

- Input map, aim raycast, cast preview (see `ControlsDecisions.md`)
- Unlocks via missions, reset in safe zones, hotbar binding (see `ControlsDecisions.md`)
- Remap anywhere vs safe-zone-only (above).