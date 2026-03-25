-- MapTestHarness.luau
-- A test-friendly reimplementation of multi-map system core logic.
-- Mirrors the real LobbyManager's pad-to-map resolution and provides
-- geometric helpers for waypoint analysis, all without Roblox service deps.
-- This allows property-based tests to exercise map logic directly.

local EnemyPath = require(script.Parent.Parent.shared.EnemyPath)

local MapTestHarness = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Pad-to-Map Resolution (mirrors LobbyManager)
-- ═══════════════════════════════════════════════════════════════════════════

local PAD_MAP_ASSIGNMENTS = {
	[1] = "Map1",
	[2] = "Map2",
	[3] = "RANDOM",
}

--- Pure logic resolveMapName (uses math.random for pad 3).
function MapTestHarness.resolveMapName(areaIndex: number): string
	local assignment = PAD_MAP_ASSIGNMENTS[areaIndex]
	if assignment == "RANDOM" then
		local allMaps = EnemyPath.getMapNames()
		return allMaps[math.random(1, #allMaps)]
	end
	return assignment
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock Game Instance
-- ═══════════════════════════════════════════════════════════════════════════

--- Mock game instance that stores mapName (mirrors GameManager).
function MapTestHarness.createMockGameInstance(mapName: string?): any
	return { mapName = mapName or "Map1" }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Geometric Helpers
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect U-turns: a U-turn occurs at waypoint i when the direction from
--- i-1→i and i→i+1 have a dot product ≤ 0 (90° or more turn).
--- Returns list of indices where U-turns occur.
function MapTestHarness.detectUTurns(waypoints: { Vector3 }): { number }
	local uturns = {}
	for i = 2, #waypoints - 1 do
		local dirIn = (waypoints[i] - waypoints[i - 1]).Unit
		local dirOut = (waypoints[i + 1] - waypoints[i]).Unit
		if dirIn:Dot(dirOut) <= 0 then
			table.insert(uturns, i)
		end
	end
	return uturns
end

--- Parallel distance: at a U-turn index, measure the perpendicular distance
--- between the approaching leg (i-1 to i) and departing leg (i to i+1).
--- This is the distance between the two parallel path segments.
function MapTestHarness.parallelDistance(waypoints: { Vector3 }, uTurnIndex: number): number
	local prev = waypoints[uTurnIndex - 1]
	local curr = waypoints[uTurnIndex]
	local next = waypoints[uTurnIndex + 1]
	-- The parallel distance is the perpendicular offset between the two legs
	local inDir = (curr - prev).Unit
	-- Project the vector from prev to next onto the perpendicular of inDir
	local toNext = next - prev
	-- Perpendicular component (in XZ plane)
	local perpDist = math.abs(toNext.X * inDir.Z - toNext.Z * inDir.X)
	return perpDist
end

--- Simple distance between two Vector3 points.
function MapTestHarness.distanceBetweenWaypoints(a: Vector3, b: Vector3): number
	return (b - a).Magnitude
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Folder Name Helper
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate folder name for an area index (mirrors MapBuilder logic).
function MapTestHarness.getFolderName(areaId: number): string
	return "MapVisuals_" .. (areaId or 1)
end

return MapTestHarness
