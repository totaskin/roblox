# Tasks: Multi-Map System

## Task 1: Redesign EnemyPath waypoints with U-turns
- [x] 1.1 Redesign `Map1` (Greenfield) waypoints in `src/shared/EnemyPath.luau` to include at least 2 U-turn segments with parallel legs within 40 studs, no waypoint gap exceeding 120 studs
- [x] 1.2 Redesign `Map2` (Dustlands) waypoints with at least 2 U-turn segments, parallel legs within 40 studs, no gap exceeding 120 studs
- [x] 1.3 Redesign `Map3` (Ironpass) waypoints with at least 2 U-turn segments, parallel legs within 40 studs, no gap exceeding 120 studs
- [x] 1.4 Reposition tower slots for all 3 maps so that slots exist between parallel path segments at each U-turn location, within 40 studs of both legs

## Task 2: Add pad-to-map resolution in LobbyManager
- [x] 2.1 Add `local EnemyPath = require(game.ReplicatedStorage.Shared.EnemyPath)` to `src/server/LobbyManager.luau`
- [x] 2.2 Add `PAD_MAP_ASSIGNMENTS` table mapping pad 1 → "Map1", pad 2 → "Map2", pad 3 → "RANDOM"
- [x] 2.3 Implement `resolveMapName(areaIndex)` function that returns the fixed map name for pads 1/2 and a random map from `EnemyPath.getMapNames()` for pad 3
- [x] 2.4 Update sign labels in `buildPads()` from `"Area " .. i` to `"Greenfield"`, `"Dustlands"`, `"Random"` for pads 1, 2, 3 respectively
- [x] 2.5 Update `launchGame()` to call `resolveMapName(areaIndex)` and pass the result as a 4th argument to `GameManager.new(players, areaId, loadouts, mapName)`
- [x] 2.6 Add `MapSelected` remote event and fire it to pad occupants with the resolved map name before game start (for pad 3 random announcement)

## Task 3: Parameterize GameManager with map name
- [x] 3.1 Update `createInstance` signature in `src/server/GameManager.luau` to accept `mapName` as 4th parameter, store as `self.mapName` (default `"Map1"`)
- [x] 3.2 Update `GameManager.new` to pass `mapName` through to `createInstance`
- [x] 3.3 Replace hardcoded `"Map1"` in `self.init()` — change `EnemyManager.setMap("Map1")` to `EnemyManager.setMap(self.mapName)`
- [x] 3.4 Replace hardcoded `"Map1"` in `MapBuilder.build("Map1", ...)` to `MapBuilder.build(self.mapName, Vector3.new(0, 0, -10000), self.areaId)`
- [x] 3.5 Replace hardcoded `EnemyPath.getMap("Map1")` in `onPlaceTower` with `EnemyPath.getMap(self.mapName)`
- [x] 3.6 In `self.stop()`, destroy `workspace:FindFirstChild("MapVisuals_" .. self.areaId)` instead of relying on shared folder cleanup

## Task 4: Update MapBuilder for per-instance folders and terrain
- [x] 4.1 Update `MapBuilder.build` signature in `src/server/MapBuilder.luau` to accept `areaId` as 3rd parameter
- [x] 4.2 Change folder name from `"MapVisuals"` to `"MapVisuals_" .. (areaId or 1)` and only destroy the matching folder
- [x] 4.3 Add `getMapTheme(mapName)` function returning ground material/color, path material/color, and elevation scale per map (Greenfield: Grass/green, Dustlands: Sand/tan, Ironpass: Metal/grey)
- [x] 4.4 Replace single ground plane with a grid of terrain tiles (e.g., 10x10 grid) with Y-position variation using `math.noise` for elevation, producing at least 2 studs of height difference, skipping tiles that overlap the path corridor
- [x] 4.5 Add `buildDecorations(folder, mapName, worldOffset)` function that places themed decorative parts outside the path corridor (Greenfield: trees/bushes with Grass material, Dustlands: cacti/rock formations with Sand material, Ironpass: pipes/crates with Metal material)
- [x] 4.6 Apply per-map theme colors and materials to path tiles and tower slots using `getMapTheme`

## Task 5: Update MAP_SPAWN in LobbyManager for per-map start positions
- [x] 5.1 Update `MAP_SPAWN` calculation in `launchGame()` to read the first waypoint from `EnemyPath.getMap(mapName)` and offset it, instead of hardcoding Map1's start position

## Task 6: Add map generators to PropertyGen
- [x] 6.1 Add `PropertyGen.mapName()` returning a random map name from `{"Map1", "Map2", "Map3"}`
- [x] 6.2 Add `PropertyGen.padIndex()` returning a random integer in [1, 3]

## Task 7: Create MapTestHarness
- [x] 7.1 Create `src/tests/MapTestHarness.luau` with mock `resolveMapName` function (pure logic replicating LobbyManager's pad-to-map resolution without Roblox deps)
- [x] 7.2 Add geometric helper functions: `detectUTurns(waypoints)` returning list of U-turn indices, `parallelDistance(waypoints, uTurnIndex)` returning distance between parallel legs, `distanceBetweenWaypoints(a, b)` for gap checking

## Task 8: Implement MapPropertyTests
- [x] 8.1 Create `src/tests/MapPropertyTests.luau` with test runner structure matching existing property test patterns
- [x] 8.2 Implement Property 1: Pad-to-Map Resolution — for random pad indices, verify resolveMapName returns a valid map name from EnemyPath.getMapNames(), and pads 1/2 return their fixed assignments (Feature: multi-map-system, Property 1)
- [x] 8.3 Implement Property 2: Map Name Storage Round Trip — for random valid map names, verify creating a mock game instance stores and returns the same map name (Feature: multi-map-system, Property 2)
- [x] 8.4 Implement Property 3: U-Turn Existence and Parallel Distance — for all maps, verify at least 2 U-turns exist and parallel legs are within 40 studs (Feature: multi-map-system, Property 3)
- [x] 8.5 Implement Property 4: Tower Slots Cover U-Turn Zones — for all maps, verify at least one tower slot exists within 40 studs of both parallel legs at each U-turn (Feature: multi-map-system, Property 4)
- [x] 8.6 Implement Property 5: Waypoint Continuity — for all maps, verify consecutive waypoint distances do not exceed 120 studs and path has at least 2 waypoints (Feature: multi-map-system, Property 5)
- [x] 8.7 Implement Property 6: Map Visuals Folder Uniqueness — for any two distinct area indices, verify generated folder names are different strings (Feature: multi-map-system, Property 6)
