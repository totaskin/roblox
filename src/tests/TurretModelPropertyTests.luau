-- TurretModelPropertyTests.luau
-- Property-based tests for the Turret 3D Models feature.
-- Uses PropertyGen.check with 100 iterations per property.
-- Each property maps to a correctness property from the design document.
--
-- Since actual 3D models are created manually in Roblox Studio, these tests
-- use mock model data from TurretModelTestHarness to validate structure requirements.
--
-- To run: require this module and call TurretModelPropertyTests.runAll()

local PropertyGen = require(script.Parent.PropertyGen)
local TurretModelTestHarness = require(script.Parent.TurretModelTestHarness)

local TurretData = require(script.Parent.Parent.shared.TurretData)

local ITERATIONS = 100

local TurretModelPropertyTests = {}
TurretModelPropertyTests.results = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-3d-models, Property 1: Model Naming Matches TurretData
-- For any turret type defined in TurretData, the expected model name in
-- ReplicatedStorage.TurretModels should exactly match the `name` field from
-- TurretData (e.g., "Scout Turret", "Tesla Turret").
-- **Validates: Requirements 1.2**
-- ═══════════════════════════════════════════════════════════════════════════
function TurretModelPropertyTests.property1_ModelNamingMatchesTurretData(): (boolean, number?)
	local harness = TurretModelTestHarness.new()
	local allTurrets = TurretData.getAllTurrets()

	return PropertyGen.check(ITERATIONS, function()
		-- Pick a random turret from TurretData
		local turretIndex = PropertyGen.int(1, #allTurrets)
		local turretType = allTurrets[turretIndex]
		local expectedName = turretType.name

		-- Load the model from the mock TurretModels folder
		local model, _err = harness.loadModel(expectedName)

		-- Model should exist and name should match exactly
		if not model then
			return false
		end

		-- Validate using harness function
		local isValid, _errorMsg = TurretModelTestHarness.validateModelNameMatchesTurretData(model)
		return isValid
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-3d-models, Property 2: Combat Turret Model Structure
-- For any combat turret model (Scout, Marksman, Rapid, Cannon, Frost, Tesla),
-- the model should contain: (a) a Part named "Base" set as PrimaryPart,
-- (b) a Part named "Body", (c) a Part named "Barrel", and (d) an Attachment
-- named "MuzzlePoint" parented to the Barrel.
-- **Validates: Requirements 2.1, 2.2, 2.3**
-- ═══════════════════════════════════════════════════════════════════════════
function TurretModelPropertyTests.property2_CombatTurretModelStructure(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function()
		-- Generate a random combat turret model
		local turretName = TurretModelTestHarness.randomCombatTurretName()
		local model = TurretModelTestHarness.createMockCombatTurretModel(turretName)

		-- Validate structure using harness validation function
		local isValid, _errorMsg = TurretModelTestHarness.validateCombatTurretStructure(model)
		return isValid
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-3d-models, Property 3: Support Turret Model Structure
-- For any support turret model (Coin Printer, Medic Station), the model should
-- contain: (a) a Part named "Base" set as PrimaryPart, (b) a Part named "Body",
-- and (c) an Attachment named "EffectPoint".
-- **Validates: Requirements 2.1, 2.4**
-- ═══════════════════════════════════════════════════════════════════════════
function TurretModelPropertyTests.property3_SupportTurretModelStructure(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function()
		-- Generate a random support turret model
		local turretName = TurretModelTestHarness.randomSupportTurretName()
		local model = TurretModelTestHarness.createMockSupportTurretModel(turretName)

		-- Validate structure using harness validation function
		local isValid, _errorMsg = TurretModelTestHarness.validateSupportTurretStructure(model)
		return isValid
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-3d-models, Property 4: Base Part Properties After Placement
-- For any turret model after placement, the Base part should have Anchored set
-- to true and CanCollide set to true.
-- **Validates: Requirements 2.5**
-- ═══════════════════════════════════════════════════════════════════════════
function TurretModelPropertyTests.property4_BasePartPropertiesAfterPlacement(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function()
		-- Randomly choose between combat and support turret
		local isCombat = PropertyGen.int(0, 1) == 1
		local model

		if isCombat then
			-- Generate a random combat turret model
			local turretName = TurretModelTestHarness.randomCombatTurretName()
			model = TurretModelTestHarness.createMockCombatTurretModel(turretName)
		else
			-- Generate a random support turret model
			local turretName = TurretModelTestHarness.randomSupportTurretName()
			model = TurretModelTestHarness.createMockSupportTurretModel(turretName)
		end

		-- Validate Base part properties using harness validation function
		local isValid, _errorMsg = TurretModelTestHarness.validateBasePartProperties(model)
		return isValid
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-3d-models, Property 5: Model Lookup By Name
-- For any turret type id, calling the model loader with that turret's name
-- should return a model from ReplicatedStorage.TurretModels with a matching
-- name, or nil if not found.
-- **Validates: Requirements 1.1, 11.1**
-- ═══════════════════════════════════════════════════════════════════════════
function TurretModelPropertyTests.property5_ModelLookupByName(): (boolean, number?)
	local harness = TurretModelTestHarness.new()
	local allTurrets = TurretData.getAllTurrets()

	-- Collect all valid turret names for lookup
	local validTurretNames = {}
	for _, turret in ipairs(allTurrets) do
		table.insert(validTurretNames, turret.name)
	end

	-- Invalid names for testing nil return
	local invalidNames = {
		"NonExistent Turret",
		"Invalid_Name",
		"",
		"scout turret", -- wrong case
		"TESLA TURRET", -- wrong case
		"Turret",
		"12345",
		"Scout",
		"Tesla",
	}

	return PropertyGen.check(ITERATIONS, function()
		-- 70% of the time test valid names, 30% test invalid names
		local testValidName = PropertyGen.int(1, 10) <= 7

		if testValidName then
			-- Test valid turret name lookup
			local nameIndex = PropertyGen.int(1, #validTurretNames)
			local turretName = validTurretNames[nameIndex]

			local model, _err = harness.loadModel(turretName)

			-- Model should exist and name should match
			if not model then
				return false
			end

			if model.Name ~= turretName then
				return false
			end

			return true
		else
			-- Test invalid turret name lookup (should return nil)
			local invalidIndex = PropertyGen.int(1, #invalidNames)
			local invalidName = invalidNames[invalidIndex]

			local model, _err = harness.loadModel(invalidName)

			-- Model should be nil for invalid names
			return model == nil
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-3d-models, Property 8: Part Count Respects Tier Limits
-- For any turret model, the total part count should not exceed the tier limit:
-- Scout ≤10, Marksman ≤15, Rapid ≤20, Cannon ≤25, Frost ≤25, Tesla ≤35,
-- Coin Printer ≤20, Medic Station ≤15.
-- **Validates: Requirements 3.3, 4.4, 5.4, 6.5, 7.5, 8.5, 9.5, 10.5**
-- ═══════════════════════════════════════════════════════════════════════════
function TurretModelPropertyTests.property8_PartCountRespectsTierLimits(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function()
		-- Randomly choose a turret name (any type)
		local turretName = TurretModelTestHarness.randomTurretName()
		local limit = TurretModelTestHarness.PART_COUNT_LIMITS[turretName]

		-- Generate a random part count within the valid range (1 to limit)
		-- This tests that models created within limits pass validation
		local randomPartCount = PropertyGen.int(1, limit)

		-- Create the appropriate model type with the random part count
		local model
		local isCombat = false
		for _, combatName in ipairs(TurretModelTestHarness.COMBAT_TURRET_NAMES) do
			if combatName == turretName then
				isCombat = true
				break
			end
		end

		if isCombat then
			model = TurretModelTestHarness.createMockCombatTurretModel(turretName, randomPartCount)
		else
			model = TurretModelTestHarness.createMockSupportTurretModel(turretName, randomPartCount)
		end

		-- Validate part count is within tier limit using harness validation function
		local isValid, _errorMsg = TurretModelTestHarness.validatePartCountLimit(model, turretName)
		return isValid
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-3d-models, Property 9: Visual Complexity Increases With Price
-- For any two combat turret types where turret A has a higher shop price than
-- turret B, turret A's model should have a part count greater than or equal to
-- turret B's model part count.
-- **Validates: Requirements 12.1, 12.4**
-- ═══════════════════════════════════════════════════════════════════════════
function TurretModelPropertyTests.property9_VisualComplexityIncreasesWithPrice(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function()
		-- Generate two random combat turret names
		local turretNameA = TurretModelTestHarness.randomCombatTurretName()
		local turretNameB = TurretModelTestHarness.randomCombatTurretName()

		-- Get part count limits for each turret type
		local limitA = TurretModelTestHarness.PART_COUNT_LIMITS[turretNameA]
		local limitB = TurretModelTestHarness.PART_COUNT_LIMITS[turretNameB]

		-- Generate random part counts within valid ranges for each turret
		-- Use a minimum of 3 parts (Base, Body, Barrel) for combat turrets
		local partCountA = PropertyGen.int(3, limitA)
		local partCountB = PropertyGen.int(3, limitB)

		-- Create mock models with the generated part counts
		local modelA = TurretModelTestHarness.createMockCombatTurretModel(turretNameA, partCountA)
		local modelB = TurretModelTestHarness.createMockCombatTurretModel(turretNameB, partCountB)

		-- Validate visual complexity progression using harness validation function
		-- The harness compares prices internally and verifies higher-priced turrets
		-- have >= part count than lower-priced turrets
		local isValid, _errorMsg = TurretModelTestHarness.validateVisualComplexityProgression(
			modelA, turretNameA,
			modelB, turretNameB
		)
		return isValid
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Runner
-- ═══════════════════════════════════════════════════════════════════════════

function TurretModelPropertyTests.runAll(): { { name: string, passed: boolean, failedAt: number? } }
	local tests = {
		{ name = "Property 1: Model Naming Matches TurretData", fn = TurretModelPropertyTests.property1_ModelNamingMatchesTurretData },
		{ name = "Property 2: Combat Turret Model Structure", fn = TurretModelPropertyTests.property2_CombatTurretModelStructure },
		{ name = "Property 3: Support Turret Model Structure", fn = TurretModelPropertyTests.property3_SupportTurretModelStructure },
		{ name = "Property 4: Base Part Properties After Placement", fn = TurretModelPropertyTests.property4_BasePartPropertiesAfterPlacement },
		{ name = "Property 5: Model Lookup By Name", fn = TurretModelPropertyTests.property5_ModelLookupByName },
		{ name = "Property 8: Part Count Respects Tier Limits", fn = TurretModelPropertyTests.property8_PartCountRespectsTierLimits },
		{ name = "Property 9: Visual Complexity Increases With Price", fn = TurretModelPropertyTests.property9_VisualComplexityIncreasesWithPrice },
	}

	local results = {}
	local passCount = 0
	local failCount = 0

	for _, test in ipairs(tests) do
		local passed, failedAt = test.fn()
		table.insert(results, {
			name = test.name,
			passed = passed,
			failedAt = failedAt,
		})

		if passed then
			passCount += 1
			print("[PASS] " .. test.name)
		else
			failCount += 1
			print("[FAIL] " .. test.name .. " (failed at iteration " .. tostring(failedAt) .. ")")
		end
	end

	print(string.format("\n=== Turret Model Results: %d/%d passed, %d failed ===", passCount, #tests, failCount))

	TurretModelPropertyTests.results = results
	return results
end

return TurretModelPropertyTests
