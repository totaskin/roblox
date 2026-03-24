-- DataTestHarness.luau
-- A test-friendly reimplementation of DataManager core logic.
-- Provides a mock DataStoreService, mock EconomyManager, mock LobbyManager,
-- and random generators for property-based testing of persistent data logic.
-- Removes all Roblox service dependencies so tests run in isolation.

local TurretData = require(script.Parent.Parent.shared.TurretData)

local DataTestHarness = {}

-- Build a set of valid turret ids from TurretData for fast lookup
local validTurretIds: { [number]: boolean } = {}
for _, turret in TurretData.getAllTurrets() do
	validTurretIds[turret.id] = true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock DataStore
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockDataStore()
	local store = {}
	store._data = {} :: { [string]: any }
	store._failCount = 0 -- fail the next N calls then succeed
	store._alwaysFail = false
	store._getCallCount = 0
	store._setCallCount = 0

	-- Configure failure injection: fail the next N calls then succeed
	function store.failNextN(n: number)
		store._failCount = n
	end

	-- Configure permanent failure mode
	function store.alwaysFail(enabled: boolean)
		store._alwaysFail = enabled
	end

	-- Check if the next call should fail, and consume a failure count if so
	local function shouldFail(): boolean
		if store._alwaysFail then
			return true
		end
		if store._failCount > 0 then
			store._failCount -= 1
			return true
		end
		return false
	end

	function store:GetAsync(key: string): any
		store._getCallCount += 1
		if shouldFail() then
			error("Mock DataStore GetAsync failure")
		end
		return store._data[key]
	end

	function store:SetAsync(key: string, value: any)
		store._setCallCount += 1
		if shouldFail() then
			error("Mock DataStore SetAsync failure")
		end
		store._data[key] = value
	end

	-- Direct access for test assertions (bypasses failure injection)
	function store.peek(key: string): any
		return store._data[key]
	end

	function store.poke(key: string, value: any)
		store._data[key] = value
	end

	function store.reset()
		store._data = {}
		store._failCount = 0
		store._alwaysFail = false
		store._getCallCount = 0
		store._setCallCount = 0
	end

	return store
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Mock EconomyManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockEconomyManager()
	local eco = {}
	local playerPersistentCoins: { [number]: number } = {}

	function eco.initPersistentCoins(userId: number)
		playerPersistentCoins[userId] = 0
	end

	function eco.setPersistentCoins(userId: number, amount: number)
		playerPersistentCoins[userId] = amount
	end

	function eco.getPersistentCoins(userId: number): number
		return playerPersistentCoins[userId] or 0
	end

	function eco.addPersistentCoins(userId: number, amount: number)
		if playerPersistentCoins[userId] then
			playerPersistentCoins[userId] += amount
		end
	end

	function eco.spendPersistentCoins(userId: number, amount: number): boolean
		if (playerPersistentCoins[userId] or 0) >= amount then
			playerPersistentCoins[userId] -= amount
			return true
		end
		return false
	end

	function eco.removePlayer(userId: number)
		playerPersistentCoins[userId] = nil
	end

	return eco
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock LobbyManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockLobbyManager()
	local lobby = {}
	local playerUnlocks: { [number]: { [number]: boolean } } = {}

	function lobby.setPlayerUnlocks(userId: number, unlocks: { [number]: boolean })
		playerUnlocks[userId] = unlocks
	end

	function lobby.getPlayerUnlocks(userId: number): { [number]: boolean }
		return playerUnlocks[userId] or { [1] = true }
	end

	function lobby.removePlayer(userId: number)
		playerUnlocks[userId] = nil
	end

	return lobby
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Test DataManager — reimplements core DataManager logic using mocks
-- ═══════════════════════════════════════════════════════════════════════════

local function createTestDataManager(mockStore: any, mockEconomy: any, mockLobby: any)
	local dm = {}

	-- Per-player tracking
	local playerTrackers: { [number]: { dirty: boolean, lastSaveTime: number } } = {}

	-- Expose for test assertions
	dm.playerTrackers = playerTrackers

	-- Save retry constants (0 delay for tests)
	local MAX_RETRIES = 3

	function dm.getKey(userId: number): string
		return "PlayerData_" .. tostring(userId)
	end

	function dm.validatePlayerData(raw: any): any
		-- Nil or non-table input: return defaults
		if raw == nil or typeof(raw) ~= "table" then
			return { version = 1, coins = 0, unlocks = { 1 } }
		end

		-- Migrate version: if missing or unrecognized, set to 1
		local version = raw.version
		if typeof(version) ~= "number" or version ~= 1 then
			version = 1
		end

		-- Clamp coins: default to 0 if nil, non-numeric, or negative
		local coins = raw.coins
		if typeof(coins) ~= "number" or coins ~= coins then -- NaN check
			coins = 0
		elseif coins < 0 then
			coins = 0
		end

		-- Filter unlocks to only valid turret ids
		local unlocks: { number } = {}
		local seen: { [number]: boolean } = {}
		if typeof(raw.unlocks) == "table" then
			for _, id in raw.unlocks do
				if typeof(id) == "number" and validTurretIds[id] and not seen[id] then
					table.insert(unlocks, id)
					seen[id] = true
				end
			end
		end

		-- Ensure turret id 1 is always present
		if not seen[1] then
			table.insert(unlocks, 1)
		end

		return {
			version = version,
			coins = coins,
			unlocks = unlocks,
		}
	end

	function dm.markDirty(userId: number)
		local tracker = playerTrackers[userId]
		if tracker then
			tracker.dirty = true
		end
	end

	function dm.getPlayerData(userId: number): any
		local coins = mockEconomy.getPersistentCoins(userId)

		-- LobbyManager stores unlocks as { [number]: boolean }, convert to array
		local unlockDict = mockLobby.getPlayerUnlocks(userId)
		local unlocks: { number } = {}
		for id, unlocked in unlockDict do
			if unlocked then
				table.insert(unlocks, id)
			end
		end

		return {
			version = 1,
			coins = coins,
			unlocks = unlocks,
		}
	end

	-- Retry-wrapped save helper (0 delay for tests)
	local function saveWithRetry(key: string, data: any): boolean
		for attempt = 1, MAX_RETRIES do
			local ok, _err = pcall(function()
				mockStore:SetAsync(key, data)
			end)
			if ok then
				return true
			end
			-- No delay in tests
		end
		return false
	end

	function dm.loadPlayer(player: any)
		local userId = player.UserId
		local key = dm.getKey(userId)

		local ok, result = pcall(function()
			return mockStore:GetAsync(key)
		end)

		local data
		if ok then
			data = dm.validatePlayerData(result)
		else
			data = { version = 1, coins = 0, unlocks = { 1 } }
		end

		-- Initialize mock EconomyManager with loaded/default coins
		mockEconomy.setPersistentCoins(userId, data.coins)

		-- Convert unlocks from array to dictionary
		local unlockDict: { [number]: boolean } = {}
		for _, id in data.unlocks do
			unlockDict[id] = true
		end
		mockLobby.setPlayerUnlocks(userId, unlockDict)

		-- Create tracker entry (clean state, just loaded)
		playerTrackers[userId] = {
			dirty = false,
			lastSaveTime = os.clock(),
		}
	end

	function dm.savePlayer(userId: number): boolean
		local tracker = playerTrackers[userId]
		if not tracker or not tracker.dirty then
			return true
		end

		local data = dm.getPlayerData(userId)
		local key = dm.getKey(userId)
		local success = saveWithRetry(key, data)

		if success then
			tracker.dirty = false
			tracker.lastSaveTime = os.clock()
			return true
		end

		return false
	end

	function dm.removePlayer(userId: number)
		playerTrackers[userId] = nil
	end

	return dm
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Random Generators (using math.random since we're outside Roblox)
-- ═══════════════════════════════════════════════════════════════════════════

--- Return a random UserId in [1, 999999].
function DataTestHarness.randomUserId(): number
	return math.random(1, 999999)
end

--- Return a random coin amount in [0, 10000] (including 0 and large values).
function DataTestHarness.randomCoinAmount(): number
	return math.random(0, 10000)
end

--- Return a random set of turret unlock ids — mix of valid (1-6) and invalid (7-99).
function DataTestHarness.randomUnlockSet(): { number }
	local result = {}
	local seen: { [number]: boolean } = {}
	-- Pick a random count of ids (0 to 10)
	local count = math.random(0, 10)
	for _ = 1, count do
		local id
		if math.random() < 0.6 then
			-- 60% chance: valid id (1-6)
			id = math.random(1, 6)
		else
			-- 40% chance: invalid id (7-99)
			id = math.random(7, 99)
		end
		if not seen[id] then
			seen[id] = true
			table.insert(result, id)
		end
	end
	return result
end

--- Generate a valid PlayerData with random coins and random subset of valid turret ids.
--- Always includes turret id 1.
function DataTestHarness.randomPlayerData(): any
	local coins = DataTestHarness.randomCoinAmount()

	-- Build a random subset of valid turret ids (1-6), always including 1
	local unlocks = { 1 }
	local seen: { [number]: boolean } = { [1] = true }
	for id = 2, 6 do
		if math.random() < 0.4 then
			table.insert(unlocks, id)
			seen[id] = true
		end
	end

	return {
		version = 1,
		coins = coins,
		unlocks = unlocks,
	}
end

--- Generate a potentially invalid raw data table for validation testing.
--- May have negative coins, nil coins, string coins, invalid turret ids,
--- missing version, etc.
function DataTestHarness.randomRawPlayerData(): any
	local roll = math.random()

	-- 10% chance: return nil entirely
	if roll < 0.1 then
		return nil
	end

	-- 10% chance: return a non-table value
	if roll < 0.2 then
		local nonTables = { "hello", 42, true }
		return nonTables[math.random(1, #nonTables)]
	end

	-- Build a table with potentially invalid fields
	local raw = {} :: any

	-- Version: 40% valid, 20% missing, 20% wrong type, 20% unrecognized number
	local vRoll = math.random()
	if vRoll < 0.4 then
		raw.version = 1
	elseif vRoll < 0.6 then
		-- missing (nil)
	elseif vRoll < 0.8 then
		raw.version = "one" -- wrong type
	else
		raw.version = math.random(2, 99) -- unrecognized version
	end

	-- Coins: 30% valid, 20% negative, 15% nil, 15% string, 10% zero, 10% large
	local cRoll = math.random()
	if cRoll < 0.3 then
		raw.coins = math.random(0, 5000)
	elseif cRoll < 0.5 then
		raw.coins = -math.random(1, 1000)
	elseif cRoll < 0.65 then
		-- nil (missing)
	elseif cRoll < 0.8 then
		raw.coins = "lots"
	elseif cRoll < 0.9 then
		raw.coins = 0
	else
		raw.coins = math.random(5000, 10000)
	end

	-- Unlocks: 30% valid array, 20% mixed valid/invalid, 20% nil, 15% empty, 15% non-table
	local uRoll = math.random()
	if uRoll < 0.3 then
		raw.unlocks = DataTestHarness.randomUnlockSet()
	elseif uRoll < 0.5 then
		-- Mix of valid and invalid ids
		local mixed = {}
		for _ = 1, math.random(1, 8) do
			table.insert(mixed, math.random(1, 99))
		end
		raw.unlocks = mixed
	elseif uRoll < 0.7 then
		-- nil (missing)
	elseif uRoll < 0.85 then
		raw.unlocks = {}
	else
		raw.unlocks = "not a table"
	end

	return raw
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DataTestHarness.new() — creates an isolated test instance with all mocks
-- ═══════════════════════════════════════════════════════════════════════════

function DataTestHarness.new()
	local self = {} :: any

	self.mockStore = createMockDataStore()
	self.mockEconomy = createMockEconomyManager()
	self.mockLobby = createMockLobbyManager()
	self.dataManager = createTestDataManager(self.mockStore, self.mockEconomy, self.mockLobby)

	-- Expose playerTrackers for direct test assertions
	self.playerTrackers = self.dataManager.playerTrackers

	-- Helper: create a mock player object
	function self.mockPlayer(userId: number?): any
		local uid = userId or DataTestHarness.randomUserId()
		return {
			UserId = uid,
			Name = "Player_" .. uid,
		}
	end

	return self
end

return DataTestHarness
