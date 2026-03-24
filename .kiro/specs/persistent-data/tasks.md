# Implementation Plan: Persistent Data

## Overview

Implement a centralized `DataManager` module that persists player coins and turret unlocks via Roblox DataStoreService. The module loads data on join, saves on leave, auto-saves every 120 seconds, and saves all players on server shutdown. Existing modules (EconomyManager, LobbyManager) keep their in-memory state; DataManager reads/writes through new accessor functions and a dirty-flag mechanism.

## Tasks

- [x] 1. Create DataManager core module
  - [x] 1.1 Create `src/server/DataManager.luau` with module table, DataStore reference (`TowerDefenseData`), PlayerTracker type, and `playerTrackers` table
    - Define `PlayerData` type: `{ version: number, coins: number, unlocks: { number } }`
    - Define `PlayerTracker` type: `{ dirty: boolean, lastSaveTime: number }`
    - Acquire DataStore via `DataStoreService:GetDataStore("TowerDefenseData")`
    - Implement `DataManager.getKey(userId)` returning `"PlayerData_" .. tostring(userId)`
    - _Requirements: 6.1, 6.2, 5.1_

  - [x] 1.2 Implement `DataManager.validatePlayerData(raw)` — validation and migration
    - If `raw` is nil, return default data `{ version = 1, coins = 0, unlocks = { 1 } }`
    - If `version` is missing or unrecognized, migrate to version 1 schema
    - Clamp `coins` to 0 if negative, non-numeric, or nil
    - Filter `unlocks` to only ids present in `TurretData`; remove unknowns
    - Ensure turret id 1 is always present in `unlocks`
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x] 1.3 Implement `DataManager.markDirty(userId)` and `DataManager.getPlayerData(userId)`
    - `markDirty` sets `playerTrackers[userId].dirty = true`
    - `getPlayerData` reads current coins from `EconomyManager.getPersistentCoins` and unlocks from `LobbyManager.getPlayerUnlocks`, returns a `PlayerData` table
    - _Requirements: 7.2, 7.3, 7.4_

- [x] 2. Implement load and save operations
  - [x] 2.1 Implement `DataManager.loadPlayer(player)`
    - Call `DataStoreService:GetAsync` with the player's key, wrapped in `pcall`
    - On success, validate data with `validatePlayerData`, then call `EconomyManager.setPersistentCoins` and `LobbyManager.setPlayerUnlocks`
    - On failure, log warning and initialize with defaults (0 coins, Scout Turret only)
    - Create a `PlayerTracker` entry with `dirty = false`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

  - [x] 2.2 Implement `saveWithRetry(key, data)` helper — retry up to 3 times with 1-second delay
    - Call `DataStoreService:SetAsync` wrapped in `pcall`
    - On failure, wait 1 second and retry (up to 3 attempts total)
    - Return `true` on success, `false` if all retries fail
    - _Requirements: 2.3, 2.4_

  - [x] 2.3 Implement `DataManager.savePlayer(userId)`
    - Skip save if player tracker is not dirty
    - Read current data via `getPlayerData`, call `saveWithRetry`
    - On success, set `dirty = false` and update `lastSaveTime`
    - On total failure, log error with UserId
    - _Requirements: 2.1, 2.2, 7.4_

  - [x] 2.4 Implement `DataManager.removePlayer(userId)` — clean up tracker after save on leave
    - Remove the player's entry from `playerTrackers`
    - _Requirements: 2.1_

- [x] 3. Implement auto-save and shutdown save
  - [x] 3.1 Implement auto-save loop in `DataManager.init()`
    - Spawn a coroutine that loops every 10 seconds, iterating connected players
    - For each player, if 120+ seconds have elapsed since `lastSaveTime`, call `savePlayer`
    - Stagger naturally since each player's `lastSaveTime` starts from their join time
    - On auto-save failure, log warning (data stays dirty for next interval)
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 3.2 Implement `DataManager.saveAllPlayers()` and bind to `game:BindToClose`
    - Iterate all tracked players, spawn concurrent `savePlayer` calls
    - Use `task.spawn` for each player to run concurrently within the 30-second limit
    - _Requirements: 4.1, 4.2_

- [x] 4. Add accessor functions to EconomyManager and LobbyManager
  - [x] 4.1 Add `EconomyManager.setPersistentCoins(userId, amount)` — sets persistent coins to a specific value
    - Set `playerPersistentCoins[userId] = amount`
    - _Requirements: 1.2, 7.2_

  - [x] 4.2 Add `DataManager.markDirty` calls to EconomyManager mutators
    - Add `DataManager.markDirty(userId)` call inside `addPersistentCoins`, `spendPersistentCoins`, and `bankKillEarnings`
    - Require DataManager at the top of EconomyManager
    - _Requirements: 7.2, 7.4_

  - [x] 4.3 Add `LobbyManager.setPlayerUnlocks(userId, unlocks)` and `LobbyManager.getPlayerUnlocks(userId)`
    - `setPlayerUnlocks` sets `playerUnlocks[userId] = unlocks`
    - `getPlayerUnlocks` returns `playerUnlocks[userId] or { [1] = true }`
    - _Requirements: 1.3, 7.3_

  - [x] 4.4 Add `DataManager.markDirty` call to LobbyManager's BuyTurret handler
    - After unlocking a turret in the `BuyTurret` remote handler, call `DataManager.markDirty(userId)`
    - _Requirements: 7.3, 7.4_

- [x] 5. Wire DataManager into LobbyManager lifecycle
  - [x] 5.1 Initialize DataManager from `LobbyManager.init()`
    - Require DataManager and call `DataManager.init()` at the start of `LobbyManager.init()`
    - _Requirements: 1.1_

  - [x] 5.2 Replace PlayerAdded initialization with `DataManager.loadPlayer`
    - In the `Players.PlayerAdded` handler inside `LobbyManager.init()`, replace `playerUnlocks[userId] = { [1] = true }` and `EconomyManager.initPersistentCoins(userId)` with `DataManager.loadPlayer(player)`
    - Keep the rest of the handler (broadcastState, loadout init, etc.) intact
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 5.3 Wire PlayerRemoving to save and clean up via DataManager
    - In the existing `Players.PlayerRemoving` handler, after handling area leave, call `DataManager.savePlayer(userId)` then `DataManager.removePlayer(userId)`
    - _Requirements: 2.1, 2.2_

- [x] 6. Checkpoint — Ensure core save/load works
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Create test harness and property tests
  - [x] 7.1 Create `src/tests/DataTestHarness.luau` with mock DataStoreService and test helpers
    - Mock `GetAsync(key)` and `SetAsync(key, value)` backed by an in-memory table
    - Support configurable failure injection (fail N times then succeed, or always fail)
    - Provide `createTestDataManager()` that returns a DataManager wired to the mock store
    - Add generators: `randomPlayerData()`, `randomRawPlayerData()`, `randomUserId()`, `randomCoinAmount()`, `randomUnlockSet()`
    - _Requirements: 5.6_

  - [x] 7.2 Write property test: Property 1 — Save-Load Round Trip
    - **Property 1: Save-Load Round Trip**
    - Generate random valid PlayerData, save via mock DataStore, load back, assert coins and unlock set are equivalent
    - **Validates: Requirements 5.6, 5.1, 2.2**

  - [x] 7.3 Write property test: Property 2 — Load Initializes In-Memory State
    - **Property 2: Load Initializes In-Memory State**
    - Pre-populate mock DataStore with random valid PlayerData, call loadPlayer, assert EconomyManager and LobbyManager reflect saved values
    - **Validates: Requirements 1.2, 1.3**

  - [x] 7.4 Write property test: Property 3 — Validation Cleans Invalid Data
    - **Property 3: Validation Cleans Invalid Data**
    - Generate random raw data with negative/nil coins and invalid turret ids, run validatePlayerData, assert coins >= 0 and all unlock ids exist in TurretData
    - **Validates: Requirements 5.3, 5.4**

  - [x] 7.5 Write property test: Property 4 — Scout Turret Always Present
    - **Property 4: Scout Turret Always Present**
    - Generate random unlock tables (including empty, missing id 1), run validatePlayerData, assert id 1 is in the result
    - **Validates: Requirements 5.5**

  - [x] 7.6 Write property test: Property 5 — Migration Produces Current Schema
    - **Property 5: Migration Produces Current Schema**
    - Generate raw data with missing/nil/unrecognized version fields, run validatePlayerData, assert result has `version = 1` and all required fields
    - **Validates: Requirements 5.2**

  - [x] 7.7 Write property test: Property 6 — Key Format Consistency
    - **Property 6: Key Format Consistency**
    - Generate random numeric UserIds, call `getKey`, assert result equals `"PlayerData_" .. tostring(userId)`
    - **Validates: Requirements 6.1**

  - [x] 7.8 Write property test: Property 7 — Dirty Flag Controls Save Writes
    - **Property 7: Dirty Flag Controls Save Writes**
    - Load a player (clean state), attempt save, assert no DataStore write. Mark dirty, save, assert DataStore write occurred.
    - **Validates: Requirements 7.4, 7.2, 7.3**

- [x] 8. Register DataPropertyTests in RunPropertyTests
  - [x] 8.1 Update `src/tests/RunPropertyTests.luau` to require and run `DataPropertyTests`
    - Add require for `DataPropertyTests`, add a header block, call `DataPropertyTests.runAll()`, include results in the return table
    - _Requirements: 5.6_

- [x] 9. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- The design specifies Luau throughout; all code uses Luau idioms and Roblox APIs
