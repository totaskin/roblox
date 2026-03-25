-- MapPropertyTests.luau
-- Property-based tests for the Multi-Map System.
-- Uses a lightweight check-based approach with randomised inputs.
-- Each property runs a minimum of 100 iterations.
--
-- To run: require this module and call MapPropertyTests.runAll()
-- Each test returns { passed: boolean, property: string, failedAt: number? }

local PropertyGen = require(script.Parent.PropertyGen)
local MapTestHarness = require(script.Parent.MapTestHarness)
local EnemyPath = require(script.Parent.Parent.shared.EnemyPath)

local ITERATIONS = 100

local MapPropertyTests = {}
MapPropertyTests.results = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: multi-map-system, Property 1: Pad-to-Map Resolution
-- For any pad index in {1, 2, 3}, resolveMapName returns a string that
-- exists in EnemyPath.getMapNames(). For pad 1, result is always "Map1".
-- For pad 2, result is always "Map2". For pad 3, result is in the list.
-- **Validates: Requirements 1.1, 1.2, 1.3**
-- ═══════════════════════════════════════════════════════════════════════════
function MapPropertyTests.property1_PadToMapResolution(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local padIdx = PropertyGen.padIndex()
		local result = MapTestHarness.resolveMapName(padIdx)

		-- Must be a valid map name
		local allMaps = EnemyPath.getMapNames()
		local found = false
		for _, name in ipairs(allMaps) do
			if name == result then
				found = true
				break
			end
		end
		if not found then return false end

		-- Fixed assignments for pads 1 and 2
		if padIdx == 1 and result ~= "Map1" then return false end
		if padIdx == 2 and result ~= "Map2" then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: multi-map-system, Property 2: Map Name Storage Round Trip
-- For any valid map name, creating a mock game instance with that name
-- and reading back the stored map name returns the same value.
-- **Validates: Requirements 1.4, 3.1**
-- ═══════════════════════════════════════════════════════════════════════════
function MapPropertyTests.property2_MapNameStorageRoundTrip(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local mapName = PropertyGen.mapName()
		local instance = MapTestHarness.createMockGameInstance(mapName)
		return instance.mapName == mapName
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: multi-map-system, Property 3: U-Turn Existence and Parallel Distance
-- For ALL maps, the waypoint sequence contains at least 2 U-turn segments
-- and at each U-turn the parallel legs are within 40 studs.
-- **Validates: Requirements 5.1, 5.2**
-- ═══════════════════════════════════════════════════════════════════════════
function MapPropertyTests.property3_UTurnExistenceAndParallelDistance(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local allMaps = EnemyPath.getMapNames()
		for _, mapName in ipairs(allMaps) do
			local mapData = EnemyPath.getMap(mapName)
			local waypoints = mapData.waypoints
			local uturns = MapTestHarness.detectUTurns(waypoints)

			-- Must have at least 2 U-turns
			if #uturns < 2 then return false end

			-- Each U-turn's parallel legs must be within 40 studs
			for _, idx in ipairs(uturns) do
				local dist = MapTestHarness.parallelDistance(waypoints, idx)
				if dist > 40 then return false end
			end
		end
		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: multi-map-system, Property 4: Tower Slots Cover U-Turn Zones
-- For ALL maps, at each U-turn, at least one tower slot exists within
-- 40 studs of both the approaching and departing path legs.
-- **Validates: Requirements 5.3**
-- ═══════════════════════════════════════════════════════════════════════════
function MapPropertyTests.property4_TowerSlotsCoverUTurnZones(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local allMaps = EnemyPath.getMapNames()
		for _, mapName in ipairs(allMaps) do
			local mapData = EnemyPath.getMap(mapName)
			local waypoints = mapData.waypoints
			local slots = mapData.towerSlots
			local uturns = MapTestHarness.detectUTurns(waypoints)

			for _, uIdx in ipairs(uturns) do
				local prev = waypoints[uIdx - 1]
				local curr = waypoints[uIdx]
				local next = waypoints[uIdx + 1]

				-- Check if any tower slot is within 40 studs of both legs
				local covered = false
				for _, slot in ipairs(slots) do
					local slotPos = Vector3.new(slot[1], 0, slot[2])

					-- Distance to approaching leg (prev → curr)
					local approachDir = (curr - prev).Unit
					local toPrev = slotPos - prev
					local projApproach = toPrev:Dot(approachDir)
					projApproach = math.clamp(projApproach, 0, (curr - prev).Magnitude)
					local closestApproach = prev + approachDir * projApproach
					local distApproach = (slotPos - closestApproach).Magnitude

					-- Distance to departing leg (curr → next)
					local departDir = (next - curr).Unit
					local toCurr = slotPos - curr
					local projDepart = toCurr:Dot(departDir)
					projDepart = math.clamp(projDepart, 0, (next - curr).Magnitude)
					local closestDepart = curr + departDir * projDepart
					local distDepart = (slotPos - closestDepart).Magnitude

					if distApproach <= 40 and distDepart <= 40 then
						covered = true
						break
					end
				end

				if not covered then return false end
			end
		end
		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: multi-map-system, Property 5: Waypoint Continuity
-- For ALL maps, consecutive waypoint distances do not exceed 120 studs
-- and the path has at least 2 waypoints.
-- **Validates: Requirements 5.4**
-- ═══════════════════════════════════════════════════════════════════════════
function MapPropertyTests.property5_WaypointContinuity(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local allMaps = EnemyPath.getMapNames()
		for _, mapName in ipairs(allMaps) do
			local mapData = EnemyPath.getMap(mapName)
			local waypoints = mapData.waypoints

			-- Must have at least 2 waypoints
			if #waypoints < 2 then return false end

			-- Consecutive distances must not exceed 120 studs
			for j = 1, #waypoints - 1 do
				local dist = MapTestHarness.distanceBetweenWaypoints(waypoints[j], waypoints[j + 1])
				if dist > 120 then return false end
			end
		end
		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: multi-map-system, Property 6: Map Visuals Folder Uniqueness
-- For any two distinct area indices, the generated folder names are
-- different strings, ensuring concurrent games don't collide.
-- **Validates: Requirements 6.1, 6.3**
-- ═══════════════════════════════════════════════════════════════════════════
function MapPropertyTests.property6_MapVisualsFolderUniqueness(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		-- Generate two distinct area indices
		local a = PropertyGen.padIndex()
		local b = PropertyGen.padIndex()
		while b == a do
			b = PropertyGen.padIndex()
		end

		local folderA = MapTestHarness.getFolderName(a)
		local folderB = MapTestHarness.getFolderName(b)
		return folderA ~= folderB
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Runner
-- ═══════════════════════════════════════════════════════════════════════════

function MapPropertyTests.runAll(): { { name: string, passed: boolean, failedAt: number? } }
	local tests = {
		{ name = "Property 1: Pad-to-Map Resolution",              fn = MapPropertyTests.property1_PadToMapResolution },
		{ name = "Property 2: Map Name Storage Round Trip",         fn = MapPropertyTests.property2_MapNameStorageRoundTrip },
		{ name = "Property 3: U-Turn Existence and Parallel Distance", fn = MapPropertyTests.property3_UTurnExistenceAndParallelDistance },
		{ name = "Property 4: Tower Slots Cover U-Turn Zones",     fn = MapPropertyTests.property4_TowerSlotsCoverUTurnZones },
		{ name = "Property 5: Waypoint Continuity",                fn = MapPropertyTests.property5_WaypointContinuity },
		{ name = "Property 6: Map Visuals Folder Uniqueness",      fn = MapPropertyTests.property6_MapVisualsFolderUniqueness },
	}

	local results = {}
	local passCount = 0
	local failCount = 0

	for _, test in ipairs(tests) do
		local passed, failedAt = test.fn()
		table.insert(results, {
			name = test.name,
			passed = passed,
			failedAt = failedAt,
		})

		if passed then
			passCount += 1
			print("[PASS] " .. test.name)
		else
			failCount += 1
			print("[FAIL] " .. test.name .. " (failed at iteration " .. tostring(failedAt) .. ")")
		end
	end

	print(string.format("\n=== Results: %d/%d passed, %d failed ===", passCount, #tests, failCount))

	MapPropertyTests.results = results
	return results
end

return MapPropertyTests
