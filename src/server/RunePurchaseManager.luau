-- RunePurchaseManager.luau
-- Handles Developer Product purchases for runes via Roblox MarketplaceService.
-- Follows the same module pattern as GamepassManager for MarketplaceService integration.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy-require modules to avoid circular dependencies
local RuneManager
local DataManager
local ResourceData

local function getRuneManager()
	if not RuneManager then
		RuneManager = require(script.Parent.RuneManager)
	end
	return RuneManager
end

local function getDataManager()
	if not DataManager then
		DataManager = require(script.Parent.DataManager)
	end
	return DataManager
end

local function getResourceData()
	if not ResourceData then
		ResourceData = require(ReplicatedStorage.Shared.ResourceData)
	end
	return ResourceData
end

-- Helper to get remotes folder
local function getRemotes()
	return ReplicatedStorage:FindFirstChild("Remotes")
end

local RunePurchaseManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Product Configuration (Task 1.1, 1.2)
-- ═══════════════════════════════════════════════════════════════════════════

-- Product configuration type:
-- Single rune: { runeTypeId: number, quantity: number }
-- Bundle: { isBundle: true, quantity: number }

-- IMPORTANT: Replace these placeholder IDs with actual Developer Product IDs from Roblox
-- after creating them in the Game Settings > Monetization > Developer Products section.
local PLACEHOLDER_BASE_ID = 1000000000

-- Rune_Product_Table: Maps Developer Product IDs to reward configurations
local Rune_Product_Table: { [number]: { runeTypeId: number?, quantity: number, isBundle: boolean? } } = {
	-- Single-rune products (one per rune type 1-10, each granting 1 rune)
	[PLACEHOLDER_BASE_ID + 1]  = { runeTypeId = 1,  quantity = 1 }, -- Ember
	[PLACEHOLDER_BASE_ID + 2]  = { runeTypeId = 2,  quantity = 1 }, -- Frost
	[PLACEHOLDER_BASE_ID + 3]  = { runeTypeId = 3,  quantity = 1 }, -- Spark
	[PLACEHOLDER_BASE_ID + 4]  = { runeTypeId = 4,  quantity = 1 }, -- Spore
	[PLACEHOLDER_BASE_ID + 5]  = { runeTypeId = 5,  quantity = 1 }, -- Shadow
	[PLACEHOLDER_BASE_ID + 6]  = { runeTypeId = 6,  quantity = 1 }, -- Radiance
	[PLACEHOLDER_BASE_ID + 7]  = { runeTypeId = 7,  quantity = 1 }, -- Stone
	[PLACEHOLDER_BASE_ID + 8]  = { runeTypeId = 8,  quantity = 1 }, -- Gale
	[3563209747 + 9]  = { runeTypeId = 9,  quantity = 1 }, -- Arcane
	[PLACEHOLDER_BASE_ID + 10] = { runeTypeId = 10, quantity = 1 }, -- Void

	-- Bundle products (grants multiple random runes)
	[PLACEHOLDER_BASE_ID + 100] = { isBundle = true, quantity = 5 }, -- 5 Random Runes
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Duplicate Prevention Cache (Task 1.3)
-- ═══════════════════════════════════════════════════════════════════════════

-- Tracks processed PurchaseIds to prevent duplicate grants within a session
local processedPurchases: { [string]: boolean } = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- ProcessReceipt Callback (Task 2)
-- ═══════════════════════════════════════════════════════════════════════════

-- Process a Developer Product purchase receipt
local function processReceipt(receiptInfo)
	local productId = receiptInfo.ProductId
	local playerId = receiptInfo.PlayerId
	local purchaseId = receiptInfo.PurchaseId

	-- 2.1: Check if product exists in our table
	local productConfig = Rune_Product_Table[productId]
	if not productConfig then
		warn("[RunePurchaseManager] Unknown product ID:", productId, "- rejecting purchase")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 2.2: Check if player is in game
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		-- Player not in game, Roblox will retry on next join
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 2.3: Check for duplicate purchase (idempotency)
	if processedPurchases[purchaseId] then
		-- Already processed, return success without granting again
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 2.7: Wrap grant logic in pcall for error handling
	local success, errorMsg = pcall(function()
		-- Accumulate runes to grant (for atomic granting)
		local runesToGrant: { [number]: number } = {}

		if productConfig.isBundle then
			-- 2.5: Bundle product - roll random runes
			local quantity = productConfig.quantity
			for _ = 1, quantity do
				-- Use bossKillCount of 0 for purchased bundles (base drop rates)
				local runeTypeId = getResourceData().rollResourceDrop(0)
				runesToGrant[runeTypeId] = (runesToGrant[runeTypeId] or 0) + 1
			end
		else
			-- 2.4: Single-rune product
			local runeTypeId = productConfig.runeTypeId
			local quantity = productConfig.quantity
			runesToGrant[runeTypeId] = (runesToGrant[runeTypeId] or 0) + quantity
		end

		-- Grant all runes atomically
		for runeTypeId, quantity in pairs(runesToGrant) do
			getRuneManager().addRunes(playerId, runeTypeId, quantity)
		end

		-- 2.6: Mark data dirty for persistence
		getDataManager().markDirty(playerId)

		-- 2.6: Fire remote events to notify client
		local remotes = getRemotes()
		if remotes then
			local runeInventoryUpdate = remotes:FindFirstChild("RuneInventoryUpdate")
			if runeInventoryUpdate then
				runeInventoryUpdate:FireClient(player, getRuneManager().getInventory(playerId))
			end

			local purchaseSuccess = remotes:FindFirstChild("PurchaseSuccess")
			if purchaseSuccess then
				purchaseSuccess:FireClient(player, runesToGrant)
			end
		end

		print("[RunePurchaseManager] Successfully granted runes for purchase:", purchaseId, "player:", playerId, "product:", productId)
	end)

	if not success then
		-- 2.7: Log error and return NotProcessedYet to allow retry
		warn("[RunePurchaseManager] Error granting runes for PurchaseId:", purchaseId, "Error:", errorMsg)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 2.6: Mark purchase as processed (after successful grant)
	processedPurchases[purchaseId] = true

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Public API
-- ═══════════════════════════════════════════════════════════════════════════

-- Initialize the module and register ProcessReceipt callback
function RunePurchaseManager.init()
	MarketplaceService.ProcessReceipt = processReceipt
	print("[RunePurchaseManager] Initialized and ProcessReceipt callback registered")
end

-- Get the product table (for testing and UI)
function RunePurchaseManager.getProductTable(): { [number]: { runeTypeId: number?, quantity: number, isBundle: boolean? } }
	return Rune_Product_Table
end

-- Get processed purchases cache (for testing)
function RunePurchaseManager.getProcessedPurchases(): { [string]: boolean }
	return processedPurchases
end

-- Clear processed purchases (for testing)
function RunePurchaseManager.clearProcessedPurchases()
	processedPurchases = {}
end

return RunePurchaseManager
