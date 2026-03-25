-- GamepassManager.luau
-- Handles gamepass ownership checks and daily pass tracking.
-- Double Money pass: grants 2x all coin earnings permanently.
-- Double Damage pass: grants 2x all turret damage permanently.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local GamepassManager = {}

-- IMPORTANT: Replace these with your actual gamepass IDs from Roblox after creating them
local DOUBLE_MONEY_GAMEPASS_ID = 1766213446
local DOUBLE_DAMAGE_GAMEPASS_ID = 1768006458

-- Cache of players with active passes for this session
local doubleMoneyPlayers: { [number]: boolean } = {}
local doubleDamagePlayers: { [number]: boolean } = {}

-- TODO: Remove this test override before publishing!
local TEST_USER_IDS = { [9234432295] = true }

-- Check if a player owns a specific gamepass
local function checkGamepass(userId: number, gamepassId: number): boolean
	if TEST_USER_IDS[userId] then return true end
	if gamepassId == 0 then return false end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, gamepassId)
	end)
	return ok and owns == true
end

-- Initialize a player: check gamepass ownership on join
function GamepassManager.initPlayer(player: Player)
	local userId = player.UserId
	doubleMoneyPlayers[userId] = checkGamepass(userId, DOUBLE_MONEY_GAMEPASS_ID)
	doubleDamagePlayers[userId] = checkGamepass(userId, DOUBLE_DAMAGE_GAMEPASS_ID)

	-- Also listen for in-session purchases
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
		if plr.UserId == userId and purchased then
			if passId == DOUBLE_MONEY_GAMEPASS_ID then
				doubleMoneyPlayers[userId] = true
			elseif passId == DOUBLE_DAMAGE_GAMEPASS_ID then
				doubleDamagePlayers[userId] = true
			end
		end
	end)
end

-- Remove player tracking on leave
function GamepassManager.removePlayer(userId: number)
	doubleMoneyPlayers[userId] = nil
	doubleDamagePlayers[userId] = nil
end

-- Returns the coin multiplier for a player (2 if double money active, 1 otherwise)
function GamepassManager.getCoinMultiplier(userId: number): number
	return doubleMoneyPlayers[userId] and 2 or 1
end

-- Returns whether double money is active for a player
function GamepassManager.hasDoubleMoney(userId: number): boolean
	return doubleMoneyPlayers[userId] == true
end

-- Returns the damage multiplier for a player (2 if double damage active, 1 otherwise)
function GamepassManager.getDamageMultiplier(userId: number): number
	return doubleDamagePlayers[userId] and 2 or 1
end

-- Returns whether double damage is active for a player
function GamepassManager.hasDoubleDamage(userId: number): boolean
	return doubleDamagePlayers[userId] == true
end

-- Get the double money gamepass ID (for prompting purchase from client)
function GamepassManager.getGamepassId(): number
	return DOUBLE_MONEY_GAMEPASS_ID
end

-- Get the double damage gamepass ID (for prompting purchase from client)
function GamepassManager.getDoubleDamageGamepassId(): number
	return DOUBLE_DAMAGE_GAMEPASS_ID
end

return GamepassManager
