# Tasks — Lobby System

## Task List

- [x] 1. Refactor GameManager to support per-area instantiation
  - [x] 1.1 Convert module-level state variables into a returned instance table
  - [x] 1.2 Add `GameManager.new(players: { Player }, areaId: number)` constructor
  - [x] 1.3 Add `instance.start()`, `instance.stop()`, and `instance.onGameOver(cb)` methods
  - [x] 1.4 Remove the auto-call to `startIntermission()` from `GameManager.init()`; gate it behind `instance.start()`
  - [x] 1.5 Update `src/server/init.server.luau` to call `LobbyManager.init()` instead of `GameManager.init()`

- [x] 2. Add lobby RemoteEvents
  - [x] 2.1 Add `LobbyState`, `LobbyCountdown`, `LobbyJoinResult`, `LobbyReturnToLobby`, `LobbyShowResults` to the remote creation list in `GameManager.init()` (or move remote setup to a shared helper)

- [x] 3. Implement LobbyManager — pad construction
  - [x] 3.1 Create `src/server/LobbyManager.luau` with `LobbyManager.init()`
  - [x] 3.2 Implement `buildPads()`: create 3 floor parts at fixed world positions with correct size, color, and anchoring
  - [x] 3.3 Add 4 transparent wall parts around each pad floor
  - [x] 3.4 Add a BillboardGui with "Area N" label above each pad floor part
  - [x] 3.5 Store pad floor parts and spawn CFrames in the AreaState table

- [x] 4. Implement LobbyManager — area state machine
  - [x] 4.1 Define `AreaState` table structure with index, status, occupants, countdownRemaining, gameManager, roundReached
  - [x] 4.2 Implement `handleJoin(player, areaIndex)`: validate capacity, in-game guard, single-area guard; add to occupants; fire `LobbyJoinResult`; start countdown if first player
  - [x] 4.3 Implement `handleLeave(player, areaIndex)`: remove from occupants; cancel countdown if area becomes empty; reset to EMPTY
  - [x] 4.4 Implement countdown loop using `task.delay` / `task.spawn`: tick once per second, broadcast `LobbyCountdown`, call `launchGame` at 0
  - [x] 4.5 Implement `launchGame(areaIndex)`: guard on WAITING status; transition to IN_GAME; teleport players; create scoped `GameManager.new()`; call `instance.start()`; wire `onGameOver` callback
  - [x] 4.6 Implement `onGameOver(areaIndex, roundReached)`: transition to RESULTS; fire `LobbyShowResults` to area occupants
  - [x] 4.7 Implement `onPlayerDismissed(player, areaIndex)`: track dismissals; when all occupants dismissed, teleport players to lobby spawn, call `instance.stop()`, reset area to EMPTY
  - [x] 4.8 Implement `broadcastState()`: build `AreaStateSnapshot` array and fire `LobbyState` to all clients
  - [x] 4.9 Connect `Players.PlayerRemoving` to call `handleLeave` for any area the disconnecting player occupies
  - [x] 4.10 On `Players.PlayerAdded`, fire `LobbyState` with current state to the new player
  - [x] 4.11 Wire `Touched` / `TouchEnded` on each pad floor part; filter to humanoid-bearing characters; call `handleJoin` / `handleLeave`
  - [x] 4.12 Wire `LobbyReturnToLobby.OnServerEvent` to call `onPlayerDismissed`

- [x] 5. Implement LobbyClient — area status overlay
  - [x] 5.1 Create `src/client/LobbyClient.luau` with `LobbyClient.init()`
  - [x] 5.2 Build a ScreenGui overlay with 3 area status frames (one per area)
  - [x] 5.3 Implement `updateAreaDisplay(areaStates)`: update each frame's label text based on status, occupantCount, and countdown
  - [x] 5.4 Listen to `LobbyState` remote and call `updateAreaDisplay`
  - [x] 5.5 Listen to `LobbyCountdown` remote and update the relevant area's countdown label
  - [x] 5.6 Listen to `LobbyJoinResult` remote; display rejection message banner on failure
  - [x] 5.7 Highlight the area frame that the local player currently occupies (track via `LobbyState` occupant data)

- [x] 6. Implement LobbyClient — results screen
  - [x] 6.1 Implement `showResults(roundReached, areaIndex)`: create a modal ScreenGui with round reached text and OK button
  - [x] 6.2 OK button click fires `LobbyReturnToLobby` to server with `areaIndex` and dismisses the modal
  - [x] 6.3 Listen to `LobbyShowResults` remote and call `showResults`

- [x] 7. Wire LobbyClient into client init
  - [x] 7.1 Require and call `LobbyClient.init()` from `src/client/init.client.luau`

- [x] 8. Write property-based tests
  - [x] 8.1 Write property test for Property 1: Join/Leave Round Trip
  - [x] 8.2 Write property test for Property 2: Capacity Enforcement
  - [x] 8.3 Write property test for Property 3: Single-Area Occupancy
  - [x] 8.4 Write property test for Property 4: First-Join Starts Countdown
  - [x] 8.5 Write property test for Property 5: Second-Join Triggers Immediate Launch
  - [x] 8.6 Write property test for Property 6: Game Launch Scopes Players Correctly
  - [x] 8.7 Write property test for Property 7: In-Game Area Rejects New Joins
  - [x] 8.8 Write property test for Property 8: Results Screen Shows Correct Round
  - [x] 8.9 Write property test for Property 9: Area Resets After All Dismissals
  - [x] 8.10 Write property test for Property 10: Area Label Reflects State
  - [x] 8.11 Write property test for Property 11: Rejection Triggers Client Message
  - [x] 8.12 Write property test for Property 12: State Broadcast on Every Change
  - [x] 8.13 Write property test for Property 13: New Player Receives Full State
