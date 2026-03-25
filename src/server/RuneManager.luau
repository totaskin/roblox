-- RuneManager.luau
-- Handles rune inventory, application to turrets, combination effects, and game-over return.
-- Follows the same module pattern as TurretManager.luau.

local RuneCombinationData = require(game.ReplicatedStorage.Shared.RuneCombinationData)
local ResourceData        = require(game.ReplicatedStorage.Shared.ResourceData)
local TurretData          = require(game.ReplicatedStorage.Shared.TurretData)
local TurretManager       = require(script.Parent.TurretManager)

-- Lazy-require DataManager to avoid circular dependency
local DataManager
local function getDataManager()
	if not DataManager then
		DataManager = require(script.Parent.DataManager)
	end
	return DataManager
end

local RuneManager = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- State (Task 2.1)
-- ═══════════════════════════════════════════════════════════════════════════

-- { [userId]: { [runeTypeId]: count } }
local playerRuneInventories: { [number]: { [number]: number } } = {}

-- { [turretInstanceId]: { runeTypeId, runeTypeId, ... } }
local turretRuneSlots: { [string]: { number } } = {}

-- { [turretInstanceId]: userId } — tracks which player owns each turret's runes
local turretRuneOwners: { [string]: number } = {}

-- Current game phase, set by GameManager callbacks
local gamePhase: string = "LOBBY"

-- ═══════════════════════════════════════════════════════════════════════════
-- Player Inventory Management (Task 2.2)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.initPlayer(userId: number)
	-- Only initialize if not already set (DataManager may have loaded saved data)
	if playerRuneInventories[userId] then return end
	local inventory = {}
	for i = 1, 10 do
		inventory[i] = 0 -- Start with no runes, earn from boss kills
	end
	playerRuneInventories[userId] = inventory
end

function RuneManager.removePlayer(userId: number)
	playerRuneInventories[userId] = nil
end

function RuneManager.getInventory(userId: number): { [number]: number }
	local inv = playerRuneInventories[userId] or {}
	print("[RuneManager] getInventory for user", userId, ":", inv)
	return inv
end

-- Set inventory from loaded data (called by DataManager)
function RuneManager.setInventory(userId: number, runes: { [number]: number })
	local inventory = {}
	for i = 1, 10 do
		inventory[i] = runes[i] or 0
	end
	playerRuneInventories[userId] = inventory
end

function RuneManager.setGamePhase(phase: string)
	gamePhase = phase
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Add Runes (Task 3 - Rune Robux Purchase)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.addRunes(userId: number, runeTypeId: number, quantity: number): boolean
	-- Validate runeTypeId is in [1, 10]
	if type(runeTypeId) ~= "number" or runeTypeId < 1 or runeTypeId > 10 or runeTypeId ~= math.floor(runeTypeId) then
		return false
	end

	-- Validate quantity > 0
	if type(quantity) ~= "number" or quantity <= 0 or quantity ~= math.floor(quantity) then
		return false
	end

	-- Get or initialize inventory
	local inventory = playerRuneInventories[userId]
	if not inventory then
		-- Initialize inventory if player doesn't have one yet
		inventory = {}
		for i = 1, 10 do
			inventory[i] = 0
		end
		playerRuneInventories[userId] = inventory
	end

	-- Increment the rune count by the specified quantity
	inventory[runeTypeId] = (inventory[runeTypeId] or 0) + quantity

	-- Mark data as dirty for persistence
	getDataManager().markDirty(userId)

	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Boss Drop (Task 2.3)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.awardBossDrop(userIds: { number }, bossKillCount: number): number
	local runeTypeId = ResourceData.rollResourceDrop(bossKillCount)
	print("[RuneManager] awardBossDrop called. runeTypeId:", runeTypeId, "userIds:", userIds)

	for _, userId in ipairs(userIds) do
		local inventory = playerRuneInventories[userId]
		print("[RuneManager] User", userId, "inventory exists:", inventory ~= nil)
		if inventory then
			inventory[runeTypeId] = (inventory[runeTypeId] or 0) + 1
			print("[RuneManager] Added rune", runeTypeId, "to user", userId, "new count:", inventory[runeTypeId])
			getDataManager().markDirty(userId)
		else
			warn("[RuneManager] No inventory for user", userId)
		end
	end

	return runeTypeId
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Recompute Turret Stats (Task 2.5)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.recomputeTurretStats(turretInstanceId: string)
	local turrets = TurretManager.getTurrets()
	local turret = turrets[turretInstanceId]
	if not turret then return end

	local turretType = TurretData.getTurretById(turret.turretTypeId)
	if not turretType then return end

	-- Compute base stats: baseStat * upgradeMultiplier^(level-1)
	local mult = turretType.upgradeMultipliers
	local baseDamage   = turretType.damage * mult.damage ^ (turret.level - 1)
	local baseRange    = turretType.range * mult.range ^ (turret.level - 1)
	local baseFireRate = turretType.fireRate * mult.fireRate ^ (turret.level - 1)

	-- Get combined rune multipliers
	local runeSlot = turretRuneSlots[turretInstanceId] or {}
	local combined = RuneCombinationData.computeCombinedMultipliers(runeSlot)

	-- Final stats = base * runeMultiplier
	turret.stats.damage   = baseDamage * combined.damage
	turret.stats.range    = baseRange * combined.range
	turret.stats.fireRate = baseFireRate * combined.fireRate

	-- Update model attributes so clients can read them (Task 4.3)
	local model = turret.model
	if model then
		model:SetAttribute("TurretDamage", turret.stats.damage)
		model:SetAttribute("TurretRange", turret.stats.range)
		model:SetAttribute("TurretFireRate", turret.stats.fireRate)
		-- Store runes as comma-separated string for client to read
		local runeStr = table.concat(runeSlot, ",")
		model:SetAttribute("TurretRunes", runeStr)
	end

	-- Create/update orbiting rune parts around the turret
	if model then
		-- Remove old rune orbs
		for _, child in model:GetChildren() do
			if child.Name:match("^RuneOrb_") then
				child:Destroy()
			end
		end
		-- Also remove old single glow if it exists
		local existingGlow = model:FindFirstChild("RuneGlow")
		if existingGlow then
			existingGlow:Destroy()
		end

		-- Create new orbiting rune parts for each applied rune
		local orbitRadius = 2.5
		local orbitHeight = 3.5
		for i, runeId in ipairs(runeSlot) do
			local res = ResourceData.Resources[runeId]
			if res then
				local orb = Instance.new("Part")
				orb.Name = "RuneOrb_" .. i
				orb.Shape = Enum.PartType.Ball
				orb.Size = Vector3.new(1.2, 1.2, 1.2)
				orb.Anchored = true
				orb.CanCollide = false
				orb.Material = Enum.Material.Neon
				orb.Color = res.color
				orb.Transparency = 0.2
				
				-- Position around turret (will be animated by client)
				local angle = (i - 1) * (2 * math.pi / 3) -- 120 degrees apart for 3 slots
				local offsetX = math.cos(angle) * orbitRadius
				local offsetZ = math.sin(angle) * orbitRadius
				orb.Position = turret.position + Vector3.new(offsetX, orbitHeight, offsetZ)
				
				-- Store the rune id and slot index as attributes for client animation
				orb.SetAttribute(orb, "RuneId", runeId)
				orb.SetAttribute(orb, "SlotIndex", i)
				
				orb.Parent = model
			end
		end
	end

	-- Task 4.2: Update BillboardGui with applied rune names
	if model then
		local billboard = model:FindFirstChild("TurretInfo")
		if billboard then
			local existingLabel = billboard:FindFirstChild("RuneLabel")
			if #runeSlot > 0 then
				-- Build comma-separated list of unique rune names
				local seen: { [number]: boolean } = {}
				local names: { string } = {}
				for _, rId in ipairs(runeSlot) do
					if not seen[rId] then
						seen[rId] = true
						local res = ResourceData.Resources[rId]
						if res then
							table.insert(names, res.name)
						end
					end
				end
				local runeText = table.concat(names, ", ")

				local label = existingLabel
				if not label then
					label = Instance.new("TextLabel")
					label.Name = "RuneLabel"
					label.BackgroundTransparency = 1
					label.Parent = billboard
				end
				label.Size = UDim2.new(1, 0, 0.4, 0)
				label.Position = UDim2.new(0, 0, 1, 0)
				label.Text = runeText
				label.TextColor3 = Color3.fromRGB(200, 180, 255)
				label.TextScaled = true
				label.Font = Enum.Font.Gotham
				label.Visible = true
			else
				-- No runes: hide the label if it exists
				if existingLabel then
					existingLabel.Visible = false
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Apply Rune (Task 2.4)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.applyRune(userId: number, turretInstanceId: string, runeTypeId: number): (boolean, string?)
	-- 1. Validate rune type id is in [1, 10]
	if type(runeTypeId) ~= "number" or runeTypeId < 1 or runeTypeId > 10 or runeTypeId ~= math.floor(runeTypeId) then
		return false, "Invalid rune type"
	end

	-- 2. Validate turret exists
	local turrets = TurretManager.getTurrets()
	local turret = turrets[turretInstanceId]
	if not turret then
		return false, "Turret not found"
	end

	-- 4. Validate ownership
	if turret.ownerId ~= userId then
		return false, "Not your turret"
	end

	-- 5. Validate rune slot limit (max 3 runes per turret)
	local currentSlots = turretRuneSlots[turretInstanceId] or {}
	if #currentSlots >= 3 then
		return false, "Turret already has 3 runes"
	end

	-- 6. Validate inventory count > 0
	local inventory = playerRuneInventories[userId]
	if not inventory or (inventory[runeTypeId] or 0) <= 0 then
		return false, "No runes of this type available"
	end

	-- 7. Decrement inventory
	inventory[runeTypeId] = inventory[runeTypeId] - 1
	getDataManager().markDirty(userId)

	-- 8. Add to rune slot
	if not turretRuneSlots[turretInstanceId] then
		turretRuneSlots[turretInstanceId] = {}
	end
	table.insert(turretRuneSlots[turretInstanceId], runeTypeId)

	-- Track owner for rune return
	turretRuneOwners[turretInstanceId] = userId

	-- 9. Recompute turret stats
	RuneManager.recomputeTurretStats(turretInstanceId)

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Return All Runes (Task 2.6)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.returnAllRunes()
	for turretInstanceId, runeSlot in pairs(turretRuneSlots) do
		-- Determine the owner: prefer turretRuneOwners, fall back to TurretManager
		local ownerId = turretRuneOwners[turretInstanceId]
		if not ownerId then
			local turrets = TurretManager.getTurrets()
			local turret = turrets[turretInstanceId]
			if turret then
				ownerId = turret.ownerId
			end
		end

		if ownerId then
			local inventory = playerRuneInventories[ownerId]
			if inventory then
				for _, runeTypeId in ipairs(runeSlot) do
					inventory[runeTypeId] = (inventory[runeTypeId] or 0) + 1
				end
				getDataManager().markDirty(ownerId)
			end
		end
	end

	-- Clear all rune slots and owners
	turretRuneSlots = {}
	turretRuneOwners = {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Utility (Task 2.7)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.getTurretRunes(turretInstanceId: string): { number }
	return turretRuneSlots[turretInstanceId] or {}
end

function RuneManager.clearAll()
	-- Only clear turret-related state, NOT player inventories
	-- Player inventories persist across games and are managed by DataManager
	turretRuneSlots = {}
	turretRuneOwners = {}
	gamePhase = "LOBBY"
end

return RuneManager
