# Design Document — Lobby System

## Overview

The Lobby System adds a pre-game waiting area to the tower defense game. The lobby contains 3 independent **Areas**, each represented by a physical pad in the Roblox world. Players walk onto a pad to join an area; a 10-second countdown begins on first entry. When the countdown expires (or a second player joins), a scoped `GameManager` instance launches for that area's players. After the game ends, a results screen is shown and players are returned to the lobby.

The system is split across two new modules:
- `src/server/LobbyManager.luau` — owns all server-side state, pad construction, countdown logic, and game launch.
- `src/client/LobbyClient.luau` — renders the area status overlay and results screen.

The existing `GameManager` is refactored to support per-area instantiation rather than running as a global singleton.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Server                                                     │
│                                                             │
│  init.server.luau                                           │
│    └─ LobbyManager.init()                                   │
│         ├─ builds 3 AreaPads (Parts + walls + BillboardGui) │
│         ├─ maintains AreaState[1..3]                        │
│         ├─ handles Touched / TouchEnded per pad             │
│         └─ on game launch: GameManager.new(players, areaId) │
│              └─ scoped GameManager instance                 │
│                   ├─ EnemyManager (per area)                │
│                   ├─ TowerManager (per area)                │
│                   ├─ EconomyManager (per area)              │
│                   └─ ResourceManager (per area)             │
└─────────────────────────────────────────────────────────────┘
         │  RemoteEvents (ReplicatedStorage.Remotes)
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Client                                                     │
│                                                             │
│  init.client.luau                                           │
│    └─ LobbyClient.init()                                    │
│         ├─ listens to LobbyState, LobbyCountdown            │
│         ├─ renders area status overlay (BillboardGui)       │
│         └─ renders ResultsScreen on LobbyShowResults        │
└─────────────────────────────────────────────────────────────┘
```

### State Machine (per Area)

```
EMPTY ──(first player joins)──► WAITING
  ▲                                │
  │                         (countdown tick)
  │                                │
  │         (2nd player joins      │
  │          OR countdown = 0)     ▼
  │                            IN_GAME
  │                                │
  │                         (game over)
  │                                ▼
  └──(all players dismiss)── RESULTS
```

---

## Components and Interfaces

### LobbyManager (server)

```luau
type AreaState = {
    index: number,           -- 1, 2, or 3
    status: "EMPTY" | "WAITING" | "IN_GAME" | "RESULTS",
    occupants: { Player },
    countdownRemaining: number,  -- seconds, 0 when not active
    gameManager: any?,       -- scoped GameManager instance or nil
    roundReached: number,    -- set on game over, used for results screen
    padFloor: BasePart,      -- the physical floor part
    spawnCFrame: CFrame,     -- where players teleport on game start
}

LobbyManager.init() -> ()
-- Creates Remotes, builds pads, wires touch events, connects PlayerRemoving.

LobbyManager.handleJoin(player: Player, areaIndex: number) -> ()
-- Validates and processes a join request. Fires LobbyJoinResult to player.

LobbyManager.handleLeave(player: Player, areaIndex: number) -> ()
-- Removes player from area. Cancels countdown if area becomes empty.

LobbyManager.launchGame(areaIndex: number) -> ()
-- Transitions area to IN_GAME, teleports players, creates scoped GameManager.

LobbyManager.onGameOver(areaIndex: number, roundReached: number) -> ()
-- Transitions area to RESULTS, fires LobbyShowResults to area occupants.

LobbyManager.onPlayerDismissed(player: Player, areaIndex: number) -> ()
-- Tracks dismissals; resets area to EMPTY when all occupants have dismissed.

LobbyManager.broadcastState() -> ()
-- Fires LobbyState to all clients with current state of all 3 areas.
```

### GameManager refactor

`GameManager` is converted from a module-level singleton to a constructor that returns an instance table:

```luau
-- New API
GameManager.new(players: { Player }, areaId: number) -> GameManagerInstance

type GameManagerInstance = {
    start: () -> (),   -- begins intermission (replaces the auto-start in init())
    stop:  () -> (),   -- tears down the instance (disconnects loops, clears enemies)
    onGameOver: (callback: (roundReached: number) -> ()) -> (),
}
```

The old `GameManager.init()` is kept in `init.server.luau` only for backward compatibility during transition; once LobbyManager is live, `init.server.luau` calls `LobbyManager.init()` instead.

### LobbyClient (client)

```luau
LobbyClient.init() -> ()
-- Wires all lobby RemoteEvent listeners, builds the area overlay UI.

LobbyClient.updateAreaDisplay(areaStates: { AreaStateSnapshot }) -> ()
-- Refreshes all 3 area labels from a state snapshot.

LobbyClient.showResults(roundReached: number, areaIndex: number) -> ()
-- Shows the ResultsScreen modal. OK button fires LobbyReturnToLobby.
```

### RemoteEvents (added to ReplicatedStorage.Remotes)

| Remote | Direction | Payload | Purpose |
|---|---|---|---|
| `LobbyState` | Server → All | `{ {index, status, occupantCount, countdown} }` | Full state sync |
| `LobbyCountdown` | Server → Area players | `areaIndex: number, seconds: number` | Per-tick countdown |
| `LobbyJoinResult` | Server → Player | `success: boolean, reason: string?` | Join accept/reject |
| `LobbyReturnToLobby` | Client → Server | `areaIndex: number` | Player dismissed results |
| `LobbyShowResults` | Server → Area players | `roundReached: number, areaIndex: number` | Trigger results screen |

---

## Data Models

### AreaStateSnapshot (sent over remotes)

```luau
type AreaStateSnapshot = {
    index: number,
    status: "EMPTY" | "WAITING" | "IN_GAME" | "RESULTS",
    occupantCount: number,   -- 0, 1, or 2
    countdown: number,       -- remaining seconds; 0 if not active
}
```

### Physical Pad Layout

3 pads are constructed procedurally at fixed world positions. Each pad consists of:
- **Floor part**: 20×1×20 studs, `Anchored = true`, `CanCollide = true`, colored per area index.
- **4 wall parts**: 20×6×1 studs each, `Anchored = true`, `Transparency = 0.7`, forming a low fence.
- **BillboardGui**: parented to the floor part, displays "Area N" label.

Pad positions (X offset, Y=0, Z=0):
- Area 1: `Vector3.new(-60, 0, 0)`
- Area 2: `Vector3.new(0, 0, 0)`
- Area 3: `Vector3.new(60, 0, 0)`

Spawn CFrames for game start are offset slightly above each pad center.

### Lobby Spawn Position

Players returning from a game are teleported to a fixed lobby spawn `CFrame` (e.g. `CFrame.new(0, 5, -40)`), away from the pads.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Join/Leave Round Trip

*For any* area in EMPTY state and any player, joining then immediately leaving should return the area's occupant list to its original empty state and the area status back to EMPTY.

**Validates: Requirements 1.2, 1.4, 2.4**

---

### Property 2: Capacity Enforcement

*For any* area already containing 2 players, attempting to add a third player should be rejected and the occupant count should remain exactly 2.

**Validates: Requirements 1.3**

---

### Property 3: Single-Area Occupancy

*For any* player already occupying area A, attempting to join area B should result in the player appearing in at most one area's occupant list across all 3 areas.

**Validates: Requirements 1.5**

---

### Property 4: First-Join Starts Countdown

*For any* area in EMPTY state, after the first player joins, the area status should be WAITING and `countdownRemaining` should be 10.

**Validates: Requirements 2.1**

---

### Property 5: Second-Join Triggers Immediate Launch

*For any* area in WAITING state with 1 occupant, adding a second player should transition the area to IN_GAME without waiting for the countdown to reach 0.

**Validates: Requirements 2.3**

---

### Property 6: Game Launch Scopes Players Correctly

*For any* area transitioning to IN_GAME, the GameManager instance created for that area should receive exactly the set of players that were in the area's occupant list at launch time.

**Validates: Requirements 3.1, 7.1**

---

### Property 7: In-Game Area Rejects New Joins

*For any* area in IN_GAME or RESULTS state, any join attempt should be rejected and the area's occupant list should be unchanged.

**Validates: Requirements 3.2**

---

### Property 8: Results Screen Shows Correct Round

*For any* game over event carrying a `roundReached` value, the `LobbyShowResults` remote fired to area players should carry that same `roundReached` value.

**Validates: Requirements 3.5**

---

### Property 9: Area Resets After All Dismissals

*For any* area in RESULTS state with N occupants, after all N players fire `LobbyReturnToLobby`, the area status should be EMPTY and the occupant list should be empty.

**Validates: Requirements 3.6, 7.3**

---

### Property 10: Area Label Reflects State

*For any* area state snapshot, the rendered label string should:
- contain the occupant count (e.g. "1/2") when status is EMPTY or WAITING,
- contain the countdown seconds when status is WAITING and countdown > 0,
- contain an "In Progress" indicator when status is IN_GAME,
- contain a "Full" indicator when occupantCount is 2.

**Validates: Requirements 4.1, 4.3, 4.4, 4.5**

---

### Property 11: Rejection Triggers Client Message

*For any* `LobbyJoinResult` event with `success = false`, the client handler should produce a non-empty rejection message string visible to the player.

**Validates: Requirements 5.3**

---

### Property 12: State Broadcast on Every Change

*For any* state-mutating operation (join, leave, countdown tick, game start, area reset), `broadcastState` should be called, resulting in a `LobbyState` remote fire to all clients.

**Validates: Requirements 6.1**

---

### Property 13: New Player Receives Full State

*For any* player connecting to the server, the `LobbyState` remote should be fired to that player with snapshots for all 3 areas.

**Validates: Requirements 6.2**

---

## Error Handling

| Scenario | Handling |
|---|---|
| Player joins full area (2 players) | `handleJoin` returns early; fires `LobbyJoinResult(false, "Area is full")` to player |
| Player joins in-game area | `handleJoin` returns early; fires `LobbyJoinResult(false, "Game in progress")` to player |
| Player joins area they already occupy | No-op; idempotent |
| Player disconnects mid-countdown | `PlayerRemoving` fires `handleLeave`; if area becomes empty, countdown is cancelled and area resets to EMPTY |
| Player disconnects mid-game | Scoped GameManager continues with remaining players; if 0 players remain, game is ended immediately |
| GameManager instance errors | `pcall` wraps `launchGame`; on failure, area resets to EMPTY and players are returned to lobby spawn |
| TouchEnded fires without prior Touched | Guard: only process leave if player is actually in the area's occupant list |
| Countdown timer fires after area already in IN_GAME | Guard: check `area.status == "WAITING"` before calling `launchGame` |

---

## Testing Strategy

### Dual Testing Approach

Both unit tests and property-based tests are required. Unit tests cover specific examples and integration points; property tests verify universal correctness across randomized inputs.

### Unit Tests

Focus areas:
- `LobbyManager.handleJoin` and `handleLeave` with mock player objects and pre-set area states.
- `LobbyManager.onGameOver` and `onPlayerDismissed` — verify state transitions and remote calls.
- `LobbyClient.updateAreaDisplay` — verify label text for each status variant.
- `LobbyClient.showResults` — verify modal appears with correct round number.
- GameManager constructor: verify `new(players, areaId)` creates an isolated instance.
- Pad construction: verify 3 pads exist with correct part counts and BillboardGui labels after `buildPads()`.

### Property-Based Tests

Use **[TestEZ](https://github.com/Roblox/testez)** with a custom generator helper for Luau (or a lightweight fast-check-style table of generators).

Each property test runs a minimum of **100 iterations**.

Each test is tagged with a comment in the format:
`-- Feature: lobby-system, Property N: <property text>`

| Property | Test Description |
|---|---|
| Property 1 | Generate random area + player; join then leave; assert EMPTY state and empty occupant list |
| Property 2 | Generate area with 2 random players; attempt third join; assert rejection and count = 2 |
| Property 3 | Generate player; join area A; attempt join area B; assert player in ≤ 1 area |
| Property 4 | Generate empty area; first player joins; assert status = WAITING, countdown = 10 |
| Property 5 | Generate WAITING area with 1 player; second player joins; assert status = IN_GAME |
| Property 6 | Generate area with N players (1–2); launch game; assert GameManager receives same player set |
| Property 7 | Generate IN_GAME or RESULTS area; attempt join; assert rejection and unchanged occupants |
| Property 8 | Generate random roundReached; trigger game over; assert LobbyShowResults carries same value |
| Property 9 | Generate RESULTS area with N players; all dismiss; assert EMPTY state |
| Property 10 | Generate random AreaStateSnapshot; render label; assert string contains expected tokens |
| Property 11 | Generate any failed join result; assert client message is non-empty string |
| Property 12 | For each mutating operation; assert broadcastState was called |
| Property 13 | Simulate player join event; assert LobbyState fired with 3 area snapshots |
