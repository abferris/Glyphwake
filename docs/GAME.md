# Game Design Document — Glyphwake

*An open-world island game where your build is written in glyphs.* (working tagline)

## Concept

A RuneScape-like 3D open-world island game with a stylized, low-poly aesthetic. The player explores a hand-crafted island, navigating from a first-person camera perspective.

## World

- Setting: A single island surrounded by water.
- Scale: ~300m island radius, with a terrain height up to ~169m; a sea floor 20m below sea level around the island edges.
- Terrain style: Stylized/beige ground, painted with flat-color grass, sand, dirt, and rock layers.
- Water: A water plane with a transparent teal material at sea level (**y = 80** in the scene).
- Vegetation: Low-poly trees and rocks placed around the island (from nature asset packs).

## Player

- Movement: WASD movement on the terrain, with jump (Space).
- Camera: First-person view. Mouse controls head look (cursor locked); the player faces where you look, so WASD moves relative to your view.
- Physics: Uses `CharacterBody3D` + `move_and_slide()` (not a Rigidbody); gravity handled manually.

## Glyphs (Core Mechanic)

The player allocates 100 points across their collected Glyphs. Glyphs define capabilities, spells, and abilities — each Glyph's effectiveness scales with points invested, and a Glyph with 0 points is inactive (not in the spell list).

### Glyph Categories

- Capability Modifiers — passive stat boosts: run faster, traverse steeper slopes, jump further, elemental resistance, extra health, increased elemental effectiveness.
- Movement Abilities — flying, double jump, wall jump, underwater breathing, dash.
- Utility — teleport, heal, focus (mana recovery).
- Attacks — ranged or melee, with various elements.
- Summoning — totems that emit an aura, or minions that fight for the player.

### Active vs Passive

- Active Glyphs add a skill to the skill tree / spell list. They cost mana, are more
  effective, and scale with invested points.
- Passive Glyphs do not add a skill — they modify existing abilities or your own
  statistics. They do not require mana, but are less impactful per point.

### Scaling

The effect of additional points is specific to each Glyph. Examples:
- Jump Glyph: more points → jump further.
- Spell Glyph: more points → higher damage, larger AoE, or lower mana cost.

### Progression

- Players start with a basic set of Glyphs.
- New Glyphs are unlocked by completing missions.
- This lets a newer player with fewer Glyphs stay competitive by investing more points into the Glyphs they have.

### Reset

Points can be reset in a safe zone, allowing players to reconfigure their build.

### Visual Identity

Equipping a Glyph changes the character model's look (shading, articles of clothing), so other players can try to strategize by reading what you have equipped. The more points invested in a Glyph, the more prominent its look becomes.

### Casting Time

Some spells require a casting time before they take effect.

## World Zones & PvP

- Creatures: PvE gameplay with creatures spread around the island.
- Safe zones: Noncombat areas, including a starting area where resetting glyphs happens. No PvP inside safe zones.
- PvP: Possible outside safe zones and away from the starting area.

## Multiplayer & Social

- Guilds: Players can form guilds.
- Guild events: Planned for the future.

## Items

Most items in the game are consumables.

## Combat Style

- Skill shots: The vast majority of the game is skill-shot based — aim matters more than stat checks.
- Targeting: Line of sight determines whether you can target someone or something.

## Gameplay Roadmap (planned)

1. Player spawn + camera setup
2. Paint the ground (terrain layers)
3. Place trees + rocks
4. Nicer water material
5. Lighting and atmosphere (sun, fog, skybox)
6. Missions and glyphs — gameplay loop: visit a landmark, complete a mission, unlock a new Glyph

## Art Style

Stylized, flat-color, low-poly. Realistic/PBR textures rejected as too detailed for the game's feel.

## Credits

Original game idea — Craig Macomber. Kept in `CREDITS.md`; every credits list (in-game,
store pages, trailers, marketing) must include it.
