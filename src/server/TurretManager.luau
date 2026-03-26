-- TurretManager.luau
-- Handles turret placement, targeting, shooting, upgrades, support towers, and cleanup
-- Turrets are fixed-stat blueprints (not combo-based) placed using session coins

local Players        = game:GetService("Players")
local TurretData    = require(game.ReplicatedStorage.Shared.TurretData)
local ResourceData  = require(game.ReplicatedStorage.Shared.ResourceData)
local EnemyManager  = require(script.Parent.EnemyManager)
local EconomyManager = require(script.Parent.EconomyManager)
local TowerManager  = require(script.Parent.TowerManager)
local GamepassManager = require(script.Parent.GamepassManager)

local TurretManager = {}

-- TurretInstance type (runtime state for a placed turret)
export type TurretInstance = {
	id: string,
	turretTypeId: number,
	ownerId: number,
	gridX: number,
	gridZ: number,
	position: Vector3,
	level: number,
	stats: { damage: number, range: number, fireRate: number },
	model: Model,
	cooldown: number,
	supportCooldown: number?,
}

-- Player color palette: Blue (Player 1), Red (Player 2)
local PLAYER_COLORS: { Color3 } = {
	Color3.fromRGB(50, 130, 255),   -- Blue (Player 1)
	Color3.fromRGB(255, 80, 80),    -- Red (Player 2)
}

-- Module state
local turrets: { [string]: TurretInstance } = {}
local turretIdCounter = 0
local playerLoadouts: { [number]: { number } }? = nil
local playerColors: { [number]: Color3 } = {}

-- Track how many of each turret type have been placed (for escalating costs)
local turretPlacementCounts: { [number]: number } = {}

-- Callbacks for support tower effects (set by GameManager)
local onSupportMoney: ((ownerId: number, amount: number) -> ())? = nil
local onSupportHealth: ((amount: number) -> ())? = nil

-- Callback to get turret runes (set by GameManager to avoid circular dep with RuneManager)
local getTurretRunesCallback: ((turretInstanceId: string) -> { number })? = nil

-- Load a turret model from ReplicatedStorage.TurretModels by name
-- Returns cloned model if found, nil if not found
local function loadTurretModel(turretName: string): Model?
	local turretModels = game.ReplicatedStorage:FindFirstChild("TurretModels")
	if not turretModels then
		warn("[TurretManager] TurretModels folder not found in ReplicatedStorage")
		return nil
	end

	local model = turretModels:FindFirstChild(turretName)
	if not model then
		warn("[TurretManager] Model not found for turret: " .. turretName)
		return nil
	end

	-- Debug: check for attachments in source model before cloning
	local attachmentCount = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Attachment") then
			attachmentCount += 1
			print("[TurretManager] Source model has Attachment: " .. desc.Name .. " in " .. desc.Parent.Name)
		end
	end
	print("[TurretManager] Source model '" .. turretName .. "' has " .. attachmentCount .. " Attachments")

	return model:Clone()
end

-- Ensure the Turrets folder exists in Workspace
local function ensureTurretsFolder(): Folder
	local folder = workspace:FindFirstChild("Turrets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Turrets"
		folder.Parent = workspace
	end
	return folder
end

local function newTurretId(): string
	turretIdCounter += 1
	return "turret_" .. turretIdCounter
end

-- Store a reference to the player loadouts table
function TurretManager.setPlayerLoadouts(loadouts: { [number]: { number } })
	playerLoadouts = loadouts
end

-- Assign each player a color from PLAYER_COLORS by join order (index in the array)
function TurretManager.assignPlayerColors(players: { Player })
	playerColors = {}
	for i, player in ipairs(players) do
		if i > #PLAYER_COLORS then break end
		playerColors[player.UserId] = PLAYER_COLORS[i]
	end
end

-- Return the assigned color for a player, or nil if not assigned
function TurretManager.getPlayerColor(userId: number): Color3?
	return playerColors[userId]
end

function TurretManager.onSupportMoney(callback: (ownerId: number, amount: number) -> ())
	onSupportMoney = callback
end

function TurretManager.onSupportHealth(callback: (amount: number) -> ())
	onSupportHealth = callback
end

function TurretManager.onGetTurretRunes(callback: (turretInstanceId: string) -> { number })
	getTurretRunesCallback = callback
end

-- Check if a turret type id is in the player's loadout
local function isInLoadout(userId: number, turretTypeId: number): boolean
	if not playerLoadouts then return false end
	local loadout = playerLoadouts[userId]
	if not loadout then return false end
	for _, id in ipairs(loadout) do
		if id == turretTypeId then
			return true
		end
	end
	return false
end

-- Check if a grid slot is occupied by either a combo tower or a turret
local function isSlotOccupied(gridX: number, gridZ: number): boolean
	-- Check existing combo towers
	for _, t in pairs(TowerManager.getTowers()) do
		if t.gridX == gridX and t.gridZ == gridZ then
			return true
		end
	end
	-- Check existing turrets
	for _, t in pairs(turrets) do
		if t.gridX == gridX and t.gridZ == gridZ then
			return true
		end
	end
	return false
end

-- Internal helper: apply owner color to a turret model
local function applyOwnerColor(model: Model, ownerColor: Color3, ownerName: string)
	-- Set Body.Color if Body part/model exists
	local body = model:FindFirstChild("Body")
	if body then
		-- If Body is a Part or MeshPart, set color directly
		if body:IsA("BasePart") then
			body.Color = ownerColor
		-- If Body is a Model, color all BaseParts inside it
		elseif body:IsA("Model") then
			for _, part in ipairs(body:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Color = ownerColor
				end
			end
		end
	end

	-- Set OwnerColor attribute on the model
	model:SetAttribute("OwnerColor", ownerColor)

	-- Add OwnerLabel to the TurretInfo BillboardGui
	local billboard = model:FindFirstChild("TurretInfo")
	if billboard then
		local ownerLabel = Instance.new("TextLabel")
		ownerLabel.Name = "OwnerLabel"
		ownerLabel.Size = UDim2.new(1, 0, 0.35, 0)
		ownerLabel.Position = UDim2.new(0, 0, 1, 0)
		ownerLabel.Text = ownerName
		ownerLabel.TextColor3 = ownerColor
		ownerLabel.BackgroundTransparency = 1
		ownerLabel.TextScaled = true
		ownerLabel.Font = Enum.Font.GothamBold
		ownerLabel.Parent = billboard
	end
end

-- Setup function for loaded models from ReplicatedStorage
-- Positions model, sets attributes, applies owner color, adds GUI elements
local function setupLoadedModel(
	model: Model,
	position: Vector3,
	turretType: any,
	level: number,
	ownerColor: Color3?,
	ownerName: string?
)
	-- Position the model using PrimaryPart CFrame, preserving original rotation
	local base = model.PrimaryPart
	if base then
		local originalRotation = base.CFrame - base.CFrame.Position -- extract rotation only
		model:SetPrimaryPartCFrame(originalRotation + position)
		-- Ensure Base part has correct properties after placement
		base.Anchored = true
		base.CanCollide = true
	else
		warn("[TurretManager] Model missing PrimaryPart: " .. model.Name)
	end

	-- Set standard turret attributes
	model:SetAttribute("TurretInstanceId", "")
	model:SetAttribute("TurretTypeId", turretType.id)
	model:SetAttribute("TurretLevel", level)
	model:SetAttribute("TurretDamage", turretType.damage)
	model:SetAttribute("TurretRange", turretType.range)
	model:SetAttribute("TurretFireRate", turretType.fireRate)

	-- BillboardGui showing level and upgrade info
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TurretInfo"
	billboard.Size = UDim2.new(0, 120, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.AlwaysOnTop = false
	billboard.Adornee = base
	billboard.Parent = model

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, 0, 0.5, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = turretType.name .. " Lv" .. level
	levelLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	levelLabel.TextScaled = true
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.Parent = billboard

	local upgradeCost = turretType.placementCost * math.pow(2, level)
	local upgradeLabel = Instance.new("TextLabel")
	upgradeLabel.Name = "UpgradeLabel"
	upgradeLabel.Size = UDim2.new(1, 0, 0.5, 0)
	upgradeLabel.Position = UDim2.new(0, 0, 0.5, 0)
	upgradeLabel.BackgroundTransparency = 1
	upgradeLabel.Text = "Upgrade: 💰 " .. upgradeCost
	upgradeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	upgradeLabel.TextScaled = true
	upgradeLabel.Font = Enum.Font.Gotham
	upgradeLabel.Parent = billboard

	-- ProximityPrompt for client-side upgrade interaction
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradePrompt"
	prompt.ActionText = "Upgrade 💰" .. upgradeCost
	prompt.ObjectText = turretType.name .. " Lv" .. level
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = base

	-- Apply owner color to Body part if provided
	if ownerColor then
		applyOwnerColor(model, ownerColor, ownerName or "")
	end

	-- Parent model to Workspace.Turrets folder
	local turretsFolder = ensureTurretsFolder()
	model.Parent = turretsFolder
end

-- Builds a procedural turret model in workspace (distinct look from combo towers)
-- Used as fallback when pre-made model not found in ReplicatedStorage
local function buildProceduralModel(position: Vector3, turretType: any, level: number, ownerColor: Color3?, ownerName: string?): Model
	local model = Instance.new("Model")
	model.Name = turretType.name

	local isSupport = turretType.supportType ~= nil

	-- Base — circular-ish platform
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(1, 4, 4)
	base.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.CanCollide = false
	base.BrickColor = BrickColor.new("Medium stone grey")
	base.Material = Enum.Material.Metal
	base.Parent = model

	if isSupport and turretType.supportType == "money" then
		-- Coin Printer: gold box with spinning coin on top
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(2, 2, 2)
		body.Position = position + Vector3.new(0, 1.5, 0)
		body.Anchored = true
		body.CanCollide = false
		body.Color = Color3.fromRGB(255, 200, 50)
		body.Material = Enum.Material.Metal
		body.Parent = model

		local slot = Instance.new("Part")
		slot.Name = "Slot"
		slot.Size = Vector3.new(1.2, 0.15, 0.3)
		slot.Position = position + Vector3.new(0, 2.6, 0)
		slot.Anchored = true
		slot.CanCollide = false
		slot.Color = Color3.fromRGB(40, 40, 40)
		slot.Parent = model

		local coin = Instance.new("Part")
		coin.Name = "Coin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.2, 1.2, 1.2)
		coin.CFrame = CFrame.new(position + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		coin.Anchored = true
		coin.CanCollide = false
		coin.Color = Color3.fromRGB(255, 215, 0)
		coin.Material = Enum.Material.Neon
		coin.Parent = model

	elseif isSupport and turretType.supportType == "health" then
		-- Medic Station: white box with red cross on top
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(2, 2.5, 2)
		body.Position = position + Vector3.new(0, 1.75, 0)
		body.Anchored = true
		body.CanCollide = false
		body.Color = Color3.fromRGB(240, 240, 240)
		body.Material = Enum.Material.SmoothPlastic
		body.Parent = model

		-- Red cross (horizontal bar)
		local crossH = Instance.new("Part")
		crossH.Name = "CrossH"
		crossH.Size = Vector3.new(1.4, 0.35, 0.1)
		crossH.Position = position + Vector3.new(0, 2.5, 1.05)
		crossH.Anchored = true
		crossH.CanCollide = false
		crossH.Color = Color3.fromRGB(220, 30, 30)
		crossH.Material = Enum.Material.Neon
		crossH.Parent = model

		-- Red cross (vertical bar)
		local crossV = Instance.new("Part")
		crossV.Name = "CrossV"
		crossV.Size = Vector3.new(0.35, 1.4, 0.1)
		crossV.Position = position + Vector3.new(0, 2.5, 1.05)
		crossV.Anchored = true
		crossV.CanCollide = false
		crossV.Color = Color3.fromRGB(220, 30, 30)
		crossV.Material = Enum.Material.Neon
		crossV.Parent = model

		-- Healing glow on top
		local glow = Instance.new("Part")
		glow.Name = "HealGlow"
		glow.Shape = Enum.PartType.Ball
		glow.Size = Vector3.new(0.8, 0.8, 0.8)
		glow.Position = position + Vector3.new(0, 3.5, 0)
		glow.Anchored = true
		glow.CanCollide = false
		glow.Color = Color3.fromRGB(80, 255, 80)
		glow.Material = Enum.Material.Neon
		glow.Parent = model
	else
		-- Combat turret: tall cylinder body + barrel
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(3, 1.5, 1.5)
		body.CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		body.Anchored = true
		body.CanCollide = false
		body.Color = Color3.fromRGB(60, 140, 200)
		body.Material = Enum.Material.Metal
		body.Parent = model

		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = Vector3.new(0.5, 0.5, 2)
		barrel.Position = position + Vector3.new(0, 3, 1)
		barrel.Anchored = true
		barrel.CanCollide = false
		barrel.Color = Color3.fromRGB(40, 40, 40)
		barrel.Material = Enum.Material.Metal
		barrel.Parent = model
	end

	-- Level indicator (small glowing part on top)
	local indicator = Instance.new("Part")
	indicator.Name = "LevelIndicator"
	indicator.Shape = Enum.PartType.Ball
	indicator.Size = Vector3.new(0.6, 0.6, 0.6)
	indicator.Position = position + Vector3.new(0, 4, 0)
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.Material = Enum.Material.Neon
	if level == 1 then
		indicator.Color = Color3.fromRGB(100, 255, 100)
	elseif level == 2 then
		indicator.Color = Color3.fromRGB(100, 100, 255)
	else
		indicator.Color = Color3.fromRGB(255, 100, 255)
	end
	indicator.Parent = model

	model.PrimaryPart = base

	-- Set attributes for client-side reading
	model:SetAttribute("TurretInstanceId", "")
	model:SetAttribute("TurretTypeId", turretType.id)
	model:SetAttribute("TurretLevel", level)
	model:SetAttribute("TurretDamage", turretType.damage)
	model:SetAttribute("TurretRange", turretType.range)
	model:SetAttribute("TurretFireRate", turretType.fireRate)

	-- BillboardGui showing level and upgrade info
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TurretInfo"
	billboard.Size = UDim2.new(0, 120, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.AlwaysOnTop = false
	billboard.Adornee = base
	billboard.Parent = model

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, 0, 0.5, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = turretType.name .. " Lv" .. level
	levelLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	levelLabel.TextScaled = true
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.Parent = billboard

	local upgradeCost = turretType.placementCost * math.pow(2, level)
	local upgradeLabel = Instance.new("TextLabel")
	upgradeLabel.Name = "UpgradeLabel"
	upgradeLabel.Size = UDim2.new(1, 0, 0.5, 0)
	upgradeLabel.Position = UDim2.new(0, 0, 0.5, 0)
	upgradeLabel.BackgroundTransparency = 1
	upgradeLabel.Text = "Upgrade: 💰 " .. upgradeCost
	upgradeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	upgradeLabel.TextScaled = true
	upgradeLabel.Font = Enum.Font.Gotham
	upgradeLabel.Parent = billboard

	-- ProximityPrompt for client-side upgrade interaction
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradePrompt"
	prompt.ActionText = "Upgrade 💰" .. upgradeCost
	prompt.ObjectText = turretType.name .. " Lv" .. level
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = base

	model.Parent = workspace

	-- Apply owner color if provided
	if ownerColor then
		applyOwnerColor(model, ownerColor, ownerName or "")
	end

	return model
end

-- Builds a turret model, trying to load pre-made model first, falling back to procedural
local function buildTurretModel(position: Vector3, turretType: any, level: number, ownerColor: Color3?, ownerName: string?): Model
	-- Try to load pre-made model from ReplicatedStorage first
	local model = loadTurretModel(turretType.name)

	if model then
		-- Use pre-made model with setup
		setupLoadedModel(model, position, turretType, level, ownerColor, ownerName)
	else
		-- Fallback to procedural generation (existing code)
		model = buildProceduralModel(position, turretType, level, ownerColor, ownerName)
	end

	return model
end

-- Get the current placement cost for a turret type (escalates with each placement)
-- Cost formula: baseCost + (baseCost * 0.5 * placementCount)
-- e.g., base 50: 1st=50, 2nd=75, 3rd=100, 4th=125...
function TurretManager.getPlacementCost(turretTypeId: number): number
	local turretType = TurretData.getTurretById(turretTypeId)
	if not turretType then
		return 0
	end
	local baseCost = turretType.placementCost
	local count = turretPlacementCounts[turretTypeId] or 0
	return math.floor(baseCost + (baseCost * 0.5 * count))
end

-- Get placement counts for all turret types (for client sync)
function TurretManager.getPlacementCounts(): { [number]: number }
	return turretPlacementCounts
end

-- Task 6.2: Place a turret on the map
function TurretManager.placeTurret(
	userId: number,
	turretTypeId: number,
	gridX: number,
	gridZ: number,
	worldPos: Vector3
): (boolean, string?)
	-- Validate turret type exists
	local turretType = TurretData.getTurretById(turretTypeId)
	if not turretType then
		return false, "Invalid turret type"
	end

	-- Validate turret is in player's loadout
	if not isInLoadout(userId, turretTypeId) then
		return false, "Turret not in loadout"
	end

	-- Validate slot is unoccupied (check both combo towers and turrets)
	if isSlotOccupied(gridX, gridZ) then
		return false, "Slot already occupied"
	end

	-- Validate player has sufficient session coins (use escalating cost)
	local cost = TurretManager.getPlacementCost(turretTypeId)
	if EconomyManager.getSessionCoins(userId) < cost then
		return false, "Not enough coins"
	end

	-- Deduct session coins
	local spent = EconomyManager.spendSessionCoins(userId, cost)
	if not spent then
		return false, "Not enough coins"
	end

	-- Increment placement count for this turret type (for escalating costs)
	turretPlacementCounts[turretTypeId] = (turretPlacementCounts[turretTypeId] or 0) + 1

	-- Create TurretInstance at level 1 with base stats
	local id = newTurretId()

	-- Look up owner color and display name for visual ownership
	local ownerColor = TurretManager.getPlayerColor(userId)
	local ownerName: string? = nil
	local player = Players:GetPlayerByUserId(userId)
	if player then
		ownerName = player.DisplayName
	end

	local model = buildTurretModel(worldPos, turretType, 1, ownerColor, ownerName)

	-- Set the actual instance id on the model so clients can read it
	model:SetAttribute("TurretInstanceId", id)

	turrets[id] = {
		id = id,
		turretTypeId = turretTypeId,
		ownerId = userId,
		gridX = gridX,
		gridZ = gridZ,
		position = worldPos,
		level = 1,
		stats = {
			damage = turretType.damage,
			range = turretType.range,
			fireRate = turretType.fireRate,
		},
		model = model,
		cooldown = 0,
		supportCooldown = 0,
	}

	return true, id
end

-- Task 6.4: Get upgrade cost for a turret type at a target level (exponential scaling)
function TurretManager.getUpgradeCost(turretTypeId: number, targetLevel: number): number
	local turretType = TurretData.getTurretById(turretTypeId)
	if not turretType then
		return 0
	end
	-- Exponential: base * 2^(targetLevel-1) → Lv2 costs 2x, Lv3 costs 4x placement
	return turretType.placementCost * math.pow(2, targetLevel - 1)
end

-- Task 6.3: Upgrade a placed turret
function TurretManager.upgradeTurret(turretInstanceId: string, userId: number): (boolean, string?)
	-- Validate turret exists
	local turret = turrets[turretInstanceId]
	if not turret then
		return false, "Turret not found"
	end

	-- Validate owned by player
	if turret.ownerId ~= userId then
		return false, "Not your turret"
	end

	local targetLevel = turret.level + 1
	local cost = TurretManager.getUpgradeCost(turret.turretTypeId, targetLevel)

	-- Validate player has sufficient coins
	if EconomyManager.getSessionCoins(userId) < cost then
		return false, "Not enough coins"
	end

	-- Deduct coins
	local spent = EconomyManager.spendSessionCoins(userId, cost)
	if not spent then
		return false, "Not enough coins"
	end

	-- Increment level
	turret.level = targetLevel

	-- Apply stat multipliers: baseStat * multiplier ^ (level - 1)
	local turretType = TurretData.getTurretById(turret.turretTypeId)
	if turretType then
		local mult = turretType.upgradeMultipliers
		turret.stats.damage = turretType.damage * mult.damage ^ (turret.level - 1)
		turret.stats.range = turretType.range * mult.range ^ (turret.level - 1)
		turret.stats.fireRate = turretType.fireRate * mult.fireRate ^ (turret.level - 1)
	end

	-- Update model attributes and BillboardGui
	local model = turret.model
	if model then
		model:SetAttribute("TurretLevel", turret.level)
		model:SetAttribute("TurretDamage", turret.stats.damage)
		model:SetAttribute("TurretRange", turret.stats.range)
		model:SetAttribute("TurretFireRate", turret.stats.fireRate)

		-- Update level indicator color
		local indicator = model:FindFirstChild("LevelIndicator")
		if indicator then
			if turret.level == 2 then
				indicator.Color = Color3.fromRGB(100, 100, 255)
			elseif turret.level >= 3 then
				indicator.Color = Color3.fromRGB(255, 100, 255)
			end
		end

		-- Update BillboardGui labels
		local billboard = model:FindFirstChild("TurretInfo")
		if billboard then
			local levelLabel = billboard:FindFirstChild("LevelLabel")
			if levelLabel and turretType then
				levelLabel.Text = turretType.name .. " Lv" .. turret.level
			end
			local upgradeLabel = billboard:FindFirstChild("UpgradeLabel")
			if upgradeLabel then
				local nextCost = TurretManager.getUpgradeCost(turret.turretTypeId, turret.level + 1)
				upgradeLabel.Text = "Upgrade: 💰 " .. nextCost
			end
		end

		-- Update ProximityPrompt
		local base = model:FindFirstChild("Base")
		local prompt = base and base:FindFirstChild("UpgradePrompt")
		if prompt then
			local nextCost = TurretManager.getUpgradeCost(turret.turretTypeId, turret.level + 1)
			prompt.ActionText = "Upgrade 💰" .. nextCost
			prompt.ObjectText = (turretType and turretType.name or "Turret") .. " Lv" .. turret.level
		end

		-- Preserve owner visuals: re-apply Body.Color from OwnerColor attribute
		local ownerColor = model:GetAttribute("OwnerColor")
		if ownerColor then
			local body = model:FindFirstChild("Body")
			if body then
				body.Color = ownerColor
			end

			-- Ensure OwnerLabel still exists in the billboard; re-create if missing
			local billboard2 = model:FindFirstChild("TurretInfo")
			if billboard2 and not billboard2:FindFirstChild("OwnerLabel") then
				local player = Players:GetPlayerByUserId(turret.ownerId)
				local ownerName = if player then player.DisplayName else ""
				local ownerLabel = Instance.new("TextLabel")
				ownerLabel.Name = "OwnerLabel"
				ownerLabel.Size = UDim2.new(1, 0, 0.35, 0)
				ownerLabel.Position = UDim2.new(0, 0, 1, 0)
				ownerLabel.Text = ownerName
				ownerLabel.TextColor3 = ownerColor
				ownerLabel.BackgroundTransparency = 1
				ownerLabel.TextScaled = true
				ownerLabel.Font = Enum.Font.GothamBold
				ownerLabel.Parent = billboard2
			end
		end
	end

	return true, nil
end

-- Task 6.5: Utility functions

function TurretManager.getTurrets(): { [string]: TurretInstance }
	return turrets
end

function TurretManager.clearAll()
	for _, t in pairs(turrets) do
		if t.model then t.model:Destroy() end
	end
	turrets = {}
	playerColors = {}
	turretPlacementCounts = {}
end

-- Task 7.1: Targeting logic — find closest enemy within turret range
local function findTarget(turretPos: Vector3, range: number): (string?, Vector3?)
	local bestDist = math.huge
	local bestId = nil
	local bestPos = nil

	for id, enemy in pairs(EnemyManager.getActiveEnemies()) do
		local root = enemy.model and enemy.model.PrimaryPart
		if not root then continue end
		local dist = (root.Position - turretPos).Magnitude
		if dist <= range and dist < bestDist then
			bestDist = dist
			bestId = id
			bestPos = root.Position
		end
	end

	return bestId, bestPos
end

-- Brainrot shooting sound IDs (replace with your own uploaded sounds for best results)
-- These are placeholder IDs — upload short goofy/brainrot clips and paste IDs here
local SHOOT_SOUNDS = {
	"rbxassetid://9114122959",   -- cartoon boing
	"rbxassetid://9114123099",   -- pop
	"rbxassetid://9114124859",   -- squeak
	"rbxassetid://9114125653",   -- spring
	"rbxassetid://9114126314",   -- honk
	"rbxassetid://9114127834",   -- splat
}

-- Performance: limit full particle effects to MAX_FULL_EFFECT_PROJECTILES at a time
local MAX_FULL_EFFECT_PROJECTILES = 10
local activeFullEffectCount = 0

local function playShootSound(position: Vector3, overrideSoundId: string?)
	local soundId = overrideSoundId or SHOOT_SOUNDS[math.random(1, #SHOOT_SOUNDS)]
	local part = Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.8
	sound.PlaybackSpeed = 0.8 + math.random() * 0.4 -- random pitch variation
	sound.RollOffMaxDistance = 80
	sound.Parent = part

	sound:Play()
	-- Clean up after sound finishes
	task.delay(3, function()
		part:Destroy()
	end)
end

-- Vibrant firing effect — scaled by rune count. runeColors is an optional list of Color3 from applied runes.
-- Performance: uses simplified effects when too many projectiles are active
local function fireProjectile(from: Vector3, to: Vector3, runeColors: { Color3 }?, shootSoundId: string?)
	playShootSound(from, shootSoundId)

	local runeCount = if runeColors then #runeColors else 0
	-- Scale factor: 0 runes = 1.0 (small), each rune adds 0.35
	local scale = 1.0 + runeCount * 0.35

	-- Pick projectile color: use first rune color if available, else random
	local defaultColors = {
		Color3.fromRGB(255, 80, 200),
		Color3.fromRGB(0, 220, 255),
		Color3.fromRGB(255, 200, 0),
		Color3.fromRGB(100, 255, 50),
		Color3.fromRGB(255, 100, 50),
		Color3.fromRGB(180, 80, 255),
	}
	local color = if runeColors and #runeColors > 0
		then runeColors[math.random(1, #runeColors)]
		else defaultColors[math.random(1, #defaultColors)]

	-- Check if we can use full effects (performance limiting)
	local useFullEffects = activeFullEffectCount < MAX_FULL_EFFECT_PROJECTILES
	if useFullEffects then
		activeFullEffectCount += 1
	end

	-- Build splash palette from rune colors or defaults (only needed for full effects)
	local splashColors: { Color3 }
	if useFullEffects then
		if runeColors and #runeColors > 0 then
			splashColors = {}
			for _, rc in ipairs(runeColors) do
				table.insert(splashColors, rc)
				-- Add a lighter tint variant
				table.insert(splashColors, Color3.new(
					math.min(rc.R + 0.3, 1),
					math.min(rc.G + 0.3, 1),
					math.min(rc.B + 0.3, 1)
				))
			end
		else
			splashColors = {
				Color3.fromRGB(255, 50, 150),
				Color3.fromRGB(0, 200, 255),
				Color3.fromRGB(255, 220, 0),
				Color3.fromRGB(100, 255, 80),
			}
		end
	end

	-- Main projectile ball (always shown)
	local projSize = 0.35 * scale
	local part = Instance.new("Part")
	part.Size = Vector3.new(projSize, projSize, projSize)
	part.Position = from
	part.Anchored = true
	part.CanCollide = false
	part.Color = color
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Parent = workspace

	-- Glow aura (only if runes present AND full effects)
	local glow: Part? = nil
	if runeCount > 0 and useFullEffects then
		glow = Instance.new("Part")
		glow.Size = Vector3.new(projSize * 2, projSize * 2, projSize * 2)
		glow.Position = from
		glow.Anchored = true
		glow.CanCollide = false
		glow.Color = color
		glow.Shape = Enum.PartType.Ball
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.6
		glow.Parent = workspace
	end

	-- Animate flight
	local steps = 8
	local stepVec = (to - from) / steps
	for i = 1, steps do
		task.wait(0.015)
		local pos = from + stepVec * i
		part.Position = pos
		if glow then
			glow.Position = pos
			local shrink = projSize * 2 * (1 - i * 0.05)
			glow.Size = Vector3.new(shrink, shrink, shrink)
		end
	end

	part:Destroy()
	if glow then glow:Destroy() end

	-- ── Impact explosion (scaled by runes) ──

	-- Central flash (always shown, but smaller for simplified)
	local flashBase = if useFullEffects then 0.8 * scale else 0.5 * scale
	local flashGrow = if useFullEffects then 4 * scale else 2 * scale
	local flash = Instance.new("Part")
	flash.Size = Vector3.new(flashBase, flashBase, flashBase)
	flash.Position = to
	flash.Anchored = true
	flash.CanCollide = false
	flash.Color = color
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Parent = workspace

	task.spawn(function()
		for k = 1, 8 do
			task.wait(0.02)
			local t = k / 8
			local sz = flashBase + flashGrow * t
			flash.Size = Vector3.new(sz, sz, sz)
			flash.Transparency = t
		end
		flash:Destroy()
		-- Decrement counter when full effect projectile finishes
		if useFullEffects then
			activeFullEffectCount -= 1
		end
	end)

	-- Skip sparks, ring, and streaks for simplified effects
	if not useFullEffects then
		return
	end

	-- Sparks (count scales with runes: 6 base, +4 per rune)
	local sparkCount = 6 + runeCount * 4
	local sparkSize = 0.4 * scale
	for j = 1, sparkCount do
		local spark = Instance.new("Part")
		spark.Size = Vector3.new(sparkSize, sparkSize, sparkSize)
		spark.Shape = Enum.PartType.Ball
		spark.Material = Enum.Material.Neon
		spark.Color = splashColors[math.random(1, #splashColors)]
		spark.Anchored = true
		spark.CanCollide = false
		spark.Position = to
		spark.Parent = workspace

		local angle = (j / sparkCount) * math.pi * 2 + math.random() * 0.5
		local upAngle = (math.random() - 0.3) * math.pi * 0.6
		local dir = Vector3.new(
			math.cos(angle) * math.cos(upAngle),
			math.sin(upAngle) + 0.4,
			math.sin(angle) * math.cos(upAngle)
		)
		local speed = (2 + math.random() * 3) * scale

		task.spawn(function()
			for k = 1, 8 do
				task.wait(0.025)
				local t = k / 8
				spark.Position = to + dir * speed * t
				spark.Transparency = t * t
				local sz = sparkSize * (1 - t * 0.6)
				spark.Size = Vector3.new(sz, sz, sz)
			end
			spark:Destroy()
		end)
	end

	-- Ring shockwave (only with 2+ runes)
	if runeCount >= 2 then
		local ringSize = 1.5 * scale
		local ring = Instance.new("Part")
		ring.Size = Vector3.new(ringSize, 0.2, ringSize)
		ring.Position = to
		ring.Anchored = true
		ring.CanCollide = false
		ring.Color = splashColors[math.random(1, #splashColors)]
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.1
		ring.Parent = workspace

		task.spawn(function()
			for k = 1, 8 do
				task.wait(0.025)
				local t = k / 8
				local sz = ringSize + 6 * scale * t
				ring.Size = Vector3.new(sz, 0.2 * (1 - t * 0.5), sz)
				ring.Transparency = 0.1 + 0.9 * t
			end
			ring:Destroy()
		end)
	end

	-- Streak trails (only with 3+ runes)
	if runeCount >= 3 then
		local streakCount = math.min(runeCount, 6)
		for j = 1, streakCount do
			local streak = Instance.new("Part")
			streak.Size = Vector3.new(0.2 * scale, 0.2 * scale, 1.5 * scale)
			streak.Material = Enum.Material.Neon
			streak.Color = splashColors[math.random(1, #splashColors)]
			streak.Anchored = true
			streak.CanCollide = false
			streak.Position = to
			streak.Parent = workspace

			local angle = (j / streakCount) * math.pi * 2 + math.random() * 0.3
			local dir = Vector3.new(math.cos(angle), 0.4 + math.random() * 0.5, math.sin(angle))
			local speed = 4 * scale

			task.spawn(function()
				for k = 1, 6 do
					task.wait(0.03)
					local t = k / 6
					local pos = to + dir * speed * t
					streak.CFrame = CFrame.lookAt(pos, pos + dir)
					streak.Transparency = t
				end
				streak:Destroy()
			end)
		end
	end
end

-- Coin pop animation for coin printer
local function playCoinPopAnimation(turretPosition: Vector3, value: number)
	task.spawn(function()
		-- Spawn a golden coin that pops up and fades
		local coin = Instance.new("Part")
		coin.Name = "CoinPop"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.3, 1.2, 1.2)
		coin.CFrame = CFrame.new(turretPosition + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		coin.Anchored = true
		coin.CanCollide = false
		coin.Color = Color3.fromRGB(255, 215, 0)
		coin.Material = Enum.Material.Neon
		coin.Parent = workspace

		-- Value label floating above coin
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 60, 0, 30)
		billboard.StudsOffset = Vector3.new(0, 1.5, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = coin
		billboard.Parent = coin

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "+💰" .. value
		label.TextColor3 = Color3.fromRGB(255, 220, 50)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = billboard

		-- Animate: pop up, spin, fade out
		local startY = turretPosition.Y + 3
		for k = 1, 20 do
			task.wait(0.04)
			local t = k / 20
			local y = startY + 4 * t - 2 * t * t -- arc upward then slow
			local spin = t * math.pi * 4
			coin.CFrame = CFrame.new(turretPosition.X, y, turretPosition.Z)
				* CFrame.Angles(0, spin, math.rad(90))
			coin.Transparency = t * t
			label.TextTransparency = t * t
		end
		coin:Destroy()
	end)
end

-- Shared support tower tick logic (used by both update and updateSupport)
local function tickSupportTurrets(dt: number)
	for _, turret in pairs(turrets) do
		local turretType = TurretData.getTurretById(turret.turretTypeId)
		if not turretType or not turretType.supportType then continue end

		turret.supportCooldown = (turret.supportCooldown or 0) - dt

		-- Coin printer charging glow: intensifies as cooldown approaches 0
		if turretType.supportType == "money" and turret.model then
			local interval = turretType.supportInterval
			local remaining = math.max(turret.supportCooldown, 0)
			local chargeProgress = 1 - (remaining / interval) -- 0 = just fired, 1 = about to fire

			-- Update the coin part glow and body color based on charge
			local coinPart = turret.model:FindFirstChild("Coin")
			local bodyPart = turret.model:FindFirstChild("Body")

			if coinPart then
				-- Coin gets brighter and bigger as it charges
				local baseSize = 0.2
				local growSize = baseSize + chargeProgress * 0.15
				coinPart.Size = Vector3.new(growSize, 1.2 + chargeProgress * 0.4, 1.2 + chargeProgress * 0.4)
				coinPart.Transparency = 0.3 * (1 - chargeProgress) -- becomes fully opaque at max charge

				-- Spin faster as charge builds
				local spinSpeed = 1 + chargeProgress * 4
				local t = tick() * spinSpeed
				local basePos = turret.position + Vector3.new(0, 3.5 + chargeProgress * 0.5, 0)
				coinPart.CFrame = CFrame.new(basePos) * CFrame.Angles(0, t, math.rad(90))
			end

			if bodyPart then
				-- Body shifts from gold to bright white-gold as charge builds
				local r = math.floor(255)
				local g = math.floor(200 + chargeProgress * 55)
				local b = math.floor(50 + chargeProgress * 200)
				bodyPart.Color = Color3.fromRGB(r, g, b)
			end

			-- Spawn charging particles at high charge levels
			if chargeProgress > 0.6 and math.random() < chargeProgress * 0.3 then
				task.spawn(function()
					local spark = Instance.new("Part")
					spark.Size = Vector3.new(0.3, 0.3, 0.3)
					spark.Shape = Enum.PartType.Ball
					spark.Material = Enum.Material.Neon
					spark.Color = Color3.fromRGB(255, 220, math.random(0, 100))
					spark.Anchored = true
					spark.CanCollide = false
					local angle = math.random() * math.pi * 2
					local radius = 1.5 + math.random() * 1
					spark.Position = turret.position + Vector3.new(
						math.cos(angle) * radius,
						2.5 + math.random() * 2,
						math.sin(angle) * radius
					)
					spark.Parent = workspace
					-- Float upward and fade
					for k = 1, 6 do
						task.wait(0.04)
						local t2 = k / 6
						spark.Position = spark.Position + Vector3.new(0, 0.3, 0)
						spark.Transparency = t2
						local sz = 0.3 * (1 - t2 * 0.7)
						spark.Size = Vector3.new(sz, sz, sz)
					end
					spark:Destroy()
				end)
			end
		end

		if turret.supportCooldown <= 0 then
			local value = math.floor(turretType.supportValue * (1.5 ^ (turret.level - 1)))
			turret.supportCooldown = turretType.supportInterval

			if turretType.supportType == "money" and onSupportMoney then
				onSupportMoney(turret.ownerId, value)
				playCoinPopAnimation(turret.position, value)

				-- Reset body color back to gold after firing
				if turret.model then
					local bodyPart = turret.model:FindFirstChild("Body")
					if bodyPart then
						bodyPart.Color = Color3.fromRGB(255, 200, 50)
					end
				end
			elseif turretType.supportType == "health" and onSupportHealth then
				onSupportHealth(value)
			end
		end
	end
end

-- Update support turrets only (called during intermission)
function TurretManager.updateSupport(dt: number)
	tickSupportTurrets(dt)
end

-- Update all turrets each heartbeat — combat turrets target/fire, support turrets tick effects
function TurretManager.update(dt: number)
	-- Tick support turrets
	tickSupportTurrets(dt)

	local turretCount = 0
	for _, turret in pairs(turrets) do
		turretCount += 1
		local turretType = TurretData.getTurretById(turret.turretTypeId)

		-- Skip support towers (already handled above)
		if turretType and turretType.supportType then continue end

		-- Combat turret logic
		turret.cooldown -= dt

		local stats = turret.stats
		local targetId, targetPos = findTarget(turret.position, stats.range)
		
		-- Debug: print once per turret
		if not turret._debugTargetPrinted and turret.model then
			turret._debugTargetPrinted = true
			print("[TurretManager] Turret " .. turret.id .. " | Range: " .. stats.range .. " | Target: " .. tostring(targetId))
		end

		-- Rotate Head (or fallback to Body/Barrel) to face target
		if turret.model then
			local turretPos = turret.position
			
			-- Look for Head model first (preferred structure)
			local head = turret.model:FindFirstChild("Head")
			if head and head:IsA("Model") then
				-- Store original part offsets on first run
				if not turret._headPartOffsets then
					turret._headPartOffsets = {}
					local headPivot = head:GetPivot()
					
					-- Store the original pivot position (fixed rotation center)
					turret._pivotPosition = headPivot.Position
					
					-- Calculate the model's original facing angle (for offset correction)
					local lookVector = headPivot.LookVector
					turret._originalAngle = math.atan2(lookVector.X, lookVector.Z)
					
					for _, part in ipairs(head:GetDescendants()) do
						if part:IsA("BasePart") then
							-- Store offset from pivot and local rotation
							local partCF = part.CFrame
							local offset = headPivot:Inverse() * partCF
							turret._headPartOffsets[part] = offset
						end
					end
					turret._lastAngle = 0
				end
				
				-- Only update angle if we have a target
				if targetId and targetPos then
					local pivotPos = turret._pivotPosition
					local dx = targetPos.X - pivotPos.X
					local dz = targetPos.Z - pivotPos.Z
					-- Calculate target angle, adjusted by model's original facing direction
					local targetAngle = math.atan2(dx, dz) - turret._originalAngle
					
					-- Smooth rotation (lerp towards target angle)
					local currentAngle = turret._lastAngle or 0
					local angleDiff = targetAngle - currentAngle
					
					-- Normalize angle difference to -PI to PI
					while angleDiff > math.pi do angleDiff = angleDiff - 2 * math.pi end
					while angleDiff < -math.pi do angleDiff = angleDiff + 2 * math.pi end
					
					-- Lerp speed (0.2 = smooth, 1.0 = instant)
					local lerpSpeed = 0.15
					turret._lastAngle = currentAngle + angleDiff * lerpSpeed
				end
				
				-- Apply rotation (use stored pivot position)
				local pivotPos = turret._pivotPosition
				local rotatedPivot = CFrame.new(pivotPos) * CFrame.Angles(0, turret._lastAngle, 0)
				
				-- Apply stored offsets with new rotation
				for part, offset in pairs(turret._headPartOffsets) do
					if part and part.Parent then
						part.CFrame = rotatedPivot * offset
					end
				end
			elseif targetId and targetPos then
				-- Fallback: rotate Barrel only (legacy/procedural models)
				local barrel = turret.model:FindFirstChild("Barrel")
				if barrel then
					local barrelOrigin = turretPos + Vector3.new(0, 3, 0)
					local lookCF = CFrame.lookAt(barrelOrigin, targetPos)
					if barrel:IsA("Model") then
						barrel:PivotTo(lookCF)
					else
						barrel.CFrame = lookCF
					end
				end
			end
		end

		if turret.cooldown > 0 then continue end
		if not targetId or not targetPos then continue end

		-- Set cooldown to 1 / fireRate
		turret.cooldown = 1 / stats.fireRate

		-- Fire from MuzzlePoint attachment(s) - supports alternating dual barrels
		local fireFrom: Vector3
		
		-- Find all MuzzlePoint attachments in Head (or Barrel as fallback)
		local muzzlePoints: {Attachment} = {}
		local head = turret.model and turret.model:FindFirstChild("Head")
		if head then
			for _, desc in ipairs(head:GetDescendants()) do
				if desc:IsA("Attachment") and desc.Name:match("^MuzzlePoint") then
					table.insert(muzzlePoints, desc)
				end
			end
		end
		
		-- Fallback: check Barrel directly (legacy structure)
		if #muzzlePoints == 0 then
			local barrel = turret.model and turret.model:FindFirstChild("Barrel")
			if barrel then
				local muzzle = barrel:FindFirstChild("MuzzlePoint")
				if muzzle and muzzle:IsA("Attachment") then
					table.insert(muzzlePoints, muzzle)
				end
			end
		end
		
		-- Debug: print muzzle points found (once per turret)
		if not turret._debugMuzzlePrinted then
			turret._debugMuzzlePrinted = true
			print("[TurretManager] Turret " .. turret.id .. " found " .. #muzzlePoints .. " MuzzlePoints")
			for i, mp in ipairs(muzzlePoints) do
				print("  MuzzlePoint " .. i .. ": " .. mp.Name .. " at " .. tostring(mp.WorldPosition))
			end
			-- Debug: print all descendants of Head to see what's there
			if head then
				print("[TurretManager] Head descendants:")
				for _, desc in ipairs(head:GetDescendants()) do
					print("  " .. desc.ClassName .. ": " .. desc.Name)
				end
			else
				print("[TurretManager] No Head found in model")
			end
		end
		
		if #muzzlePoints > 0 then
			-- Initialize muzzle index if not set
			if not turret._lastMuzzleIndex then
				turret._lastMuzzleIndex = 0
			end
			-- Alternate to next muzzle (1-2-1-2 pattern)
			turret._lastMuzzleIndex = (turret._lastMuzzleIndex % #muzzlePoints) + 1
			fireFrom = muzzlePoints[turret._lastMuzzleIndex].WorldPosition
		else
			-- Fallback: no muzzle points found, calculate from barrel or turret position
			local barrel = turret.model and turret.model:FindFirstChild("Barrel")
			if barrel then
				local barrelCF = if barrel:IsA("Model") then barrel:GetPivot() else barrel.CFrame
				local barrelPos = if barrel:IsA("Model") then barrel:GetPivot().Position else barrel.Position
				fireFrom = barrelPos + barrelCF.LookVector * 1.0
			else
				fireFrom = turret.position + Vector3.new(0, 3, 0)
			end
		end

		-- Gather rune colors for this turret's applied runes
		local runeColors: { Color3 }? = nil
		if getTurretRunesCallback then
			local runeSlot = getTurretRunesCallback(turret.id)
			if runeSlot and #runeSlot > 0 then
				runeColors = {}
				local seen: { [number]: boolean } = {}
				for _, rId in ipairs(runeSlot) do
					if not seen[rId] then
						seen[rId] = true
						local res = ResourceData.Resources[rId]
						if res then
							table.insert(runeColors, res.color)
						end
					end
				end
			end
		end

		-- Get turret-specific shoot sound if defined
		local shootSoundId: string? = nil
		if turretType then
			shootSoundId = turretType.shootSound
		end

		task.spawn(fireProjectile, fireFrom, targetPos, runeColors, shootSoundId)

		-- Deal damage equal to turret's damage stat (single-target only)
		-- Apply 2X damage multiplier if owner has the gamepass
		local damageMultiplier = GamepassManager.getDamageMultiplier(turret.ownerId)
		EnemyManager.damageEnemy(targetId, stats.damage * damageMultiplier)

		-- Apply rune visual effects on the enemy
		if getTurretRunesCallback then
			local runeSlot = getTurretRunesCallback(turret.id)
			if runeSlot and #runeSlot > 0 then
				EnemyManager.applyRuneEffect(targetId, runeSlot)
				
				-- Apply slow effect if Frost rune (id 2) is equipped
				for _, runeId in ipairs(runeSlot) do
					if runeId == 2 then
						-- Frost rune: 50% slow for 3 seconds (very noticeable)
						EnemyManager.applySlow(targetId, 0.5, 3.0)
						break
					end
				end
			end
		end

		-- Frost turret applies slow effect
		local turretType2 = TurretData.getTurretById(turret.turretTypeId)
		if turretType2 and turretType2.id == 5 then
			EnemyManager.applySlow(targetId, 0.4, 2.0) -- 60% slow for 2 seconds
		end
	end
end

return TurretManager
