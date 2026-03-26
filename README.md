# Tower Defense — Game Design Document

## Concept

A multiplayer tower defense game where players survive endless waves of enemies by placing towers on a grid. The twist: towers are crafted by combining up to 5 rare resources, and the combination determines the tower's effects — some powerful, some cursed.

---

## Core Loop

1. Wave starts — enemies follow a winding path toward the base
2. Players kill enemies to earn money and boss drops (resources)
3. Players spend money to place towers, choosing which resources to slot in
4. Towers attack automatically based on their combo stats
5. Wave clears → intermission → next wave (harder)
6. Every 5 rounds a boss spawns, dropping 1 resource on death
7. Game ends when base health reaches 0

---

## Economy

- Players start with 💰150
- Killing enemies gives money (scales with enemy type)
- Tower placement costs money: base 50 + 30 per resource used
- All players in the session share kills and boss drops

---

## Resources

10 resource types dropped by bosses. Each has a theme, color and hint so players can guess what combos might do.

| # | Name | Color | Theme |
|---|------|-------|-------|
| 1 | Ember | Red-orange | Fire |
| 2 | Frost | Light blue | Ice |
| 3 | Spark | Yellow | Lightning |
| 4 | Spore | Green | Nature |
| 5 | Shadow | Dark purple | Dark |
| 6 | Radiance | Pale yellow | Light |
| 7 | Stone | Brown | Earth |
| 8 | Gale | Sky blue | Wind |
| 9 | Arcane | Purple | Magic |
| 10 | Void | Near black | Void |

### Drop Probability

Boss drops 1 resource per kill. The probability of rarer resources increases with round number.

| Resource | Round 1 | Round 1000 |
|----------|---------|------------|
| Ember (#1) | ~50% | ~15% |
| Void (#10) | ~0.1% | ~10% |

The curve interpolates linearly between these values over 1000 rounds.

---

## Towers

Towers are placed on fixed grid slots (up to 50 per map). Players select 1–5 resources and spend money to place. The resource combination determines all tower stats.

### Base Stats
- Damage: 10
- Range: 20 studs
- Fire rate: 1 attack/sec

Combos apply multipliers to these base values.

### Example Combos

| Resources | Tower | Effect |
|-----------|-------|--------|
| Ember | Ember Tower | Burns enemies (DoT) |
| Frost | Frost Tower | Slows enemies |
| Ember + Frost | Steam Tower | AoE slow + damage |
| Ember + Spark | Plasma Tower | High single-target damage |
| Shadow + Void | Abyss Tower | Very high damage |
| Frost + Earth + Nature | Glacier Tower | Wide freeze AoE |
| All 5 primal (1-5) | Primal Tower | Devastating AoE |
| All 5 upper (6-10) | Ascendant Tower | Massive slow + damage |

### Cursed Combos (bad outcomes)

Some combinations cancel each other out or backfire:

| Resources | Tower | Problem |
|-----------|-------|---------|
| Shadow + Radiance | Cursed Tower | Nearly useless |
| Ember + Spore | Ash Tower | Fire burns the spores |
| Frost + Spark | Short Circuit | Ice kills the lightning |
| Fire+Nature+Shadow+Light (4) | Chaos Tower | Hits allies too |
| Shadow+Arcane+Void+Light (4) | Null Tower | Does nothing |

Players can see the combo preview (name, description, stats) before placing, so cursed combos are a risk/reward decision.

---

## Waves

- Enemies spawn in groups and walk the map path
- Wave difficulty scales every round: +8% enemy health, slight speed creep
- Enemy variety increases over time (Grunts early → Armored + Swarm late)
- Boss every 5 rounds, boss tier upgrades at rounds 20, 50, 100

### Enemy Types

| Name | Role |
|------|------|
| Grunt | Basic, balanced |
| Runner | Fast, low health |
| Brute | Slow, tanky |
| Swarm | Tiny, many, fast |
| Armored | High health, slow |
| Bosses | Scaled versions of above, drop resources |

---

## Maps

3 maps with different path layouts, each with 50 tower grid slots.

| Map | Layout |
|-----|--------|
| Greenfield | S-curve path |
| Dustlands | Spiral inward |
| Ironpass | Zigzag gauntlet |

---

## Multiplayer

- All players share the same base health and wave state
- Each player has their own money and resource inventory
- Any player can place towers anywhere on the grid
- Boss resource drops go to all players simultaneously

---

## Tech Stack

- Roblox / Luau
- Rojo for file sync
- Aftman for toolchain management

### Project Structure

```
src/
  shared/
    Types.luau         -- type definitions
    ResourceData.luau  -- resource themes + drop curve
    TowerData.luau     -- combo recipes + stat resolution
    WaveData.luau      -- enemy types + wave generation
    EnemyPath.luau     -- map waypoints + tower slots
  server/
    GameManager.luau   -- state machine + remote wiring
    EnemyManager.luau  -- spawning + movement + damage
    TowerManager.luau  -- placement + targeting + shooting
    ResourceManager.luau -- inventories + boss drops
    EconomyManager.luau  -- money tracking
  client/
    TowerPlacer.luau   -- grid UI + placement input
    UI.luau            -- HUD + inventory + build panel
```


---

## Release Notes

### 0.9.7
- Fixed critical bug where runes could be lost when leaving the game (runes are now properly saved before cleanup)
- Made lobby loadout selector responsive to screen size

### 0.9.6
- Made turret shop, rune inventory bar, rune panel, and rune shop UIs responsive to screen size
- All shop/rune UIs now scale with screen dimensions while maintaining min/max size constraints

### 0.9.5
- Fixed turret placement costs resetting on new round (now only resets when starting a new game from lobby)
- Improved leaderboard score submission reliability

### 0.9.4
- Added weekly leaderboards on front wall showing top 10 players per difficulty
- Implemented difficulty levels per lobby pad: Easy (1x), Medium (1.5x), Hard (2.5x rewards/enemy health)
- Turret placement costs now escalate by 50% for each turret of the same type placed
- Fixed various sync issues with turret costs and leaderboard data storage

### 0.9.3
- Improved turret placement UX: once the ghost preview snaps to a valid pad, clicking anywhere on the screen confirms placement (no longer need to click precisely on the pad)

