# Requirements Document

## Introduction

This feature adds persistent data saving to the tower defense game using Roblox DataStoreService. Currently, persistent coins (managed by EconomyManager) and turret unlocks (managed by LobbyManager) are stored in-memory and reset when the server restarts. This feature ensures player progress survives across server restarts and play sessions.

## Glossary

- **DataStore_Service**: The Roblox DataStoreService API used to read and write persistent key-value data.
- **Data_Manager**: A new server module responsible for saving and loading player data via DataStore_Service.
- **Player_Data**: A structured record containing a player's persistent coins (number) and turret unlocks (table of turret type ids).
- **Save_Operation**: A single call to DataStore_Service:SetAsync or UpdateAsync to persist Player_Data for one player.
- **Load_Operation**: A single call to DataStore_Service:GetAsync to retrieve Player_Data for one player.
- **Scout_Turret**: The default turret (id=1) that is always unlocked for every player at zero cost.
- **Economy_Manager**: The existing server module that tracks persistent coins in memory.
- **Lobby_Manager**: The existing server module that tracks turret unlocks and loadouts in memory.

## Requirements

### Requirement 1: Load Player Data on Join

**User Story:** As a player, I want my coins and turret unlocks to be loaded when I join the server, so that I keep my progress from previous sessions.

#### Acceptance Criteria

1. WHEN a player joins the server, THE Data_Manager SHALL perform a Load_Operation to retrieve the Player_Data for that player from DataStore_Service.
2. WHEN a Load_Operation returns valid Player_Data, THE Data_Manager SHALL initialize Economy_Manager persistent coins with the saved coin value.
3. WHEN a Load_Operation returns valid Player_Data, THE Data_Manager SHALL initialize Lobby_Manager turret unlocks with the saved unlock table.
4. WHEN a Load_Operation returns no data (new player), THE Data_Manager SHALL initialize Economy_Manager persistent coins to 0 and Lobby_Manager turret unlocks to contain only Scout_Turret (id=1).
5. IF a Load_Operation fails due to a DataStore_Service error, THEN THE Data_Manager SHALL initialize the player with default data (0 coins, Scout_Turret only) and log a warning.

### Requirement 2: Save Player Data on Leave

**User Story:** As a player, I want my progress to be saved when I leave the server, so that I do not lose coins or unlocks.

#### Acceptance Criteria

1. WHEN a player leaves the server, THE Data_Manager SHALL perform a Save_Operation to persist the player's current persistent coins and turret unlocks to DataStore_Service.
2. THE Save_Operation SHALL write a Player_Data record containing the persistent coin balance from Economy_Manager and the turret unlock table from Lobby_Manager.
3. IF a Save_Operation fails due to a DataStore_Service error, THEN THE Data_Manager SHALL retry the Save_Operation up to 3 times with a 1-second delay between attempts.
4. IF all retry attempts for a Save_Operation fail, THEN THE Data_Manager SHALL log an error containing the player's UserId.

### Requirement 3: Auto-Save on Interval

**User Story:** As a player, I want my data saved periodically while I play, so that a server crash does not lose significant progress.

#### Acceptance Criteria

1. WHILE a player is connected to the server, THE Data_Manager SHALL perform a Save_Operation for that player at a regular interval of 120 seconds.
2. THE Data_Manager SHALL stagger auto-save intervals across connected players to avoid simultaneous DataStore_Service requests.
3. IF an auto-save Save_Operation fails, THEN THE Data_Manager SHALL log a warning and attempt the save at the next interval.

### Requirement 4: Save All on Server Shutdown

**User Story:** As a player, I want my data saved when the server shuts down, so that progress is not lost during maintenance or restarts.

#### Acceptance Criteria

1. WHEN the server begins shutting down (game:BindToClose), THE Data_Manager SHALL perform a Save_Operation for every connected player before the server process exits.
2. THE Data_Manager SHALL execute all shutdown Save_Operations concurrently to complete within the Roblox BindToClose time limit of 30 seconds.

### Requirement 5: Data Integrity

**User Story:** As a player, I want my saved data to be consistent and correct, so that I do not lose coins or unlocks due to data corruption.

#### Acceptance Criteria

1. THE Data_Manager SHALL store Player_Data using a versioned schema that includes a version number field.
2. WHEN a Load_Operation retrieves Player_Data with an unrecognized or missing version number, THE Data_Manager SHALL migrate the data to the current schema version before use.
3. THE Data_Manager SHALL validate that loaded persistent coins are a non-negative number; IF the value is invalid, THEN THE Data_Manager SHALL default to 0 coins.
4. THE Data_Manager SHALL validate that loaded turret unlocks contain only turret ids that exist in TurretData; IF an unknown id is found, THEN THE Data_Manager SHALL remove the unknown id from the unlock table.
5. THE Data_Manager SHALL ensure Scout_Turret (id=1) is present in the turret unlock table after every Load_Operation, regardless of saved data.
6. FOR ALL valid Player_Data records, saving then loading SHALL produce an equivalent Player_Data record (round-trip property).

### Requirement 6: DataStore Key Format

**User Story:** As a developer, I want a consistent and predictable key format for DataStore entries, so that data can be reliably accessed and debugged.

#### Acceptance Criteria

1. THE Data_Manager SHALL use a DataStore key in the format "PlayerData_{UserId}" where UserId is the player's numeric Roblox UserId.
2. THE Data_Manager SHALL use a single named DataStore called "TowerDefenseData" for all Player_Data records.

### Requirement 7: Expose Data Accessors for Existing Modules

**User Story:** As a developer, I want EconomyManager and LobbyManager to read and write persistent data through Data_Manager, so that save/load logic is centralized.

#### Acceptance Criteria

1. THE Data_Manager SHALL provide a function to get the current Player_Data (coins and unlocks) for a given UserId.
2. THE Data_Manager SHALL provide a function to update persistent coins for a given UserId, which writes to both the in-memory Economy_Manager state and marks the data as dirty for the next save.
3. THE Data_Manager SHALL provide a function to update turret unlocks for a given UserId, which writes to both the in-memory Lobby_Manager state and marks the data as dirty for the next save.
4. WHEN a Save_Operation is triggered, THE Data_Manager SHALL only write to DataStore_Service if the Player_Data has been marked as dirty since the last successful save.
