-- RuneTestHarness.luau
-- A test-friendly reimplementation of rune system core logic.
-- Mirrors the real RuneManager but removes all Roblox service dependencies
-- (no Instance, no Workspace, no RemoteEvents).
-- Uses RuneCombinationData and ResourceData directly (pure data modules).
-- This allows property-based tests to exercise rune logic directly.

local RuneCombinationData = require(script.Parent.Parent.shared.RuneCombinationData)
local ResourceData = require(script.Parent.Parent.shared.ResourceData)
local TurretData = require(script.Parent.Parent.shared.TurretData)

local RuneTestHarness = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock RuneManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockRuneManager(turretRegistry: any)
	local rm = {}

	-- State (mirrors real RuneManager)
	local playerRuneInventories: { [number]: { [number]: number } } = {}
	local turretRuneSlots: { [string]: { number } } = {}
	local turretRuneOwners: { [string]: number } = {}
	local gamePhase: string = "LOBBY"

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

	function rm.setGamePhase(phase: string)
		gamePhase = phase
	end

	function rm.getGamePhase(): string
		return gamePhase
	end

	-- ── Boss Drop ──

	function rm.awardBossDrop(userIds: { number }, bossKillCount: number): number
		local runeTypeId = ResourceData.rollResourceDrop(bossKillCount)

		for _, userId in ipairs(userIds) do
			local inventory = playerRuneInventories[userId]
			if inventory then
				inventory[runeTypeId] = (inventory[runeTypeId] or 0) + 1
			end
		end

		return runeTypeId
	end

	-- ── Recompute Turret Stats ──

	function rm.recomputeTurretStats(turretInstanceId: string)
		local turret = turretRegistry.turrets[turretInstanceId]
		if not turret then return end

		local turretType = TurretData.getTurretById(turret.turretTypeId)
		if not turretType then return end

		-- Compute base stats: baseStat * upgradeMultiplier^(level-1)
		local mult = turretType.upgradeMultipliers
		local baseDamage = turretType.damage * mult.damage ^ (turret.level - 1)
		local baseRange = turretType.range * mult.range ^ (turret.level - 1)
		local baseFireRate = turretType.fireRate * mult.fireRate ^ (turret.level - 1)

		-- Get combined rune multipliers
		local runeSlot = turretRuneSlots[turretInstanceId] or {}
		local combined = RuneCombinationData.computeCombinedMultipliers(runeSlot)

		-- Final stats = base * runeMultiplier (no model updates since no Roblox)
		turret.stats.damage = baseDamage * combined.damage
		turret.stats.range = baseRange * combined.range
		turret.stats.fireRate = baseFireRate * combined.fireRate
	end

	-- ── Apply Rune (full validation chain matching real RuneManager) ──

	function rm.applyRune(userId: number, turretInstanceId: string, runeTypeId: number): (boolean, string?)
		-- 1. Validate rune type id is in [1, 10]
		if type(runeTypeId) ~= "number" or runeTypeId < 1 or runeTypeId > 10 or runeTypeId ~= math.floor(runeTypeId) then
			return false, "Invalid rune type"
		end

		-- 2. Validate turret exists
		local turret = turretRegistry.turrets[turretInstanceId]
		if not turret then
			return false, "Turret not found"
		end

		-- 3. Validate ownership
		if turret.ownerId ~= userId then
			return false, "Not your turret"
		end

		-- 4. Validate rune slot limit (max 3 runes per turret)
		local currentSlots = turretRuneSlots[turretInstanceId] or {}
		if #currentSlots >= 3 then
			return false, "Turret already has 3 runes"
		end

		-- 5. Validate inventory count > 0
		local inventory = playerRuneInventories[userId]
		if not inventory or (inventory[runeTypeId] or 0) <= 0 then
			return false, "No runes of this type available"
		end

		-- 6. Decrement inventory
		inventory[runeTypeId] = inventory[runeTypeId] - 1

		-- 7. Add to rune slot
		if not turretRuneSlots[turretInstanceId] then
			turretRuneSlots[turretInstanceId] = {}
		end
		table.insert(turretRuneSlots[turretInstanceId], runeTypeId)

		-- Track owner for rune return
		turretRuneOwners[turretInstanceId] = userId

		-- 8. Recompute turret stats
		rm.recomputeTurretStats(turretInstanceId)

		return true, nil
	end

	-- ── Return All Runes ──

	function rm.returnAllRunes()
		for turretInstanceId, runeSlot in pairs(turretRuneSlots) do
			-- Determine the owner: prefer turretRuneOwners, fall back to turret registry
			local ownerId = turretRuneOwners[turretInstanceId]
			if not ownerId then
				local turret = turretRegistry.turrets[turretInstanceId]
				if turret then
					ownerId = turret.ownerId
				end
			end

			if ownerId then
				local inventory = playerRuneInventories[ownerId]
				if inventory then
					for _, rTypeId in ipairs(runeSlot) do
						inventory[rTypeId] = (inventory[rTypeId] or 0) + 1
					end
				end
			end
		end

		-- Clear all rune slots and owners
		turretRuneSlots = {}
		turretRuneOwners = {}
	end

	-- ── Utility ──

	function rm.getTurretRunes(turretInstanceId: string): { number }
		return turretRuneSlots[turretInstanceId] or {}
	end

	function rm.clearAll()
		-- Only clear turret-related state, NOT player inventories
		-- Player inventories persist across games
		turretRuneSlots = {}
		turretRuneOwners = {}
		gamePhase = "LOBBY"
	end

	return rm
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock Turret Registry
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockTurretRegistry()
	local registry = {}
	registry.turrets = {} :: { [string]: any }

	function registry.addTurret(id: string, turretTypeId: number, ownerId: number, level: number?)
		local turretType = TurretData.getTurretById(turretTypeId)
		if not turretType then return end

		local lvl = level or 1
		local mult = turretType.upgradeMultipliers

		registry.turrets[id] = {
			id = id,
			turretTypeId = turretTypeId,
			ownerId = ownerId,
			level = lvl,
			stats = {
				damage = turretType.damage * mult.damage ^ (lvl - 1),
				range = turretType.range * mult.range ^ (lvl - 1),
				fireRate = turretType.fireRate * mult.fireRate ^ (lvl - 1),
			},
		}
	end

	function registry.getTurrets(): { [string]: any }
		return registry.turrets
	end

	function registry.clearAll()
		registry.turrets = {}
	end

	return registry
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RuneTestHarness.new() — creates an isolated test instance
-- ═══════════════════════════════════════════════════════════════════════════

function RuneTestHarness.new()
	local self = {} :: any

	self.turretRegistry = createMockTurretRegistry()
	self.runeManager = createMockRuneManager(self.turretRegistry)

	-- Expose RuneCombinationData directly for tests that need it
	self.RuneCombinationData = RuneCombinationData

	-- Helper: set up a player with rune inventory (optionally pre-filled)
	function self.setupPlayerWithInventory(userId: number, inventory: { [number]: number }?)
		self.runeManager.initPlayer(userId)
		if inventory then
			local inv = self.runeManager.getInventory(userId)
			for runeTypeId, count in pairs(inventory) do
				inv[runeTypeId] = count
			end
		end
	end

	-- Helper: add a mock turret to the registry
	function self.addMockTurret(id: string, turretTypeId: number, ownerId: number, level: number?)
		self.turretRegistry.addTurret(id, turretTypeId, ownerId, level)
	end

	-- Helper: set up a valid scenario for rune application
	-- Creates a player with inventory containing the rune and a turret owned by them
	function self.setupValidScenario(userId: number, turretId: string, turretTypeId: number, runeTypeId: number)
		-- Init player with 1 rune of the specified type
		self.runeManager.initPlayer(userId)
		local inv = self.runeManager.getInventory(userId)
		inv[runeTypeId] = (inv[runeTypeId] or 0) + 1

		-- Add turret owned by this player
		self.turretRegistry.addTurret(turretId, turretTypeId, userId)
	end

	return self
end

return RuneTestHarness
