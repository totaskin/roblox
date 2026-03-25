-- RunePurchaseTestHarness.luau
-- A test-friendly reimplementation of rune purchase system core logic.
-- Mirrors the real RunePurchaseManager but removes all Roblox service dependencies
-- (no MarketplaceService, no Players service, no RemoteEvents).
-- Uses ResourceData directly (pure data module).
-- This allows property-based tests to exercise purchase logic directly.

local ResourceData = require(script.Parent.Parent.shared.ResourceData)

local RunePurchaseTestHarness = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Product Configuration (mirrors RunePurchaseManager)
-- ═══════════════════════════════════════════════════════════════════════════

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
	[PLACEHOLDER_BASE_ID + 9]  = { runeTypeId = 9,  quantity = 1 }, -- Arcane
	[PLACEHOLDER_BASE_ID + 10] = { runeTypeId = 10, quantity = 1 }, -- Void

	-- Bundle products (grants multiple random runes)
	[PLACEHOLDER_BASE_ID + 100] = { isBundle = true, quantity = 5 }, -- 5 Random Runes
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock RuneManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockRuneManager()
	local rm = {}

	-- State
	local playerRuneInventories: { [number]: { [number]: number } } = {}
	local addRunesCalls: { { userId: number, runeTypeId: number, quantity: number, success: boolean } } = {}
	local shouldFailAddRunes: boolean = false

	-- ── Player Inventory Management ──

	function rm.initPlayer(userId: number)
		local inventory = {}
		for i = 1, 10 do
			inventory[i] = 0
		end
		playerRuneInventories[userId] = inventory
	end

	function rm.removePlayer(userId: number)
		playerRuneInventories[userId] = nil
	end

	function rm.getInventory(userId: number): { [number]: number }
		return playerRuneInventories[userId] or {}
	end

	function rm.setInventory(userId: number, runes: { [number]: number })
		local inventory = {}
		for i = 1, 10 do
			inventory[i] = runes[i] or 0
		end
		playerRuneInventories[userId] = inventory
	end

	-- ── Add Runes (mirrors real RuneManager.addRunes) ──

	function rm.addRunes(userId: number, runeTypeId: number, quantity: number): boolean
		-- Track the call
		local callRecord = {
			userId = userId,
			runeTypeId = runeTypeId,
			quantity = quantity,
			success = false,
		}

		-- Simulate failure if configured
		if shouldFailAddRunes then
			table.insert(addRunesCalls, callRecord)
			error("Simulated addRunes failure")
		end

		-- Validate runeTypeId is in [1, 10]
		if type(runeTypeId) ~= "number" or runeTypeId < 1 or runeTypeId > 10 or runeTypeId ~= math.floor(runeTypeId) then
			table.insert(addRunesCalls, callRecord)
			return false
		end

		-- Validate quantity > 0
		if type(quantity) ~= "number" or quantity <= 0 or quantity ~= math.floor(quantity) then
			table.insert(addRunesCalls, callRecord)
			return false
		end

		-- Get or initialize inventory
		local inventory = playerRuneInventories[userId]
		if not inventory then
			inventory = {}
			for i = 1, 10 do
				inventory[i] = 0
			end
			playerRuneInventories[userId] = inventory
		end

		-- Increment the rune count
		inventory[runeTypeId] = (inventory[runeTypeId] or 0) + quantity

		callRecord.success = true
		table.insert(addRunesCalls, callRecord)
		return true
	end

	-- ── Test Utilities ──

	function rm.getAddRunesCalls(): { { userId: number, runeTypeId: number, quantity: number, success: boolean } }
		return addRunesCalls
	end

	function rm.clearAddRunesCalls()
		addRunesCalls = {}
	end

	function rm.setShouldFailAddRunes(shouldFail: boolean)
		shouldFailAddRunes = shouldFail
	end

	function rm.clearAll()
		playerRuneInventories = {}
		addRunesCalls = {}
		shouldFailAddRunes = false
	end

	return rm
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock DataManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockDataManager()
	local dm = {}

	-- State
	local markDirtyCalls: { number } = {}

	function dm.markDirty(userId: number)
		table.insert(markDirtyCalls, userId)
	end

	function dm.getMarkDirtyCalls(): { number }
		return markDirtyCalls
	end

	function dm.clearMarkDirtyCalls()
		markDirtyCalls = {}
	end

	function dm.clearAll()
		markDirtyCalls = {}
	end

	return dm
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock Players Service
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockPlayersService()
	local ps = {}

	-- State: set of online player userIds
	local onlinePlayers: { [number]: { UserId: number } } = {}

	function ps.addPlayer(userId: number)
		onlinePlayers[userId] = { UserId = userId }
	end

	function ps.removePlayer(userId: number)
		onlinePlayers[userId] = nil
	end

	function ps.GetPlayerByUserId(userId: number): { UserId: number }?
		return onlinePlayers[userId]
	end

	function ps.isPlayerOnline(userId: number): boolean
		return onlinePlayers[userId] ~= nil
	end

	function ps.getOnlinePlayers(): { [number]: { UserId: number } }
		return onlinePlayers
	end

	function ps.clearAll()
		onlinePlayers = {}
	end

	return ps
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock Remotes (tracks fired events)
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockRemotes()
	local remotes = {}

	-- State
	local firedEvents: { { eventName: string, userId: number, payload: any } } = {}

	function remotes.fireClient(eventName: string, userId: number, payload: any)
		table.insert(firedEvents, {
			eventName = eventName,
			userId = userId,
			payload = payload,
		})
	end

	function remotes.getFiredEvents(): { { eventName: string, userId: number, payload: any } }
		return firedEvents
	end

	function remotes.clearFiredEvents()
		firedEvents = {}
	end

	function remotes.clearAll()
		firedEvents = {}
	end

	return remotes
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock RunePurchaseManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockRunePurchaseManager(runeManager: any, dataManager: any, playersService: any, remotes: any)
	local rpm = {}

	-- State
	local processedPurchases: { [string]: boolean } = {}
	local rollResourceDropCalls: { number } = {} -- tracks bossKillCount args

	-- Mock enum values (mirrors Roblox's Enum.ProductPurchaseDecision)
	rpm.PurchaseDecision = {
		PurchaseGranted = "PurchaseGranted",
		NotProcessedYet = "NotProcessedYet",
	}

	-- ── Product Table Access ──

	function rpm.getProductTable(): { [number]: { runeTypeId: number?, quantity: number, isBundle: boolean? } }
		return Rune_Product_Table
	end

	function rpm.getProcessedPurchases(): { [string]: boolean }
		return processedPurchases
	end

	function rpm.clearProcessedPurchases()
		processedPurchases = {}
	end

	-- ── Roll Resource Drop (wrapper to track calls) ──

	function rpm.rollResourceDrop(bossKillCount: number): number
		table.insert(rollResourceDropCalls, bossKillCount)
		return ResourceData.rollResourceDrop(bossKillCount)
	end

	function rpm.getRollResourceDropCalls(): { number }
		return rollResourceDropCalls
	end

	function rpm.clearRollResourceDropCalls()
		rollResourceDropCalls = {}
	end

	-- ── Process Receipt (mirrors real RunePurchaseManager.processReceipt) ──

	function rpm.processReceipt(receiptInfo: { ProductId: number, PlayerId: number, PurchaseId: string }): string
		local productId = receiptInfo.ProductId
		local playerId = receiptInfo.PlayerId
		local purchaseId = receiptInfo.PurchaseId

		-- Check if product exists in our table
		local productConfig = Rune_Product_Table[productId]
		if not productConfig then
			return rpm.PurchaseDecision.NotProcessedYet
		end

		-- Check if player is in game
		local player = playersService.GetPlayerByUserId(playerId)
		if not player then
			return rpm.PurchaseDecision.NotProcessedYet
		end

		-- Check for duplicate purchase (idempotency)
		if processedPurchases[purchaseId] then
			return rpm.PurchaseDecision.PurchaseGranted
		end

		-- Wrap grant logic in pcall for error handling
		local success, errorMsg = pcall(function()
			-- Accumulate runes to grant (for atomic granting)
			local runesToGrant: { [number]: number } = {}

			if productConfig.isBundle then
				-- Bundle product - roll random runes
				local quantity = productConfig.quantity
				for _ = 1, quantity do
					-- Use bossKillCount of 0 for purchased bundles (base drop rates)
					local runeTypeId = rpm.rollResourceDrop(0)
					runesToGrant[runeTypeId] = (runesToGrant[runeTypeId] or 0) + 1
				end
			else
				-- Single-rune product
				local runeTypeId = productConfig.runeTypeId
				local quantity = productConfig.quantity
				runesToGrant[runeTypeId] = (runesToGrant[runeTypeId] or 0) + quantity
			end

			-- Grant all runes atomically
			for runeTypeId, quantity in pairs(runesToGrant) do
				runeManager.addRunes(playerId, runeTypeId, quantity)
			end

			-- Mark data dirty for persistence
			dataManager.markDirty(playerId)

			-- Fire remote events to notify client
			remotes.fireClient("RuneInventoryUpdate", playerId, runeManager.getInventory(playerId))
			remotes.fireClient("PurchaseSuccess", playerId, runesToGrant)
		end)

		if not success then
			-- Log error and return NotProcessedYet to allow retry
			return rpm.PurchaseDecision.NotProcessedYet
		end

		-- Mark purchase as processed (after successful grant)
		processedPurchases[purchaseId] = true

		return rpm.PurchaseDecision.PurchaseGranted
	end

	-- ── Utility ──

	function rpm.clearAll()
		processedPurchases = {}
		rollResourceDropCalls = {}
	end

	return rpm
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RunePurchaseTestHarness.new() — creates an isolated test instance
-- ═══════════════════════════════════════════════════════════════════════════

function RunePurchaseTestHarness.new()
	local self = {} :: any

	-- Create all mock components
	self.runeManager = createMockRuneManager()
	self.dataManager = createMockDataManager()
	self.playersService = createMockPlayersService()
	self.remotes = createMockRemotes()
	self.purchaseManager = createMockRunePurchaseManager(
		self.runeManager,
		self.dataManager,
		self.playersService,
		self.remotes
	)

	-- Expose ResourceData for tests that need it
	self.ResourceData = ResourceData

	-- Expose product table constants
	self.PLACEHOLDER_BASE_ID = PLACEHOLDER_BASE_ID

	-- ═══════════════════════════════════════════════════════════════════════
	-- Helper Functions
	-- ═══════════════════════════════════════════════════════════════════════

	-- Set up a player as online with initialized inventory
	function self.setupPlayer(userId: number, inventory: { [number]: number }?)
		self.playersService.addPlayer(userId)
		self.runeManager.initPlayer(userId)
		if inventory then
			self.runeManager.setInventory(userId, inventory)
		end
	end

	-- Remove a player (simulate offline)
	function self.removePlayer(userId: number)
		self.playersService.removePlayer(userId)
		self.runeManager.removePlayer(userId)
	end

	-- Get player's rune inventory
	function self.getInventory(userId: number): { [number]: number }
		return self.runeManager.getInventory(userId)
	end

	-- Get list of addRunes calls made
	function self.getAddRunesCalls(): { { userId: number, runeTypeId: number, quantity: number, success: boolean } }
		return self.runeManager.getAddRunesCalls()
	end

	-- Get list of markDirty calls made
	function self.getMarkDirtyCalls(): { number }
		return self.dataManager.getMarkDirtyCalls()
	end

	-- Get list of remote events fired
	function self.getRemotesFired(): { { eventName: string, userId: number, payload: any } }
		return self.remotes.getFiredEvents()
	end

	-- Get list of rollResourceDrop calls (for bundle testing)
	function self.getRollResourceDropCalls(): { number }
		return self.purchaseManager.getRollResourceDropCalls()
	end

	-- Check if a player is online
	function self.isPlayerOnline(userId: number): boolean
		return self.playersService.isPlayerOnline(userId)
	end

	-- Get the product table
	function self.getProductTable(): { [number]: { runeTypeId: number?, quantity: number, isBundle: boolean? } }
		return self.purchaseManager.getProductTable()
	end

	-- Get processed purchases cache
	function self.getProcessedPurchases(): { [string]: boolean }
		return self.purchaseManager.getProcessedPurchases()
	end

	-- Process a purchase receipt
	function self.processReceipt(receiptInfo: { ProductId: number, PlayerId: number, PurchaseId: string }): string
		return self.purchaseManager.processReceipt(receiptInfo)
	end

	-- Configure addRunes to fail (for error handling tests)
	function self.setShouldFailAddRunes(shouldFail: boolean)
		self.runeManager.setShouldFailAddRunes(shouldFail)
	end

	-- Create a valid product ID for a specific rune type (1-10)
	function self.getProductIdForRuneType(runeTypeId: number): number
		return PLACEHOLDER_BASE_ID + runeTypeId
	end

	-- Create a valid bundle product ID
	function self.getBundleProductId(): number
		return PLACEHOLDER_BASE_ID + 100
	end

	-- Create an invalid product ID (not in product table)
	function self.getInvalidProductId(): number
		return PLACEHOLDER_BASE_ID + 999
	end

	-- Generate a unique purchase ID
	local purchaseIdCounter = 0
	function self.generatePurchaseId(): string
		purchaseIdCounter = purchaseIdCounter + 1
		return "TestPurchase_" .. tostring(purchaseIdCounter) .. "_" .. tostring(os.clock())
	end

	-- Create a mock receipt structure
	function self.createReceipt(playerId: number, productId: number, purchaseId: string?): { ProductId: number, PlayerId: number, PurchaseId: string }
		return {
			ProductId = productId,
			PlayerId = playerId,
			PurchaseId = purchaseId or self.generatePurchaseId(),
		}
	end

	-- Reset all state for a fresh test
	function self.reset()
		self.runeManager.clearAll()
		self.dataManager.clearAll()
		self.playersService.clearAll()
		self.remotes.clearAll()
		self.purchaseManager.clearAll()
		purchaseIdCounter = 0
	end

	-- ═══════════════════════════════════════════════════════════════════════
	-- Scenario Setup Helpers
	-- ═══════════════════════════════════════════════════════════════════════

	-- Set up a complete valid purchase scenario
	function self.setupValidPurchaseScenario(userId: number, runeTypeId: number?): { ProductId: number, PlayerId: number, PurchaseId: string }
		-- Set up player as online with empty inventory
		self.setupPlayer(userId)

		-- Create receipt for the specified rune type (default to Ember/1)
		local targetRuneType = runeTypeId or 1
		local productId = self.getProductIdForRuneType(targetRuneType)
		return self.createReceipt(userId, productId)
	end

	-- Set up a bundle purchase scenario
	function self.setupBundlePurchaseScenario(userId: number): { ProductId: number, PlayerId: number, PurchaseId: string }
		-- Set up player as online with empty inventory
		self.setupPlayer(userId)

		-- Create receipt for bundle product
		local productId = self.getBundleProductId()
		return self.createReceipt(userId, productId)
	end

	-- Set up an offline player scenario (player not in game)
	function self.setupOfflinePlayerScenario(userId: number, runeTypeId: number?): { ProductId: number, PlayerId: number, PurchaseId: string }
		-- Initialize inventory but don't add to players service (simulates offline)
		self.runeManager.initPlayer(userId)

		-- Create receipt for the specified rune type
		local targetRuneType = runeTypeId or 1
		local productId = self.getProductIdForRuneType(targetRuneType)
		return self.createReceipt(userId, productId)
	end

	-- Set up an invalid product scenario
	function self.setupInvalidProductScenario(userId: number): { ProductId: number, PlayerId: number, PurchaseId: string }
		-- Set up player as online
		self.setupPlayer(userId)

		-- Create receipt with invalid product ID
		local productId = self.getInvalidProductId()
		return self.createReceipt(userId, productId)
	end

	return self
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Export product table for external access (e.g., PropertyGen)
-- ═══════════════════════════════════════════════════════════════════════════

RunePurchaseTestHarness.PLACEHOLDER_BASE_ID = PLACEHOLDER_BASE_ID
RunePurchaseTestHarness.Rune_Product_Table = Rune_Product_Table

return RunePurchaseTestHarness
