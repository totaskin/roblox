-- DataPropertyTests.luau
-- Property-based tests for the Persistent Data System.
-- Uses a lightweight check-based approach with randomised inputs.
-- Each property runs a minimum of 100 iterations.
--
-- To run: require this module and call DataPropertyTests.runAll()
-- Each test returns { passed: boolean, property: string, failedAt: number? }

local PropertyGen = require(script.Parent.PropertyGen)
local DataTestHarness = require(script.Parent.DataTestHarness)

local ITERATIONS = 100

local DataPropertyTests = {}
DataPropertyTests.results = {}

-- Helper: convert an array of numbers to a sorted array for set comparison
local function toSortedArray(arr: { number }): { number }
	local copy = {}
	for _, v in arr do
		table.insert(copy, v)
	end
	table.sort(copy)
	return copy
end

-- Helper: check if two arrays represent the same set of numbers
local function sameSet(a: { number }, b: { number }): boolean
	local sortedA = toSortedArray(a)
	local sortedB = toSortedArray(b)
	if #sortedA ~= #sortedB then
		return false
	end
	for i = 1, #sortedA do
		if sortedA[i] ~= sortedB[i] then
			return false
		end
	end
	return true
end

-- Helper: check if a value exists in an array
local function arrayContains(arr: { number }, value: number): boolean
	for _, v in arr do
		if v == value then
			return true
		end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: persistent-data, Property 1: Save-Load Round Trip
-- For any valid PlayerData record (non-negative coins, valid turret unlock
-- ids including id 1), saving it to the DataStore and then loading it back
-- should produce an equivalent PlayerData record with the same coin value
-- and the same set of unlock ids.
-- **Validates: Requirements 5.6, 5.1, 2.2**
-- ═══════════════════════════════════════════════════════════════════════════
function DataPropertyTests.property1_SaveLoadRoundTrip(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local data = DataTestHarness.randomPlayerData()
		local harness = DataTestHarness.new()
		local userId = DataTestHarness.randomUserId()
		local key = harness.dataManager.getKey(userId)
		local mockPlayer = harness.mockPlayer(userId)

		-- Pre-populate mock store with the generated data
		harness.mockStore.poke(key, data)

		-- Load the player (reads from store, validates, sets in-memory state)
		harness.dataManager.loadPlayer(mockPlayer)

		-- Mark dirty so save actually writes
		harness.dataManager.markDirty(userId)

		-- Save the player (reads in-memory state, writes to store)
		harness.dataManager.savePlayer(userId)

		-- Read back from mock store
		local loaded = harness.mockStore.peek(key)

		if not loaded then
			return false
		end

		-- Assert coins match
		if loaded.coins ~= data.coins then
			return false
		end

		-- Assert unlock sets are equivalent (same elements, order doesn't matter)
		return sameSet(loaded.unlocks, data.unlocks)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: persistent-data, Property 2: Load Initializes In-Memory State
-- For any valid PlayerData record returned by a Load_Operation, after
-- DataManager.loadPlayer completes, EconomyManager.getPersistentCoins
-- should return the saved coin value and LobbyManager.getPlayerUnlocks
-- should return the saved unlock table.
-- **Validates: Requirements 1.2, 1.3**
-- ═══════════════════════════════════════════════════════════════════════════
function DataPropertyTests.property2_LoadInitializesInMemoryState(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local data = DataTestHarness.randomPlayerData()
		local harness = DataTestHarness.new()
		local userId = DataTestHarness.randomUserId()
		local key = harness.dataManager.getKey(userId)
		local mockPlayer = harness.mockPlayer(userId)

		-- Pre-populate mock store
		harness.mockStore.poke(key, data)

		-- Load the player
		harness.dataManager.loadPlayer(mockPlayer)

		-- Assert EconomyManager has the correct coins
		if harness.mockEconomy.getPersistentCoins(userId) ~= data.coins then
			return false
		end

		-- Assert LobbyManager has the correct unlocks (dict form)
		local unlockDict = harness.mockLobby.getPlayerUnlocks(userId)

		-- Convert saved unlocks array to a set for comparison
		local expectedSet: { [number]: boolean } = {}
		for _, id in data.unlocks do
			expectedSet[id] = true
		end

		-- Check every expected id is in the dict
		for id, _ in expectedSet do
			if not unlockDict[id] then
				return false
			end
		end

		-- Check no extra ids in the dict
		for id, unlocked in unlockDict do
			if unlocked and not expectedSet[id] then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: persistent-data, Property 3: Validation Cleans Invalid Data
-- For any raw data table where coins is negative, non-numeric, or nil,
-- and/or unlocks contains turret ids not present in TurretData, the
-- validation function should produce a PlayerData where coins is a
-- non-negative number and unlocks contains only ids that exist in TurretData.
-- **Validates: Requirements 5.3, 5.4**
-- ═══════════════════════════════════════════════════════════════════════════
function DataPropertyTests.property3_ValidationCleansInvalidData(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local raw = DataTestHarness.randomRawPlayerData()
		local harness = DataTestHarness.new()

		local result = harness.dataManager.validatePlayerData(raw)

		-- Assert coins is a non-negative number
		if typeof(result.coins) ~= "number" then
			return false
		end
		if result.coins < 0 then
			return false
		end

		-- Assert every id in unlocks is a valid turret id (1-6)
		for _, id in result.unlocks do
			if typeof(id) ~= "number" or id < 1 or id > 6 then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: persistent-data, Property 4: Scout Turret Always Present
-- For any loaded PlayerData (including empty unlock tables, tables missing
-- id 1, or nil data), after validation, the unlock table must contain
-- turret id 1.
-- **Validates: Requirements 5.5**
-- ═══════════════════════════════════════════════════════════════════════════
function DataPropertyTests.property4_ScoutTurretAlwaysPresent(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = DataTestHarness.new()

		-- Generate random unlock sets (may be empty, may miss id 1)
		local randomUnlocks = DataTestHarness.randomUnlockSet()
		local raw = { version = 1, coins = 100, unlocks = randomUnlocks }

		local result = harness.dataManager.validatePlayerData(raw)

		-- Assert id 1 is present
		if not arrayContains(result.unlocks, 1) then
			return false
		end

		-- Also test with nil data
		local resultNil = harness.dataManager.validatePlayerData(nil)
		if not arrayContains(resultNil.unlocks, 1) then
			return false
		end

		-- Also test with empty table
		local resultEmpty = harness.dataManager.validatePlayerData({})
		if not arrayContains(resultEmpty.unlocks, 1) then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: persistent-data, Property 5: Migration Produces Current Schema
-- For any raw data table with a missing, nil, or unrecognized version
-- field, the migration function should produce a PlayerData record with
-- the current schema version number and all required fields present.
-- **Validates: Requirements 5.2**
-- ═══════════════════════════════════════════════════════════════════════════
function DataPropertyTests.property5_MigrationProducesCurrentSchema(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = DataTestHarness.new()

		-- Use randomRawPlayerData which may have bad versions
		local raw = DataTestHarness.randomRawPlayerData()

		local result = harness.dataManager.validatePlayerData(raw)

		-- Assert version is 1
		if result.version ~= 1 then
			return false
		end

		-- Assert coins field exists and is a number
		if typeof(result.coins) ~= "number" then
			return false
		end

		-- Assert unlocks field exists and is a table
		if typeof(result.unlocks) ~= "table" then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: persistent-data, Property 6: Key Format Consistency
-- For any numeric UserId, the DataStore key generated by DataManager
-- should equal the string "PlayerData_" concatenated with the string
-- representation of that UserId.
-- **Validates: Requirements 6.1**
-- ═══════════════════════════════════════════════════════════════════════════
function DataPropertyTests.property6_KeyFormatConsistency(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = DataTestHarness.new()
		local userId = DataTestHarness.randomUserId()

		local key = harness.dataManager.getKey(userId)
		local expected = "PlayerData_" .. tostring(userId)

		return key == expected
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: persistent-data, Property 7: Dirty Flag Controls Save Writes
-- For any player whose data has not been modified since the last successful
-- save, a save operation should not write to DataStoreService. For any
-- player whose data has been modified (marked dirty), a save operation
-- should write to DataStoreService.
-- **Validates: Requirements 7.4, 7.2, 7.3**
-- ═══════════════════════════════════════════════════════════════════════════
function DataPropertyTests.property7_DirtyFlagControlsSaveWrites(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = DataTestHarness.new()
		local userId = DataTestHarness.randomUserId()
		local mockPlayer = harness.mockPlayer(userId)

		-- Load a player (creates clean tracker)
		harness.dataManager.loadPlayer(mockPlayer)

		-- Record current SetAsync call count
		local countBefore = harness.mockStore._setCallCount

		-- Save without marking dirty — should NOT write
		harness.dataManager.savePlayer(userId)

		if harness.mockStore._setCallCount ~= countBefore then
			return false
		end

		-- Mark dirty
		harness.dataManager.markDirty(userId)

		-- Save after marking dirty — should write
		harness.dataManager.savePlayer(userId)

		if harness.mockStore._setCallCount <= countBefore then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Runner
-- ═══════════════════════════════════════════════════════════════════════════

function DataPropertyTests.runAll(): { { name: string, passed: boolean, failedAt: number? } }
	local tests = {
		{ name = "Property 1: Save-Load Round Trip",                fn = DataPropertyTests.property1_SaveLoadRoundTrip },
		{ name = "Property 2: Load Initializes In-Memory State",    fn = DataPropertyTests.property2_LoadInitializesInMemoryState },
		{ name = "Property 3: Validation Cleans Invalid Data",      fn = DataPropertyTests.property3_ValidationCleansInvalidData },
		{ name = "Property 4: Scout Turret Always Present",         fn = DataPropertyTests.property4_ScoutTurretAlwaysPresent },
		{ name = "Property 5: Migration Produces Current Schema",   fn = DataPropertyTests.property5_MigrationProducesCurrentSchema },
		{ name = "Property 6: Key Format Consistency",              fn = DataPropertyTests.property6_KeyFormatConsistency },
		{ name = "Property 7: Dirty Flag Controls Save Writes",     fn = DataPropertyTests.property7_DirtyFlagControlsSaveWrites },
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

	DataPropertyTests.results = results
	return results
end

return DataPropertyTests
