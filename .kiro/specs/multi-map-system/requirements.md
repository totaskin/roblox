# Requirements Document

## Introduction

The tower defense game currently has 3 lobby pads but hardcodes "Map1" for every game session. This feature assigns a distinct map to each lobby pad (Pad 1 → Greenfield, Pad 2 → Dustlands, Pad 3 → Random), enhances the existing flat terrain with elevation changes and decorative details, and redesigns the enemy paths to include U-turns so turrets positioned along the path can engage enemies traveling in both directions.

## Glossary

- **Lobby_Pad**: One of the 3 physical start-game platforms in the lobby area, identified by index 1–3.
- **Map_Selector**: The server-side logic that determines which map a Lobby_Pad launches.
- **Map_Builder**: The module (`MapBuilder.luau`) responsible for constructing the visual game world (ground, path tiles, tower slots, terrain details, boundaries).
- **Enemy_Path**: The module (`EnemyPath.luau`) that defines waypoint sequences, tower slot positions, and grid sizes for each map.
- **Terrain_Generator**: The subsystem within Map_Builder that creates elevation changes, hills, rocks, and decorative elements on the ground plane.
- **Game_Manager**: The module (`GameManager.luau`) that orchestrates a game session including map selection, enemy spawning, and tower placement.
- **U_Turn**: A path segment where the enemy route reverses direction by 180 degrees, allowing turrets to fire at enemies on both the approaching and departing legs.
- **World_Offset**: A Vector3 displacement applied to all map geometry to isolate the game area from the lobby.

## Requirements

### Requirement 1: Pad-to-Map Assignment

**User Story:** As a player, I want each lobby pad to launch a specific map, so that I can choose which map to play by stepping on the corresponding pad.

#### Acceptance Criteria

1. WHEN a game launches from Lobby_Pad 1, THE Map_Selector SHALL select "Map1" (Greenfield) as the active map.
2. WHEN a game launches from Lobby_Pad 2, THE Map_Selector SHALL select "Map2" (Dustlands) as the active map.
3. WHEN a game launches from Lobby_Pad 3, THE Map_Selector SHALL select a map at random from the set of all available maps with uniform probability.
4. THE Map_Selector SHALL pass the selected map name to Game_Manager so that Game_Manager uses the selected map for enemy pathing, map building, and tower placement validation.

### Requirement 2: Map Name Display on Lobby Pads

**User Story:** As a player, I want to see which map each pad launches, so that I can make an informed choice before stepping on a pad.

#### Acceptance Criteria

1. THE Lobby_Pad 1 sign SHALL display the text "Greenfield" alongside the area label.
2. THE Lobby_Pad 2 sign SHALL display the text "Dustlands" alongside the area label.
3. THE Lobby_Pad 3 sign SHALL display the text "Random" alongside the area label.

### Requirement 3: Game_Manager Map Parameterization

**User Story:** As a developer, I want Game_Manager to accept a map name parameter, so that each game instance uses the correct map instead of hardcoding "Map1".

#### Acceptance Criteria

1. WHEN Game_Manager creates a new instance, THE Game_Manager SHALL accept a map name parameter and store the map name for the duration of the session.
2. THE Game_Manager SHALL pass the stored map name to Enemy_Path, Map_Builder, and tower placement validation instead of using a hardcoded "Map1" string.
3. WHEN Game_Manager initializes enemy spawning, THE Game_Manager SHALL call `EnemyManager.setMap` with the stored map name.
4. WHEN Game_Manager builds the visual map, THE Game_Manager SHALL call `MapBuilder.build` with the stored map name and the World_Offset.

### Requirement 4: Uneven Terrain Generation

**User Story:** As a player, I want maps to have varied terrain with hills and elevation changes, so that the game world feels detailed and visually interesting rather than flat.

#### Acceptance Criteria

1. WHEN Map_Builder builds a map, THE Terrain_Generator SHALL create a ground surface with elevation variation rather than a single flat plane.
2. THE Terrain_Generator SHALL generate terrain hills using a grid of ground tiles with varying Y-positions, producing height differences of at least 2 studs across the map.
3. THE Terrain_Generator SHALL keep the enemy path corridor at a consistent walkable elevation (Y = 0 relative to World_Offset) so that enemies traverse the path without clipping through terrain.
4. THE Terrain_Generator SHALL place decorative elements (rocks, bushes, trees) on the terrain outside the enemy path corridor to add visual detail.
5. THE Terrain_Generator SHALL apply distinct visual themes per map: Greenfield uses grass and foliage, Dustlands uses sand and rock formations, Ironpass uses metal and industrial elements.

### Requirement 5: U-Turn Path Design

**User Story:** As a player, I want enemy paths to include U-turns, so that I can place turrets in positions where they can shoot enemies traveling in both directions for more strategic gameplay.

#### Acceptance Criteria

1. THE Enemy_Path for each map SHALL include at least two U_Turn segments where the path reverses direction by 180 degrees.
2. THE Enemy_Path SHALL position U_Turn segments so that the approaching leg and the departing leg run parallel within turret firing range (40 studs or less between parallel path segments).
3. THE Enemy_Path SHALL place tower slots between parallel path segments at U_Turn locations so that a turret placed in a tower slot can target enemies on both the approaching and departing legs.
4. FOR ALL maps, THE Enemy_Path waypoint data SHALL produce a valid continuous path from start to end with no waypoint gaps exceeding 120 studs.

### Requirement 6: Per-Instance Map Isolation

**User Story:** As a developer, I want each game instance to build and clean up its own map visuals, so that multiple concurrent games from different pads do not interfere with each other.

#### Acceptance Criteria

1. WHEN Map_Builder builds a map, THE Map_Builder SHALL use a unique folder name that includes the area index (e.g., "MapVisuals_1") instead of a shared "MapVisuals" folder.
2. WHEN a game instance stops, THE Game_Manager SHALL destroy only the map visuals folder belonging to that instance.
3. IF two game instances are running concurrently, THEN THE Map_Builder SHALL maintain separate visual folders so that stopping one game does not remove the other game's map geometry.

### Requirement 7: Random Map Selection Fairness

**User Story:** As a player, I want the random pad to give each map an equal chance of being selected, so that the randomization feels fair.

#### Acceptance Criteria

1. WHEN Lobby_Pad 3 triggers a game launch, THE Map_Selector SHALL retrieve the list of all available map names from Enemy_Path.getMapNames().
2. THE Map_Selector SHALL select one map from the list using a uniform random index (each map has equal probability of selection).
3. WHEN the random map is selected, THE Map_Selector SHALL announce the selected map name to all occupants of the pad via a client remote event before the game starts.
