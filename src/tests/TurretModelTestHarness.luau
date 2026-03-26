-- TurretModelTestHarness.luau
-- A test-friendly module for turret 3D model structure validation.
-- Provides mock model structures, validation functions, and constants
-- for property-based testing of turret model requirements.
--
-- Since actual 3D models are created manually in Roblox Studio, these mocks
-- represent the expected structure for validation purposes.

local PropertyGen = require(script.Parent.PropertyGen)
local TurretData = require(script.Parent.Parent.shared.TurretData)

local TurretModelTestHarness = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════════════════════

-- Combat turret names (have Barrel and MuzzlePoint)
TurretModelTestHarness.COMBAT_TURRET_NAMES = {
	"Scout Turret",
	"Marksman Turret",
	"Rapid Turret",
	"Cannon Turret",
	"Frost Turret",
	"Tesla Turret",
}

-- Support turret names (have EffectPoint instead)
TurretModelTestHarness.SUPPORT_TURRET_NAMES = {
	"Coin Printer",
	"Medic Station",
}

-- Part count limits by turret name (from design doc)
-- **Validates: Requirements 3.3, 4.4, 5.4, 6.5, 7.5, 8.5, 9.5, 10.5**
TurretModelTestHarness.PART_COUNT_LIMITS = {
	["Scout Turret"] = 10,
	["Marksman Turret"] = 15,
	["Rapid Turret"] = 20,
	["Cannon Turret"] = 25,
	["Frost Turret"] = 25,
	["Tesla Turret"] = 35,
	["Coin Printer"] = 20,
	["Medic Station"] = 15,
}

-- Shop prices for visual complexity validation (from TurretData)
TurretModelTestHarness.TURRET_SHOP_PRICES = {
	["Scout Turret"] = 0,
	["Marksman Turret"] = 1000,
	["Rapid Turret"] = 10000,
	["Cannon Turret"] = 100000,
	["Frost Turret"] = 1000000,
	["Tesla Turret"] = 10000000,
	["Coin Printer"] = 500,
	["Medic Station"] = 2000,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock Model Creation Functions
-- ═══════════════════════════════════════════════════════════════════════════

-- Helper: Create a mock combat turret model structure
-- Combat turrets have: Base (PrimaryPart), Body, Barrel with MuzzlePoint attachment
function TurretModelTestHarness.createMockCombatTurretModel(turretName: string, partCount: number?): any
	local limit = TurretModelTestHarness.PART_COUNT_LIMITS[turretName] or 10
	local actualPartCount = partCount or PropertyGen.int(3, limit)

	-- MuzzlePoint attachment on Barrel
	local muzzlePoint = {
		Name = "MuzzlePoint",
		ClassName = "Attachment",
		WorldPosition = Vector3.new(0, 2, 3),
	}

	-- Barrel part with MuzzlePoint
	local barrel = {
		Name = "Barrel",
		ClassName = "Part",
		Anchored = true,
		CanCollide = false,
		Children = { muzzlePoint },
		FindFirstChild = function(self, name: string)
			for _, child in ipairs(self.Children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end,
	}

	-- Base part (PrimaryPart)
	local base = {
		Name = "Base",
		ClassName = "Part",
		Anchored = true,
		CanCollide = true,
	}

	-- Body part
	local body = {
		Name = "Body",
		ClassName = "Part",
		Anchored = true,
		CanCollide = false,
		Color = Color3.fromRGB(60, 140, 200),
	}

	-- Additional detail parts to reach partCount
	local additionalParts = {}
	for i = 1, math.max(0, actualPartCount - 3) do
		table.insert(additionalParts, {
			Name = "Detail" .. i,
			ClassName = "Part",
			Anchored = true,
			CanCollide = false,
		})
	end

	-- Build children list
	local children = { base, body, barrel }
	for _, part in ipairs(additionalParts) do
		table.insert(children, part)
	end

	return {
		Name = turretName,
		ClassName = "Model",
		PrimaryPart = base,
		Children = children,
		PartCount = actualPartCount,
		FindFirstChild = function(self, name: string)
			for _, child in ipairs(self.Children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end,
		GetDescendants = function(self)
			local descendants = {}
			for _, child in ipairs(self.Children) do
				table.insert(descendants, child)
				if child.Children then
					for _, grandchild in ipairs(child.Children) do
						table.insert(descendants, grandchild)
					end
				end
			end
			return descendants
		end,
	}
end

-- Helper: Create a mock support turret model structure
-- Support turrets have: Base (PrimaryPart), Body with EffectPoint attachment
function TurretModelTestHarness.createMockSupportTurretModel(turretName: string, partCount: number?): any
	local limit = TurretModelTestHarness.PART_COUNT_LIMITS[turretName] or 15
	local actualPartCount = partCount or PropertyGen.int(2, limit)

	-- EffectPoint attachment on Body
	local effectPoint = {
		Name = "EffectPoint",
		ClassName = "Attachment",
		WorldPosition = Vector3.new(0, 2, 0),
	}

	-- Base part (PrimaryPart)
	local base = {
		Name = "Base",
		ClassName = "Part",
		Anchored = true,
		CanCollide = true,
	}

	-- Body part with EffectPoint
	local body = {
		Name = "Body",
		ClassName = "Part",
		Anchored = true,
		CanCollide = false,
		Color = Color3.fromRGB(60, 140, 200),
		Children = { effectPoint },
		FindFirstChild = function(self, name: string)
			for _, child in ipairs(self.Children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end,
	}

	-- Additional detail parts
	local additionalParts = {}
	for i = 1, math.max(0, actualPartCount - 2) do
		table.insert(additionalParts, {
			Name = "Detail" .. i,
			ClassName = "Part",
			Anchored = true,
			CanCollide = false,
		})
	end

	-- Build children list
	local children = { base, body }
	for _, part in ipairs(additionalParts) do
		table.insert(children, part)
	end

	return {
		Name = turretName,
		ClassName = "Model",
		PrimaryPart = base,
		Children = children,
		PartCount = actualPartCount,
		FindFirstChild = function(self, name: string)
			for _, child in ipairs(self.Children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end,
		GetDescendants = function(self)
			local descendants = {}
			for _, child in ipairs(self.Children) do
				table.insert(descendants, child)
				if child.Children then
					for _, grandchild in ipairs(child.Children) do
						table.insert(descendants, grandchild)
					end
				end
			end
			return descendants
		end,
	}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Random Selection Helpers
-- ═══════════════════════════════════════════════════════════════════════════

-- Get a random combat turret name
function TurretModelTestHarness.randomCombatTurretName(): string
	local names = TurretModelTestHarness.COMBAT_TURRET_NAMES
	return names[PropertyGen.int(1, #names)]
end

-- Get a random support turret name
function TurretModelTestHarness.randomSupportTurretName(): string
	local names = TurretModelTestHarness.SUPPORT_TURRET_NAMES
	return names[PropertyGen.int(1, #names)]
end

-- Get a random turret name (any type)
function TurretModelTestHarness.randomTurretName(): string
	local allNames = {}
	for _, name in ipairs(TurretModelTestHarness.COMBAT_TURRET_NAMES) do
		table.insert(allNames, name)
	end
	for _, name in ipairs(TurretModelTestHarness.SUPPORT_TURRET_NAMES) do
		table.insert(allNames, name)
	end
	return allNames[PropertyGen.int(1, #allNames)]
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Validation Functions
-- ═══════════════════════════════════════════════════════════════════════════

-- Validate combat turret model structure
-- Returns: (isValid: boolean, errorMessage: string?)
-- **Validates: Requirements 2.1, 2.2, 2.3**
function TurretModelTestHarness.validateCombatTurretStructure(model: any): (boolean, string?)
	-- (a) Verify Base part exists and is set as PrimaryPart
	local base = model:FindFirstChild("Base")
	if not base then
		return false, "Missing Base part"
	end
	if base.ClassName ~= "Part" then
		return false, "Base is not a Part (got " .. tostring(base.ClassName) .. ")"
	end
	if model.PrimaryPart ~= base then
		return false, "Base is not set as PrimaryPart"
	end

	-- (b) Verify Body part exists
	local body = model:FindFirstChild("Body")
	if not body then
		return false, "Missing Body part"
	end
	if body.ClassName ~= "Part" then
		return false, "Body is not a Part (got " .. tostring(body.ClassName) .. ")"
	end

	-- (c) Verify Barrel part exists
	local barrel = model:FindFirstChild("Barrel")
	if not barrel then
		return false, "Missing Barrel part"
	end
	if barrel.ClassName ~= "Part" then
		return false, "Barrel is not a Part (got " .. tostring(barrel.ClassName) .. ")"
	end

	-- (d) Verify MuzzlePoint attachment exists on Barrel
	local muzzlePoint = barrel:FindFirstChild("MuzzlePoint")
	if not muzzlePoint then
		return false, "Missing MuzzlePoint attachment on Barrel"
	end
	if muzzlePoint.ClassName ~= "Attachment" then
		return false, "MuzzlePoint is not an Attachment (got " .. tostring(muzzlePoint.ClassName) .. ")"
	end

	return true, nil
end

-- Validate support turret model structure
-- Returns: (isValid: boolean, errorMessage: string?)
-- **Validates: Requirements 2.1, 2.4**
function TurretModelTestHarness.validateSupportTurretStructure(model: any): (boolean, string?)
	-- (a) Verify Base part exists and is set as PrimaryPart
	local base = model:FindFirstChild("Base")
	if not base then
		return false, "Missing Base part"
	end
	if base.ClassName ~= "Part" then
		return false, "Base is not a Part (got " .. tostring(base.ClassName) .. ")"
	end
	if model.PrimaryPart ~= base then
		return false, "Base is not set as PrimaryPart"
	end

	-- (b) Verify Body part exists
	local body = model:FindFirstChild("Body")
	if not body then
		return false, "Missing Body part"
	end
	if body.ClassName ~= "Part" then
		return false, "Body is not a Part (got " .. tostring(body.ClassName) .. ")"
	end

	-- (c) Verify EffectPoint attachment exists on Body
	local effectPoint = body:FindFirstChild("EffectPoint")
	if not effectPoint then
		return false, "Missing EffectPoint attachment on Body"
	end
	if effectPoint.ClassName ~= "Attachment" then
		return false, "EffectPoint is not an Attachment (got " .. tostring(effectPoint.ClassName) .. ")"
	end

	return true, nil
end

-- Validate part count is within tier limit
-- Returns: (isValid: boolean, errorMessage: string?)
-- **Validates: Requirements 3.3, 4.4, 5.4, 6.5, 7.5, 8.5, 9.5, 10.5**
function TurretModelTestHarness.validatePartCountLimit(model: any, turretName: string): (boolean, string?)
	local limit = TurretModelTestHarness.PART_COUNT_LIMITS[turretName]
	if not limit then
		return false, "Unknown turret name: " .. tostring(turretName)
	end

	local partCount = model.PartCount
	if not partCount then
		-- Count parts manually if PartCount not set
		partCount = 0
		for _, child in ipairs(model.Children or {}) do
			if child.ClassName == "Part" then
				partCount = partCount + 1
			end
		end
	end

	if partCount > limit then
		return false, string.format(
			"Part count %d exceeds limit %d for %s",
			partCount, limit, turretName
		)
	end

	return true, nil
end

-- Validate Base part properties (Anchored and CanCollide)
-- Returns: (isValid: boolean, errorMessage: string?)
-- **Validates: Requirements 2.5**
function TurretModelTestHarness.validateBasePartProperties(model: any): (boolean, string?)
	local base = model:FindFirstChild("Base")
	if not base then
		return false, "Missing Base part"
	end

	if base.Anchored ~= true then
		return false, "Base.Anchored is not true"
	end

	if base.CanCollide ~= true then
		return false, "Base.CanCollide is not true"
	end

	return true, nil
end

-- Validate model name matches TurretData
-- Returns: (isValid: boolean, errorMessage: string?)
-- **Validates: Requirements 1.2**
function TurretModelTestHarness.validateModelNameMatchesTurretData(model: any): (boolean, string?)
	local modelName = model.Name
	if not modelName then
		return false, "Model has no Name"
	end

	-- Check if name exists in TurretData
	local turrets = TurretData.getAllTurrets()
	for _, turret in ipairs(turrets) do
		if turret.name == modelName then
			return true, nil
		end
	end

	return false, "Model name '" .. tostring(modelName) .. "' does not match any turret in TurretData"
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock Model Loader (simulates ReplicatedStorage.TurretModels lookup)
-- ═══════════════════════════════════════════════════════════════════════════

-- Create a mock TurretModels folder with all turret models
function TurretModelTestHarness.createMockTurretModelsFolder(): any
	local models = {}

	-- Add combat turret models
	for _, name in ipairs(TurretModelTestHarness.COMBAT_TURRET_NAMES) do
		models[name] = TurretModelTestHarness.createMockCombatTurretModel(name)
	end

	-- Add support turret models
	for _, name in ipairs(TurretModelTestHarness.SUPPORT_TURRET_NAMES) do
		models[name] = TurretModelTestHarness.createMockSupportTurretModel(name)
	end

	return {
		Name = "TurretModels",
		ClassName = "Folder",
		Models = models,
		FindFirstChild = function(self, name: string)
			return self.Models[name]
		end,
	}
end

-- Mock model loader function (simulates loadTurretModel from TurretManager)
-- Returns: (model: any?, errorMessage: string?)
-- **Validates: Requirements 1.1, 11.1**
function TurretModelTestHarness.loadTurretModel(turretModelsFolder: any, turretName: string): (any?, string?)
	if not turretModelsFolder then
		return nil, "TurretModels folder not found"
	end

	local model = turretModelsFolder:FindFirstChild(turretName)
	if not model then
		return nil, "Model not found for turret: " .. tostring(turretName)
	end

	-- Return a "clone" (in mock, just return the model itself)
	return model, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Visual Complexity Helpers
-- ═══════════════════════════════════════════════════════════════════════════

-- Check if turret A has higher or equal visual complexity than turret B
-- (based on part count, where higher price should mean >= part count)
-- **Validates: Requirements 12.1, 12.4**
function TurretModelTestHarness.validateVisualComplexityProgression(
	modelA: any,
	turretNameA: string,
	modelB: any,
	turretNameB: string
): (boolean, string?)
	local priceA = TurretModelTestHarness.TURRET_SHOP_PRICES[turretNameA]
	local priceB = TurretModelTestHarness.TURRET_SHOP_PRICES[turretNameB]

	if not priceA or not priceB then
		return false, "Unknown turret name(s)"
	end

	-- Only compare if A is more expensive than B
	if priceA <= priceB then
		return true, nil -- No constraint when A is cheaper or equal
	end

	-- A is more expensive, so A should have >= part count
	local partCountA = modelA.PartCount or 0
	local partCountB = modelB.PartCount or 0

	if partCountA < partCountB then
		return false, string.format(
			"%s (price %d, parts %d) has fewer parts than %s (price %d, parts %d)",
			turretNameA, priceA, partCountA,
			turretNameB, priceB, partCountB
		)
	end

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Instance Factory
-- ═══════════════════════════════════════════════════════════════════════════

function TurretModelTestHarness.new()
	local self = {} :: any

	-- Create mock TurretModels folder
	self.turretModelsFolder = TurretModelTestHarness.createMockTurretModelsFolder()

	-- Expose constants
	self.COMBAT_TURRET_NAMES = TurretModelTestHarness.COMBAT_TURRET_NAMES
	self.SUPPORT_TURRET_NAMES = TurretModelTestHarness.SUPPORT_TURRET_NAMES
	self.PART_COUNT_LIMITS = TurretModelTestHarness.PART_COUNT_LIMITS
	self.TURRET_SHOP_PRICES = TurretModelTestHarness.TURRET_SHOP_PRICES

	-- Helper: Load a turret model by name
	function self.loadModel(turretName: string): (any?, string?)
		return TurretModelTestHarness.loadTurretModel(self.turretModelsFolder, turretName)
	end

	-- Helper: Create a fresh combat turret model
	function self.createCombatModel(turretName: string, partCount: number?): any
		return TurretModelTestHarness.createMockCombatTurretModel(turretName, partCount)
	end

	-- Helper: Create a fresh support turret model
	function self.createSupportModel(turretName: string, partCount: number?): any
		return TurretModelTestHarness.createMockSupportTurretModel(turretName, partCount)
	end

	-- Helper: Get a random combat turret name
	function self.randomCombatName(): string
		return TurretModelTestHarness.randomCombatTurretName()
	end

	-- Helper: Get a random support turret name
	function self.randomSupportName(): string
		return TurretModelTestHarness.randomSupportTurretName()
	end

	-- Helper: Get a random turret name (any type)
	function self.randomTurretName(): string
		return TurretModelTestHarness.randomTurretName()
	end

	-- Reset the mock folder (recreate all models)
	function self.reset()
		self.turretModelsFolder = TurretModelTestHarness.createMockTurretModelsFolder()
	end

	return self
end

return TurretModelTestHarness
