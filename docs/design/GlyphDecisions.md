# Glyphs & Skills — Decisions & Design Notes

Status: data model implemented (`Assets/Scripts/Glyphs/`, data-only — nothing castable
yet). Covers how Glyphs map to skills, how they classify, and how points scale them.

## Core model

- **1 Glyph = 1 skill** for actives. A fireball is one Glyph; a single-target fire shot is a
  separate Glyph. Dash is an active Glyph; double jump and wall jump are passive Glyphs.
- **Passives do not add a bindable skill.** They are either **Modifiers** (change existing
  stats/effects/capabilities — faster run, more health, lifesteal) or **Techniques**
  (mana-driven actions/capabilities riding on an existing input — double jump, wall jump,
  waterbreathing, spiderclimb). A passive is never selectable and cannot appear in the
  spell list.
- **Categories** (from `GAME.md`): Capability, Movement, Utility, Attack, Summoning.
- A Glyph that is acquired but has **0 points is inactive and not in your spell list** —
  nothing it grants exists until the first point is spent.

## Activation & point scaling

- **Total pool is 100 points** (down from the original 1000 design). Each point is 1% of
  your build — coarse enough to play without micro-calculations, single-point enough to
  dial in a build by hand.
- The original anchors 10/30/50/100/150 (of 1000) are exactly the same fractions as
  **1/3/5/10/15 of 100** — the impact curves didn't change, only the number size.
- **Activation threshold = 1 point** (`GlyphData.ActivationPoints`), which is a hard rule
  (0 = inactive), also the first reading guidepost ("minimally useful").
  `GlyphData.IsActiveAt(points)` encodes this, so both the
  allocation UI and the cast/effect systems must respect it.
- Because 1 point activates, **base values are defined at 1 point**, and every additional
  point adds that Glyph's `perPoint` growth:
  `ValueAt(points) = base + perPoint * (points - 1)`.
- **Any investment is valid** — there are no required tiers or breakpoints. Each point is
  1% of the 100-point pool, so a build is just "whatever percentage you chose": 2%, 20%,
  or dumping most of the pool into one ace skill are all legitimate.
- **1/3/5/10/15 are reading guideposts, not anchors and not targets.** They exist to help
  read how effective a skill is in a build (e.g. alongside the glyph visual prominence in
  `GAME.md`), never to constrain what a player may invest:

  | Investment in one Glyph | Reads as |
  |---|---|
  | 1 | minimally useful |
  | 3 | a secondary spell |
  | 5 | decently impactful, something you use regularly |
  | 10 | a primary Glyph |
  | 15 | specialist — the build is centered on it |

  They are reference points for reading builds and for discussing your own, not enforced
  thresholds. If surfaced in UI at all, it is as read-only shorthand. Implemented as
  guidepost constants on `GlyphData`.
- **No cap per Glyph** — `maxPoints` was removed. You may sink the whole 100-point pool
  into one attack; nothing in the data model stops you, and the counter-play is other
  players' glyphs/tactics, not a ceiling.
- **Theories need real numbers:** everything a player can spend points on exposes its
  exact base and per-point value, so the allocation UI prints "Damage: 12 + 2/point"
  style summaries. This is `ScaledStat` and the `*At(points)` helpers.
- **Spells must be fine without passives** — base power is adequate on its own. Passives
  are a tailoring layer for specific playstyles, not a requirement for viability.

## Classification

Classification is hierarchical. The first split — and the easiest one — is **Active vs
Passive**; every other classification sits underneath it.

1. **Active vs Passive** (which concrete type the Glyph is):
   - **Active Glyphs** (`ActiveGlyphData`) **add a skill to the skill tree / spell list.**
     They are what the player casts, binds to a hotbar slot, and invests points in.
   - **Passive Glyphs** (`PassiveGlyphData`) **do not add a skill.** They are **Modifiers**
     (change stats/effects/capabilities) or **Techniques** (mana-driven actions on existing
     inputs), and modifier effects only apply while the affected skills are active.
2. **`GlyphCategory`** (Capability, Movement, Utility, Attack, Summoning) applies within
   either side — an active and a passive can both be, say, Movement.
3. **School** — the *verb* the magic performs (see *Schools of magic*). A fixed,
   structured set.
4. **Elements** — the energy type (see *Elements*).
5. **Tags** — `GlyphTag` assets for any further classification. Adding a tag means creating
   an asset, not editing code. Passives can match on tags, schools, or elements.

### Passives → spells (using tags)

- A passive modifier matches a **set of spells** and applies an operation to one `StatKey`
  (damage, radius, mana cost, cast time...). The set can **combine filters** — element,
  school, and tag at once (e.g. "all Inferno *Kindling* spells").
- Three operations (see *Modifier math & stacking*): **Flat**, **Percent**, **Multiply**.
  - "larger AoE" → `Flat Radius` to spells tagged `AoE`
  - "lower mana" → `Multiply ManaCost` to all
  - "stronger fire" → `Percent Damage` to spells of the Inferno element

## Schools of magic

A Glyph's **school** is the *verb* — what the magic does to reality — independent of its
element (energy type), target, shape, and cast/effect time. Affinities and specialist
passives key off schools. The set is original rather than lifted from D&D, and deliberately
smaller (6 vs D&D's 8).

| School | Verb | Lean | Covers |
|---|---|---|---|
| **Kindling** | channel raw energy | active | fireballs, lightning, healing (life energy), life-drain, undeath, light/shadow, smoke |
| **Warding** | prevent & deny | active | barriers, absorb, dispel/counterspell, silence, isolation, severs |
| **Calling** | spirit-binding | active | summons/minions; a spirit bound into yourself (shapeshift), an object (animate), or the ground (roots) |
| **Seeking** | perceive & know | active | reveal, detect, foresee, scry |
| **Flowing** | move through space | active | fall control, jumps, dash, haste/slow, teleport, portals |
| **Shaping** | alter physical properties | mostly passive | altering your own substance/body (tougher skin, altered limbs, enhanced metabolism) |

### School principles (decided)

- **School = mechanism (verb), not purpose (domain).** Healing is Kindling (channeled life
  energy) rather than a restoration school; necromancy is Kindling channeled with **Death**
  energy rather than its own school.
- **Life and Death are energies, not schools** (see *Elements*).
- **No mind control and no hard lockout.** *Compelling* (influence minds) was cut: it takes
  away the opponent's agency and isn't fun to play against. Control is always soft —
  silence, root, isolation, slow — never petrify, stun-lock, or charm.
- **Shaping is mostly passive.** True transformation lives on passive glyphs; active Shaping
  is currently empty. Candidates were redistributed: stonehide → Warding (or passive),
  featherfall / spiderclimb / waterbreathing → Flowing or passive, shapeshift / animate
  object → Calling, stonewall → Kindling; enlarge/shrink, state-of-matter change, and
  quicksand were cut.
- **No duplicate spells.** One effect, one spell — e.g. immobilize is Calling's roots, not
  also a separate "hold" spell.
- **Element is optional.** Some spells are pure-school (town portal = Flowing, silence =
  Warding).

## Elements

An element is the **energy type** a spell channels — the character the **mana** takes,
independent of its school (verb), target, shape, and cast/effect time. Elements determine
**damage type and resistances**. Element is **optional**: pure-school spells (town portal =
Flowing, silence = Warding) have none.

Six elements, each an internal duality:

| Element | Covers | Damage form |
|---|---|---|
| **Inferno** | fire / heat | burning |
| **Aqua** | water + ice | piercing (ice) / bludgeoning (crushing water) |
| **Terra** | earth / stone | bludgeoning / piercing |
| **Zephyr** | air / wind | slashing |
| **Anima** | life + death (+ body/physical attributes) | life / decay |
| **Lux** | light + shadow | **none** — utility only |

### Element principles (decided)

- **Damage type ≈ element.** Piercing / slashing / bludgeoning describe *how* an element
  hurts; **resistances are per element** (Inferno, Aqua, Terra, Zephyr, Anima). **Lux deals
  no damage** and therefore has no resistance.
- **Anima covers "physical" body effects.** A gauntleted punch and a thrown rock are both
  **Terra** (earth); body/self effects are **Anima**. So a double jump is **Zephyr + Anima**
  (wind + body), not a separate "physical" type.
- **Multi-element is allowed.** A spell may carry several elements:
  - Meteor = **Inferno + Terra**
  - Lightning = **Zephyr + Inferno**
  - Fire punch = **Inferno** (the element carries the damage; not a hybrid)
  - Double jump = **Zephyr + Anima** (non-damaging)
- **Split damage equally** among a spell's damaging elements (temporary rule).
- **Element is more than flavor:** it decides what the spell is resisted by.
- **Life-force exception:** a few **Anima** spells spend **health** instead of mana (blood
  magic) as deliberate outliers.

Open: whether specific mixes get a formal **combo table** (with named rules) or stay
descriptive.

## Mana (essence)

Mana is **raw, elementless magical energy** — the common fuel for all magic. The **school**
is what you do with it; the **element** is what it becomes. Mana is not an element, not
life force (Anima's domain), and not death (Kindling + Death). Keeping it neutral is what
lets a spell choose any element (or none) at cast time.

### Costs

- **All active spells cost mana per cast.** The **basic attack is free**, so a mana-light
  build still works.
- **Channels and Techniques drain while held** — Shield, Dragon's Breath, waterbreathing,
  spiderclimb, double/wall jump.
- **Life-force exception:** a few **Anima** spells spend **health** instead of mana (see
  *Elements*).

### Recovery

- **Slow passive regen** at all times, plus a **full refill at safe zones**.
- A **Channel spell** refills mana quickly but **locks out other casting while held** —
  channeling ambient essence into yourself. (School/name open.)
- **Passive Glyphs** boost regen, cut costs, or grant on-kill refill. Max mana and regen are
  `Self`-targeted modifiers (`MaxMana`, `ManaRecovery` in `StatKey`).
- **Consumables** may give a quick influx (undecided).

Open: what the mana-refill Channel spell is called and which school it belongs to.

## Active spells

Active spells are described along independent axes: **targeting** (what it aims at),
**cast time** (the commitment to produce it), and **effect time** (how the result behaves
once produced). A spell picks one of each — e.g. an Impulse-cast Meteor is Point-targeted
and leaves an Instant effect.

### Targeting

**Target type** — what the spell addresses:

| Target | Meaning | Examples |
|---|---|---|
| **Self** | applied to / centered on the caster | Shield, Dash, Healing Aura |
| **Single** | one entity | Firebolt, Heal, Healing Bond |
| **AoE** | an area | Dragon's Breath, totem aura |
| **Point** | a location in space / on the ground | Meteor, Town Portal |

**Affects** — who the target/area is allowed to affect (independent of target type):

| Affects | Meaning |
|---|---|
| **Enemies** | only enemies |
| **Allies** | only allies (and possibly the caster) |
| **Self** | only the caster |
| **All** | anything in the target/area |
| **By tag/type** | only entities matching a tag (e.g. a totem: "people of type in range") |

**Shape** — the physical form the spell takes:

| Shape | Meaning | Examples |
|---|---|---|
| **Projectile** | a skillshot that flies through the air to its target | Firebolt, Meteor |
| **Beam** | a continuous ray / tether between caster and target | Healing Bond |
| **Cone** | spreads outward from its origin | Dragon's Breath |
| **Radius / aura** | area around a center | Healing Aura, totem aura |
| **Point-placed** | placed at a location and remains there | totem, traps, Town Portal |
| **None / self** | no travel geometry | Shield, Dash |

### Cast time (commitment)

The commitment needed to produce the spell:

| Tier | Delay / commitment | Movement | Interruptible |
|---|---|---|---|
| **Impulse** | none — fires immediately | free | no |
| **Focus** | wind-up; length varies (short or long) | free | no |
| **Channel** | must keep casting; stopping ends it | free | no (you choose to stop) |
| **Ritual** | long, demands undivided attention | locked | yes |

Examples:
- **Impulse** — Dash; Firebolt.
- **Focus** — Meteor: a powerful AoE ball of flaming material (physical + fire damage),
  pointed at a spot. Healing Aura: a longer Focus cast that sets a **Lasting** healing
  effect centered on the caster.
- **Channel** — Shield: spend mana continuously to hold up a barrier. Dragon's Breath: a
  continuous cone of flame in the direction you face while casting.
- **Ritual** — Town Portal: teleport to town.

### Effect time (persistence)

How the result behaves once produced; a spell picks one tier:

| Tier | Meaning |
|---|---|
| **Instant** | resolves now; nothing persists |
| **Channel** | effect exists only while you keep casting |
| **Anchored** | persists while its physical thing exists (totem, summon, ward) |
| **Lasting** | lasts a set clock duration |

Examples:
- **Instant** — Heal (one-time heal); Firebolt; Meteor (throw a big burning rock that
  resolves on impact).
- **Channel** — Shield; Dragon's Breath; Healing Bond (a stream of healing to one target
  for as long as you keep casting).
- **Anchored** — Summon ____ (any conjured entity; persists until gone); ____ Totem
  (emits an aura from a placed totem — those of the matching type in range feel its
  effects); Trigger Trap Glyph (paired with a second spell and casts that spell when
  triggered); Proximity Trap Glyph (casts its paired spell when an enemy enters range).
- **Lasting** — most aura spells; Smokescreen (a fog that obscures for a set time).

### Status effects

Some spells apply a lingering status to what they hit — **slow, burning, dazed**, etc. Only
a minority of spells do. Statuses belong to the **spell**, not to passives.

Clarification — **Focus vs Ritual is freedom, not cast length.** Focus can wind up short
*or* long and stays mobile + uninterruptible; a Ritual locks you in place and can be
interrupted. **Focus vs Channel:** Focus completes and *then* applies its effect (Instant,
Lasting, or Anchored); Channel only holds its effect while you keep casting.

## Passives

Passives never add a bindable skill. They are either **Modifiers** (change stats/effects/
capabilities) or **Techniques** (mana-driven actions on existing inputs) — see
*Modifiers vs Techniques*.

### What a passive can target

| Target | Meaning |
|---|---|
| **Self** | your own stats/state — health, mana, regen, speed, carry, point pool, ... |
| **Spell** | one specific spell |
| **Element** | every spell of an element |
| **School** | every spell of a school |

The last three are all "a set of spells," selected by name, element, or school. So a
passive always reduces to **Self** or **a set of spells**. There is deliberately no 5th
"system" target:

- **On-hit / trigger effects** → part of the **Spell** they belong to.
- **Cooldowns** → a property of the **Spell**.
- **Point pool** → **Self**.
- **Glyph slots** → do not exist; slots are **unlimited** (managing them is the player's
  problem).
- **Adding a target to a spell** (a spell gets two targets) → a **Spell** modification.

Summons, allies, and enemies are reached through the targeted spell's **Affects**, never as
a passive's own target.

### Modifiers vs Techniques

- **Modifier** — changes a stat, effect, or capability; **always-on** (no input, no mana).
  **Lifesteal** is a modifier: a passive stat that normally **starts at 0** (some Anima
  spells grant lifesteal intrinsically instead). Examples: +health, +regen, resistances,
  lifesteal.
- **Technique** — an action/capability that **rides an existing input** and **consumes
  mana**; not selectable, no hotbar slot, so it is still a passive. Points scale it:
  - **Double jump** (press jump again while airborne) — scaled distance; needs mana.
  - **Wall jump** (press jump while against a wall) — scaled force.
  - **Waterbreathing** — no breath timer; you spend mana instead, and start drowning when
    it runs out.
  - **Spiderclimb** — climb while mana lasts; points scale climb speed.

Most passives are always-on; a few are state-gated (double jump only matters *while
airborne*). We do not build a general condition system for passives.

### Modifier math & stacking

When several modifiers touch the same stat, resolve in three stages: **flat → percent →
multiply**.

- **Flat** — added first (e.g. +10 damage).
- **Percent** — all percents **add together**, then apply as one (two +10% = +20%).
- **Multiply** — applied last, multiplicatively (x2, x1.5).

This is predictable and easy to balance. (`PassiveModifier` currently has `Add`/`Multiply`
only and will need a percent operation.)

### Passive constraints (decided)

- **School and element are both optional on passives for now** (allows mundane passives,
  e.g. +carry weight); may change later.
- **Passives are strictly positive** — no drawbacks/curses (revisit as a separate concept
  later).

### Non-magical passives (unresolved)

- There is **no XP** — progression is **acquiring Glyphs**, not grinding levels.
- **Luck**, **money**, and **loot** are undecided: the game is Glyph/magic-based, so their
  purpose is unclear. Items are expected at least for **fetch quests**. Revisit later.

## Not built yet (next layers)

- Casting/execution of skills (needs the AimSource → AimTarget pipeline)
- Status effects on spells (slow, burning, dazed, ...)
- Techniques (mana-driven passive abilities: double jump, wall jump, waterbreathing,
  spiderclimb)
- Mana pool, regen, and the mana-refill Channel spell
- Point allocation + the 100-point pool
- Unlocks via missions, reset in safe zones, hotbar binding (see `ControlsDecisions.md`)