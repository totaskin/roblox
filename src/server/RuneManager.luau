-- RuneManager.luau
-- Handles rune inventory, application to turrets, combination effects, and game-over return.
-- Follows the same module pattern as TurretManager.luau.

local RuneCombinationData = require(game.ReplicatedStorage.Shared.RuneCombinationData)
local ResourceData        = require(game.ReplicatedStorage.Shared.ResourceData)
local TurretData          = require(game.ReplicatedStorage.Shared.TurretData)
local TurretManager       = require(script.Parent.TurretManager)

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
	local inventory = {}
	for i = 1, 10 do
		inventory[i] = 0
	end
	playerRuneInventories[userId] = inventory
end

function RuneManager.removePlayer(userId: number)
	playerRuneInventories[userId] = nil
end

function RuneManager.getInventory(userId: number): { [number]: number }
	return playerRuneInventories[userId] or {}
end

function RuneManager.setGamePhase(phase: string)
	gamePhase = phase
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Boss Drop (Task 2.3)
-- ═══════════════════════════════════════════════════════════════════════════

function RuneManager.awardBossDrop(userIds: { number }, round: number): number
	local runeTypeId = ResourceData.rollResourceDrop(round)

	for _, userId in ipairs(userIds) do
		local inventory = playerRuneInventories[userId]
		if inventory then
			inventory[runeTypeId] = (inventory[runeTypeId] or 0) + 1
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
	end

	-- Task 4.1: Add/update neon glow Part colored by rune type(s)
	if model then
		local existingGlow = model:FindFirstChild("RuneGlow")
		if #runeSlot > 0 then
			-- Collect unique rune type ids to compute blended color
			local uniqueTypes: { [number]: boolean } = {}
			for _, rId in ipairs(runeSlot) do
				uniqueTypes[rId] = true
			end

			-- Average the RGB values of all unique rune type colors
			local totalR, totalG, totalB = 0, 0, 0
			local count = 0
			for rId, _ in pairs(uniqueTypes) do
				local res = ResourceData.Resources[rId]
				if res then
					totalR = totalR + res.color.R
					totalG = totalG + res.color.G
					totalB = totalB + res.color.B
					count = count + 1
				end
			end

			local glowColor = Color3.new(totalR / count, totalG / count, totalB / count)

			local glow = existingGlow
			if not glow then
				glow = Instance.new("Part")
				glow.Name = "RuneGlow"
				glow.Shape = Enum.PartType.Ball
				glow.Anchored = true
				glow.CanCollide = false
				glow.Parent = model
			end
			glow.Size = Vector3.new(2, 2, 2)
			glow.Material = Enum.Material.Neon
			glow.Transparency = 0.3
			glow.Position = turret.position + Vector3.new(0, 4.5, 0)
			glow.Color = glowColor
		else
			-- No runes: remove glow if it exists
			if existingGlow then
				existingGlow:Destroy()
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

	-- 3. Validate game phase is Intermission
	if gamePhase ~= "Intermission" then
		return false, "Runes can only be applied during intermission"
	end

	-- 4. Validate ownership
	if turret.ownerId ~= userId then
		return false, "Not your turret"
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
	playerRuneInventories = {}
	turretRuneSlots = {}
	turretRuneOwners = {}
	gamePhase = "LOBBY"
end

return RuneManager
