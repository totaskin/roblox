-- DataManager.luau
-- Centralized module for persisting player data (coins, turret unlocks, and runes)
-- via Roblox DataStoreService. Loads on join, saves on leave, auto-saves,
-- and saves all on server shutdown.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local TurretData = require(game.ReplicatedStorage.Shared.TurretData)

-- Lazy-require to break circular dependency (DataManager <-> EconomyManager <-> LobbyManager)
local EconomyManager
local LobbyManager
local RuneManager
local function getEconomyManager()
	if not EconomyManager then
		EconomyManager = require(script.Parent.EconomyManager)
	end
	return EconomyManager
end
local function getLobbyManager()
	if not LobbyManager then
		LobbyManager = require(script.Parent.LobbyManager)
	end
	return LobbyManager
end
local function getRuneManager()
	if not RuneManager then
		RuneManager = require(script.Parent.RuneManager)
	end
	return RuneManager
end

local DataManager = {}

-- Types
export type PlayerData = {
	version: number,
	coins: number,
	unlocks: { number },
	loadout: { number }?,
	runes: { [number]: number }?,
}

export type PlayerTracker = {
	dirty: boolean,
	lastSaveTime: number,
}

-- DataStore reference (lazy-initialized to avoid errors in unpublished places)
local dataStore = nil
local function getDataStore()
	if not dataStore then
		dataStore = DataStoreService:GetDataStore("TowerDefenseData")
	end
	return dataStore
end

-- Per-player tracking for dirty flag and auto-save timing
local playerTrackers: { [number]: PlayerTracker } = {}

-- Generate the DataStore key for a given userId
function DataManager.getKey(userId: number): string
	return "PlayerData_" .. tostring(userId)
end

-- Build a set of valid turret ids from TurretData for fast lookup
local validTurretIds: { [number]: boolean } = {}
for _, turret in TurretData.getAllTurrets() do
	validTurretIds[turret.id] = true
end

-- Validate and migrate raw data loaded from DataStore.
-- Returns a clean PlayerData table conforming to the current schema (version 1).
function DataManager.validatePlayerData(raw: any): PlayerData
	-- Nil or non-table input: return defaults
	if raw == nil or typeof(raw) ~= "table" then
		return { version = 1, coins = 0, unlocks = { 1 }, runes = {} }
	end

	-- Migrate version: if missing or unrecognized, set to 1
	local version = raw.version
	if typeof(version) ~= "number" or version ~= 1 then
		version = 1
	end

	-- Clamp coins: default to 0 if nil, non-numeric, or negative
	local coins = raw.coins
	if typeof(coins) ~= "number" or coins ~= coins then -- NaN check: coins ~= coins
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

	-- Validate loadout: array of up to 3 valid turret ids that are in unlocks
	local loadout: { number } = {}
	local unlockSet: { [number]: boolean } = {}
	for _, id in unlocks do
		unlockSet[id] = true
	end
	if typeof(raw.loadout) == "table" then
		for _, id in raw.loadout do
			if typeof(id) == "number" and unlockSet[id] and #loadout < 3 then
				table.insert(loadout, id)
			end
		end
	end

	-- Validate runes: dictionary of rune id (1-10) to count (non-negative integer)
	local runes: { [number]: number } = {}
	if typeof(raw.runes) == "table" then
		for id, count in pairs(raw.runes) do
			local numId = tonumber(id)
			if numId and numId >= 1 and numId <= 10 and typeof(count) == "number" and count >= 0 then
				runes[numId] = math.floor(count)
			end
		end
	end

	return {
		version = version,
		coins = coins,
		unlocks = unlocks,
		loadout = loadout,
		runes = runes,
	}
end

-- Mark a player's data as dirty (needs saving on next save cycle).
function DataManager.markDirty(userId: number)
	local tracker = playerTrackers[userId]
	if tracker then
		tracker.dirty = true
	end
end

-- Get the current PlayerData for a userId by reading from in-memory modules.
-- Reads coins from EconomyManager, unlocks from LobbyManager, and runes from RuneManager.
function DataManager.getPlayerData(userId: number): PlayerData
	local coins = getEconomyManager().getPersistentCoins(userId)

	-- LobbyManager stores unlocks as { [number]: boolean }, convert to array
	local unlockDict = getLobbyManager().getPlayerUnlocks(userId)
	local unlocks: { number } = {}
	for id, unlocked in unlockDict do
		if unlocked then
			table.insert(unlocks, id)
		end
	end

	-- Get runes from RuneManager
	local runes = getRuneManager().getInventory(userId)

	return {
		version = 1,
		coins = coins,
		unlocks = unlocks,
		loadout = getLobbyManager().getPlayerLoadout(userId),
		runes = runes,
	}
end

-- Auto-save constants
local AUTO_SAVE_INTERVAL = 120
local AUTO_SAVE_CHECK_INTERVAL = 10

-- Save retry constants
local MAX_RETRIES = 3
local RETRY_DELAY = 1

-- Retry-wrapped save helper. Attempts SetAsync up to MAX_RETRIES times with
-- RETRY_DELAY seconds between attempts. Returns true on success, false if all fail.
local function saveWithRetry(key: string, data: PlayerData): boolean
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			getDataStore():SetAsync(key, data)
		end)
		if ok then
			return true
		end
		warn("[DataManager] Save failed for", key, "attempt", attempt, ":", err)
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY)
		end
	end
	return false
end

-- Load player data from DataStore and initialize EconomyManager + LobbyManager + RuneManager state.
-- Called from PlayerAdded handler.
function DataManager.loadPlayer(player: Player)
	local userId = player.UserId
	local key = DataManager.getKey(userId)

	local ok, result = pcall(function()
		return getDataStore():GetAsync(key)
	end)

	local data: PlayerData
	if ok then
		data = DataManager.validatePlayerData(result)
	else
		warn("[DataManager] Failed to load data for", key, ":", result)
		data = { version = 1, coins = 0, unlocks = { 1 }, runes = {} }
	end

	-- Initialize EconomyManager with loaded/default coins
	getEconomyManager().setPersistentCoins(userId, data.coins)

	-- Convert unlocks from array { 1, 3, 5 } to dictionary { [1] = true, [3] = true, [5] = true }
	local unlockDict: { [number]: boolean } = {}
	for _, id in data.unlocks do
		unlockDict[id] = true
	end
	getLobbyManager().setPlayerUnlocks(userId, unlockDict)
	getLobbyManager().setPlayerLoadout(userId, data.loadout or {})

	-- Initialize RuneManager with loaded runes
	getRuneManager().setInventory(userId, data.runes or {})

	-- Create tracker entry (clean state, just loaded)
	playerTrackers[userId] = {
		dirty = false,
		lastSaveTime = os.clock(),
	}
end

-- Save player data to DataStore if dirty. Reads current state from
-- EconomyManager + LobbyManager via getPlayerData, then writes with retry.
-- Returns true on success or if no save was needed, false on failure.
function DataManager.savePlayer(userId: number): boolean
	local tracker = playerTrackers[userId]
	if not tracker or not tracker.dirty then
		return true
	end

	local data = DataManager.getPlayerData(userId)
	local key = DataManager.getKey(userId)
	local success = saveWithRetry(key, data)

	if success then
		tracker.dirty = false
		tracker.lastSaveTime = os.clock()
		return true
	end

	warn("[DataManager] Failed to save data for UserId", userId, "after all retries")
	return false
end

-- Clean up player tracking after save on leave.
function DataManager.removePlayer(userId: number)
	playerTrackers[userId] = nil
end

-- Initialize DataManager. Spawns the auto-save loop that checks every
-- AUTO_SAVE_CHECK_INTERVAL seconds and saves players whose data has been
-- dirty for AUTO_SAVE_INTERVAL seconds since their last save.
function DataManager.init()
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				local userId = player.UserId
				local tracker = playerTrackers[userId]
				if tracker and tracker.dirty and (os.clock() - tracker.lastSaveTime) >= AUTO_SAVE_INTERVAL then
					local success = DataManager.savePlayer(userId)
					if not success then
						warn("[DataManager] Auto-save failed for UserId", userId)
					end
				end
			end
		end
	end)

	game:BindToClose(function()
		DataManager.saveAllPlayers()
	end)
end

-- Save all tracked players concurrently. Called from game:BindToClose
-- to persist all dirty data within the 30-second shutdown limit.
function DataManager.saveAllPlayers()
	local threads = {}
	for userId, tracker in playerTrackers do
		if tracker.dirty then
			local thread = task.spawn(function()
				DataManager.savePlayer(userId)
			end)
			table.insert(threads, thread)
		end
	end
end

return DataManager
