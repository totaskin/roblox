-- EconomyManager.luau
-- Handles player money: starting balance, earning on kill, spending on towers

local EconomyManager = {}

local playerMoney: { [number]: number } = {}

local STARTING_MONEY = 150

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

return EconomyManager
