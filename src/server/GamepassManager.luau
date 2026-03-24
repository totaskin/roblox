-- GamepassManager.luau
-- Handles gamepass ownership checks and daily pass tracking.
-- Double Money pass: grants 2x all coin earnings for the calendar day of purchase.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local GamepassManager = {}

-- IMPORTANT: Replace this with your actual gamepass ID from Roblox after creating it
local DOUBLE_MONEY_GAMEPASS_ID = 0 -- Set to your gamepass ID

-- Cache of players with active double money for this session
local doubleMoneyPlayers: { [number]: boolean } = {}

-- Check if a player owns the double money gamepass
local function checkGamepass(userId: number): boolean
	if DOUBLE_MONEY_GAMEPASS_ID == 0 then return false end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, DOUBLE_MONEY_GAMEPASS_ID)
	end)
	return ok and owns == true
end

-- Initialize a player: check gamepass ownership on join
function GamepassManager.initPlayer(player: Player)
	local userId = player.UserId
	doubleMoneyPlayers[userId] = checkGamepass(userId)

	-- Also listen for in-session purchases
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
		if plr.UserId == userId and passId == DOUBLE_MONEY_GAMEPASS_ID and purchased then
			doubleMoneyPlayers[userId] = true
		end
	end)
end

-- Remove player tracking on leave
function GamepassManager.removePlayer(userId: number)
	doubleMoneyPlayers[userId] = nil
end

-- Returns the coin multiplier for a player (2 if double money active, 1 otherwise)
function GamepassManager.getCoinMultiplier(userId: number): number
	return doubleMoneyPlayers[userId] and 2 or 1
end

-- Returns whether double money is active for a player
function GamepassManager.hasDoubleMoney(userId: number): boolean
	return doubleMoneyPlayers[userId] == true
end

-- Get the gamepass ID (for prompting purchase from client)
function GamepassManager.getGamepassId(): number
	return DOUBLE_MONEY_GAMEPASS_ID
end

return GamepassManager
