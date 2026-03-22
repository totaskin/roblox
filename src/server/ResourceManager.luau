-- ResourceManager.luau
-- Handles resource inventories and boss drop logic

local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)

local ResourceManager = {}

-- { [userId]: { [resourceId]: count } }
local inventories: { [number]: { [number]: number } } = {}

function ResourceManager.initPlayer(userId: number)
	inventories[userId] = {}
	for i = 1, 10 do
		inventories[userId][i] = 0
	end
end

function ResourceManager.removePlayer(userId: number)
	inventories[userId] = nil
end

function ResourceManager.getInventory(userId: number): { [number]: number }
	return inventories[userId] or {}
end

function ResourceManager.addResource(userId: number, resourceId: number, amount: number?)
	local inv = inventories[userId]
	if not inv then return end
	inv[resourceId] = (inv[resourceId] or 0) + (amount or 1)
end

-- Called when a boss dies — awards one resource to all players in the session
function ResourceManager.awardBossDrop(userIds: { number }, round: number)
	local resourceId = ResourceData.rollResourceDrop(round)
	for _, userId in ipairs(userIds) do
		ResourceManager.addResource(userId, resourceId, 1)
	end
	return resourceId
end

-- Consumes resources for tower placement, returns false if insufficient
function ResourceManager.consumeResources(userId: number, resourceIds: { number }): boolean
	local inv = inventories[userId]
	if not inv then return false end

	-- Count required amounts
	local needed: { [number]: number } = {}
	for _, id in ipairs(resourceIds) do
		needed[id] = (needed[id] or 0) + 1
	end

	-- Check
	for id, count in pairs(needed) do
		if (inv[id] or 0) < count then return false end
	end

	-- Deduct
	for id, count in pairs(needed) do
		inv[id] -= count
	end
	return true
end

return ResourceManager
