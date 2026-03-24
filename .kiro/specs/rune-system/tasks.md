# Tasks: Rune System

## Task 1: Create RuneCombinationData shared module
- [x] 1.1 Create `src/shared/RuneCombinationData.luau` with SingleEffects table defining stat multipliers and special effects for all 10 rune types (Ember 1.15x damage, Frost slow, Spark 1.2x fireRate, Spore poison, Shadow 1.1x damage + crit, Radiance 1.1x range + 1.05x damage, Stone 1.25x range, Gale 1.15x fireRate + 1.05x range, Arcane 1.2x damage + 1.1x fireRate, Void 1.3x damage + 0.9x fireRate)
- [x] 1.2 Add PairEffects table with synergy pairs (Ember+Spark, Frost+Gale, Spore+Radiance, Shadow+Void, Stone+Arcane) and clash pairs (Ember+Frost, Shadow+Radiance, Spore+Void, Spark+Stone, Gale+Stone) with multipliers as defined in design
- [x] 1.3 Implement `getSingleEffect(runeTypeId)`, `getPairEffect(runeTypeA, runeTypeB)` (canonical key ordering), and `computeCombinedMultipliers(runeSlot)` utility functions

## Task 2: Create RuneManager server module
- [x] 2.1 Create `src/server/RuneManager.luau` with player rune inventory state (`playerRuneInventories`), turret rune slot state (`turretRuneSlots`), and game phase tracking
- [x] 2.2 Implement `initPlayer(userId)` (zero counts for all 10 types), `removePlayer(userId)`, `getInventory(userId)`, and `setGamePhase(phase)`
- [x] 2.3 Implement `awardBossDrop(userIds, round)` using `ResourceData.rollResourceDrop(round)` to pick rune type, increment each player's inventory, return the awarded rune type id
- [x] 2.4 Implement `applyRune(userId, turretInstanceId, runeTypeId)` with validation (ownership, inventory count > 0, intermission phase, valid turret, valid rune type), decrement inventory, add to rune slot, call `recomputeTurretStats`
- [x] 2.5 Implement `recomputeTurretStats(turretInstanceId)` — read turret base stats and level from TurretManager, compute combined rune multipliers via RuneCombinationData, write final stats back to turret instance and update model attributes
- [x] 2.6 Implement `returnAllRunes()` — iterate all turret rune slots, increment owning player inventories, clear all slots
- [x] 2.7 Implement `getTurretRunes(turretInstanceId)` and `clearAll()` for cleanup

## Task 3: Integrate RuneManager with GameManager
- [x] 3.1 Add `RuneManager` require to GameManager and register remote events: `ApplyRune`, `ApplyRuneResult`, `RuneInventoryUpdate`, `TurretRunesUpdate`
- [x] 3.2 In `onPlayerAdded`, call `RuneManager.initPlayer(userId)`; in `onPlayerRemoving`, call `RuneManager.removePlayer(userId)`
- [x] 3.3 In `onEnemyKilled`, when `enemyData.isBoss`, call `RuneManager.awardBossDrop(userIds, round)` and fire `RuneInventoryUpdate` to each player
- [x] 3.4 In `setGameOver`, call `RuneManager.returnAllRunes()` before `EnemyManager.clearAll()`, then fire `RuneInventoryUpdate` to each player with final inventory
- [x] 3.5 In state transitions (intermission start, wave start), call `RuneManager.setGamePhase()` with the appropriate phase string
- [x] 3.6 Add `ApplyRune` OnServerEvent handler that validates args and delegates to `RuneManager.applyRune`, fires `ApplyRuneResult` to requesting player, and broadcasts `TurretRunesUpdate` + `RuneInventoryUpdate` on success

## Task 4: Add rune visual feedback to turret models
- [x] 4.1 In `RuneManager.recomputeTurretStats`, after updating stats, add/update a neon glow Part on the turret model colored by the rune type (or blended color for multiple runes)
- [x] 4.2 Update the turret's BillboardGui to list applied rune names below the level label
- [x] 4.3 Set model attributes `TurretDamage`, `TurretRange`, `TurretFireRate` with the rune-modified stats so clients can read them

## Task 5: Create RuneHUD client module
- [x] 5.1 Create `src/client/RuneHUD.luau` with `init()`, `show()`, `hide()` functions and a rune inventory display (10 rune type slots with counts, using ResourceData colors/names)
- [x] 5.2 Implement rune application panel: when player clicks a placed turret during intermission, show panel with rune buttons (greyed out if count is 0), current turret runes, and stat preview using RuneCombinationData
- [x] 5.3 Wire `ApplyRune` remote: on rune button click, fire `ApplyRune(turretInstanceId, runeTypeId)` to server
- [x] 5.4 Wire `ApplyRuneResult` remote: display error message for 3 seconds on rejection
- [x] 5.5 Wire `RuneInventoryUpdate` remote: update displayed inventory counts
- [x] 5.6 Wire `TurretRunesUpdate` remote: update turret rune display and stat preview if panel is open for that turret

## Task 6: Integrate RuneHUD with client init
- [x] 6.1 Add `RuneHUD = require(script.RuneHUD)` and `RuneHUD.init()` to `src/client/init.client.luau`
- [x] 6.2 Show RuneHUD during game (alongside TurretHUD) and hide during lobby/results

## Task 7: Add rune generators to PropertyGen
- [x] 7.1 Add `PropertyGen.runeTypeId()` returning random int in [1, 10], `PropertyGen.runeSlot(maxSize)` returning random list of rune type ids, and `PropertyGen.runeInventory()` returning random inventory table with counts in [0, 5]

## Task 8: Create RuneTestHarness
- [x] 8.1 Create `src/tests/RuneTestHarness.luau` with mock RuneManager (in-memory state, no Roblox deps), mock turret data integration, and helper functions for setting up test scenarios (player with inventory, turret with runes, etc.)

## Task 9: Implement RunePropertyTests
- [x] 9.1 Create `src/tests/RunePropertyTests.luau` with test runner structure matching TurretPropertyTests pattern
- [x] 9.2 Implement Property 1: Boss Drop Awards Exactly One Rune Per Player — generate random round and player ids, call awardBossDrop, verify each player's total inventory increased by exactly 1 and awarded id is in [1,10] (Feature: rune-system, Property 1)
- [x] 9.3 Implement Property 2: Inventory Non-Negative Invariant — generate random operation sequences (init, award, apply, return), verify all counts remain >= 0 and freshly initialized players have all zeros (Feature: rune-system, Property 2)
- [x] 9.4 Implement Property 3: Ownership Validation — generate player/turret pairs where player doesn't own turret, verify applyRune returns (false, "Not your turret") with no state change (Feature: rune-system, Property 3)
- [x] 9.5 Implement Property 4: Empty Inventory Validation — generate scenarios with zero-count rune types, verify applyRune returns (false, "No runes of this type available") with no state change (Feature: rune-system, Property 4)
- [x] 9.6 Implement Property 5: Phase Validation — set game phase to non-intermission values, verify applyRune returns (false, "Runes can only be applied during intermission") with no state change (Feature: rune-system, Property 5)
- [x] 9.7 Implement Property 6: Valid Application Transfer — generate valid scenarios, verify inventory decrements by 1 and rune slot grows by 1 (Feature: rune-system, Property 6)
- [x] 9.8 Implement Property 7: Combination Table Completeness — for all 45 unique pairs, verify getPairEffect returns valid type and is order-independent (Feature: rune-system, Property 7)
- [x] 9.9 Implement Property 8: Combined Multiplier Computation — generate random rune slots, verify computeCombinedMultipliers matches manual product of single + pair effects (Feature: rune-system, Property 8)
- [x] 9.10 Implement Property 9: Synergy/Clash Direction — for all synergy pairs verify at least one multiplier > 1, for all clash pairs verify at least one multiplier < 1 (Feature: rune-system, Property 9)
- [x] 9.11 Implement Property 10: Single-Rune Effects — for each rune type id, verify getSingleEffect returns correct multipliers matching requirements (Feature: rune-system, Property 10)
- [x] 9.12 Implement Property 11: Rune Slot Persistence — apply runes, change game phase, verify rune slots unchanged (Feature: rune-system, Property 11)
- [x] 9.13 Implement Property 12: Rune Return Round Trip — set up turrets with runes, call returnAllRunes, verify inventories restored and all slots cleared (Feature: rune-system, Property 12)
