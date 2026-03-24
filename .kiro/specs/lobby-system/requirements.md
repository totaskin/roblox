# Requirements Document

## Introduction

The Lobby System provides a pre-game waiting area for the tower defense game. The lobby contains 3 independent game areas. Players can enter any area; once a player enters an area a 10-second countdown begins. When the countdown expires, or when 2 players are present in the area, the game starts for those players as an isolated game instance. Players in different areas play completely separate, independent games.

## Glossary

- **Lobby**: The shared pre-game space containing all 3 game areas.
- **Area**: One of 3 distinct zones in the lobby. Each area hosts at most 2 players and launches one independent game instance.
- **Countdown**: A 10-second timer that begins when the first player enters an Area and triggers game start on expiry.
- **Game_Instance**: An isolated run of the tower defense game (waves, enemies, towers) scoped to the players of one Area.
- **LobbyManager**: The server-side module that owns lobby state, area occupancy, countdown logic, and area pad construction.
- **LobbyClient**: The client-side module that renders the lobby UI, area status, and results screen.
- **GameManager**: The existing server module that manages wave/intermission/game-over state for a Game_Instance.
- **Player**: A Roblox player connected to the server.
- **AreaPad**: A physical floor part in the Roblox world representing one Area. Players walk onto it to join and walk off it to leave.
- **ResultsScreen**: A UI screen shown to Players after a Game_Instance ends, displaying the final round reached. Dismissed by clicking OK.

---

## Requirements

### Requirement 1: Area Occupancy

**User Story:** As a player, I want to enter one of 3 game areas, so that I can be matched into a game with up to one other player.

#### Acceptance Criteria

1. THE LobbyManager SHALL maintain 3 Areas, each identified by an index (1, 2, 3).
2. WHEN a Player enters an Area, THE LobbyManager SHALL add the Player to that Area's occupant list.
3. WHEN a Player enters an Area that already contains 2 Players, THE LobbyManager SHALL reject the entry and keep the Player in the Lobby.
4. WHEN a Player leaves the Lobby or disconnects while in an Area, THE LobbyManager SHALL remove the Player from that Area's occupant list.
5. THE LobbyManager SHALL allow a Player to occupy at most 1 Area at a time.

---

### Requirement 2: Countdown Timer

**User Story:** As a player, I want a countdown to start when I enter an area, so that I know when the game will begin.

#### Acceptance Criteria

1. WHEN the first Player enters an empty Area, THE LobbyManager SHALL start a 10-second Countdown for that Area.
2. WHILE a Countdown is active for an Area, THE LobbyManager SHALL broadcast the remaining seconds to all Players in that Area once per second.
3. WHEN a second Player enters an Area whose Countdown is already active, THE LobbyManager SHALL immediately start the game for that Area without waiting for the Countdown to expire.
4. WHEN all Players leave an Area before the Countdown expires, THE LobbyManager SHALL cancel the Countdown and reset the Area to empty.
5. IF the Countdown reaches 0 seconds and at least 1 Player remains in the Area, THEN THE LobbyManager SHALL start the game for that Area.

---

### Requirement 3: Game Instance Launch

**User Story:** As a player, I want the game to start automatically for my area, so that I can play with whoever joined my area.

#### Acceptance Criteria

1. WHEN a game starts for an Area, THE LobbyManager SHALL pass the list of Players in that Area to a new Game_Instance.
2. WHEN a game starts for an Area, THE LobbyManager SHALL mark that Area as in-game and prevent new Players from entering it.
3. WHEN a game starts for an Area, THE LobbyManager SHALL teleport the Players in that Area to the game map for that Area.
4. THE Game_Instance SHALL run independently; events in one Area's game SHALL NOT affect Players in other Areas.
5. WHEN a Game_Instance ends (game over), THE LobbyManager SHALL display a results screen to the Players of that Area showing the final round reached and outcome.
6. WHEN a Player clicks the OK button on the results screen, THE LobbyClient SHALL return that Player to the Lobby and THE LobbyManager SHALL reset the Area to empty once all Players in that Area have dismissed the results screen.

---

### Requirement 4: Lobby UI — Area Status Display

**User Story:** As a player, I want to see the status of all 3 areas from the lobby, so that I can choose which area to join.

#### Acceptance Criteria

1. THE LobbyClient SHALL display all 3 Areas with their current occupant count (e.g. "1/2 players").
2. WHEN an Area's occupant count changes, THE LobbyClient SHALL update the display within 1 second.
3. WHEN a Countdown is active for an Area, THE LobbyClient SHALL display the remaining seconds for that Area.
4. WHEN an Area is in-game, THE LobbyClient SHALL display that Area as unavailable (e.g. "In Progress").
5. WHEN an Area is full (2 Players), THE LobbyClient SHALL display that Area as full.

---

### Requirement 5: Physical Area Pads — Join and Leave

**User Story:** As a player, I want to walk into a physical pad in the Roblox world to join an area, so that joining feels natural and spatial rather than menu-driven.

#### Acceptance Criteria

1. WHEN a Player's character touches an Area pad, THE LobbyManager SHALL send a join request for that Area on behalf of that Player.
2. WHEN a Player's character exits an Area pad, THE LobbyManager SHALL send a leave request for that Area on behalf of that Player.
3. WHEN THE LobbyManager rejects a join request (Area full or in-game), THE LobbyClient SHALL display a rejection message to the Player.
4. THE LobbyClient SHALL display the current occupant count and countdown for each Area as an informational overlay; joining and leaving are driven by physical touch detection, not UI buttons.
5. WHEN a Player is occupying an Area, THE LobbyClient SHALL indicate which Area the local Player is currently in.

---

### Requirement 6: Server-Client Synchronisation

**User Story:** As a developer, I want lobby state kept in sync between server and clients, so that all players see accurate area status.

#### Acceptance Criteria

1. WHEN any Area's state changes (occupant added, occupant removed, countdown tick, game started, area reset), THE LobbyManager SHALL broadcast the updated Area state to all Players in the Lobby.
2. WHEN a Player joins the server, THE LobbyManager SHALL send the current state of all 3 Areas to that Player.
3. THE LobbyManager SHALL use RemoteEvents under ReplicatedStorage.Remotes for all lobby-related client-server communication, consistent with the existing remote pattern.

---

### Requirement 7: Game State Integration

**User Story:** As a developer, I want the lobby to integrate with the existing GameManager, so that each area runs a proper game instance.

#### Acceptance Criteria

1. WHEN a Game_Instance is created for an Area, THE LobbyManager SHALL initialise a GameManager scoped to the Players of that Area.
2. THE LobbyManager SHALL ensure the global game state begins in State.LOBBY and transitions to State.INTERMISSION only after a game starts for an Area.
3. WHEN a Game_Instance ends, THE LobbyManager SHALL reset the scoped GameManager state so the Area can host a new game.

---

### Requirement 8: Physical Area Pad Construction

**User Story:** As a developer, I want the 3 area pads to be physical structures in the Roblox world, so that players can walk in and out to join or leave an area naturally.

#### Acceptance Criteria

1. THE LobbyManager SHALL construct 3 distinct pad zones in the Lobby world, each corresponding to one Area (index 1, 2, 3).
2. WHEN the Lobby is initialised, THE LobbyManager SHALL create transparent barrier walls around each pad zone to visually delineate the area boundaries.
3. THE LobbyManager SHALL use Roblox Touched and TouchEnded events on each pad's floor part to detect when a Player's character enters or exits the pad zone.
4. WHEN a Player's character enters a pad zone, THE LobbyManager SHALL treat this as a join request for the corresponding Area.
5. WHEN a Player's character exits a pad zone, THE LobbyManager SHALL treat this as a leave request for the corresponding Area.
6. THE LobbyManager SHALL ensure each pad zone is visually distinct and labelled with its Area index so Players can identify which area they are entering.
