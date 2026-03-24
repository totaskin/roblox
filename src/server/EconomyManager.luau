-- EconomyManager.luau
-- Handles player money: starting balance, earning on kill, spending on towers
-- Extended with session coins, persistent coins, and kill earnings for the turret system

-- Lazy-require to break circular dependency (EconomyManager <-> DataManager)
local DataManager
local function getDataManager()
	if not DataManager then
		DataManager = require(script.Parent.DataManager)
	end
	return DataManager
end

local EconomyManager = {}

local playerMoney: { [number]: number } = {}

local STARTING_MONEY = 150

-- Turret system coin pools
local playerSessionCoins: { [number]: number } = {}
local playerPersistentCoins: { [number]: number } = {}
local playerKillEarnings: { [number]: number } = {}

function EconomyManager.initPlayer(userId: number)
	playerMoney[userId] = STARTING_MONEY
end

function EconomyManager.removePlayer(userId: number)
	playerMoney[userId] = nil
end

function EconomyManager.getMoney(userId: number): number
	return playerMoney[userId] or 0
end

function EconomyManager.addMoney(userId: number, amount: number)
	if playerMoney[userId] then
		playerMoney[userId] += amount
	end
end

-- Returns true and deducts if affordable, false otherwise
function EconomyManager.spend(userId: number, amount: number): boolean
	if (playerMoney[userId] or 0) >= amount then
		playerMoney[userId] -= amount
		return true
	end
	return false
end

-- Session coins (in-game, reset per session)

function EconomyManager.initSessionCoins(userId: number, startingAmount: number)
	playerSessionCoins[userId] = startingAmount
end

function EconomyManager.getSessionCoins(userId: number): number
	return playerSessionCoins[userId] or 0
end

function EconomyManager.addSessionCoins(userId: number, amount: number)
	if playerSessionCoins[userId] then
		playerSessionCoins[userId] += amount
	end
end

function EconomyManager.spendSessionCoins(userId: number, amount: number): boolean
	if (playerSessionCoins[userId] or 0) >= amount then
		playerSessionCoins[userId] -= amount
		return true
	end
	return false
end

-- Persistent coins (lobby, persists across sessions)

function EconomyManager.initPersistentCoins(userId: number)
	playerPersistentCoins[userId] = 0
end

function EconomyManager.setPersistentCoins(userId: number, amount: number)
	playerPersistentCoins[userId] = amount
end

function EconomyManager.getPersistentCoins(userId: number): number
	return playerPersistentCoins[userId] or 0
end

function EconomyManager.addPersistentCoins(userId: number, amount: number)
	if playerPersistentCoins[userId] then
		playerPersistentCoins[userId] += amount
		getDataManager().markDirty(userId)
	end
end

function EconomyManager.spendPersistentCoins(userId: number, amount: number): boolean
	if (playerPersistentCoins[userId] or 0) >= amount then
		playerPersistentCoins[userId] -= amount
		getDataManager().markDirty(userId)
		return true
	end
	return false
end

-- Kill earnings tracking (per session)

function EconomyManager.initKillEarnings(userId: number)
	playerKillEarnings[userId] = 0
end

function EconomyManager.addKillEarnings(userId: number, amount: number)
	if playerKillEarnings[userId] then
		playerKillEarnings[userId] += amount
	end
end

function EconomyManager.getKillEarnings(userId: number): number
	return playerKillEarnings[userId] or 0
end

function EconomyManager.bankKillEarnings(userId: number)
	local earnings = playerKillEarnings[userId] or 0
	if earnings > 0 and playerPersistentCoins[userId] then
		playerPersistentCoins[userId] += earnings
		getDataManager().markDirty(userId)
	end
	playerKillEarnings[userId] = 0
end

return EconomyManager
