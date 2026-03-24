-- RunePropertyTests.luau
-- Property-based tests for the Rune System.
-- Uses a lightweight check-based approach with randomised inputs.
-- Each property runs a minimum of 100 iterations.
--
-- To run: require this module and call RunePropertyTests.runAll()
-- Each test returns { passed: boolean, property: string, failedAt: number? }

local PropertyGen = require(script.Parent.PropertyGen)
local RuneTestHarness = require(script.Parent.RuneTestHarness)
local RuneCombinationData = require(script.Parent.Parent.shared.RuneCombinationData)

local ITERATIONS = 100

local RunePropertyTests = {}
RunePropertyTests.results = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 1: Boss Drop Awards Exactly One Rune Per Player
-- For any round number and any set of player ids, calling awardBossDrop
-- should increment exactly one rune type count by exactly one for each
-- player, and the awarded rune type id should be in [1, 10].
-- **Validates: Requirements 1.1, 1.2**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property1_BossDropAwardsExactlyOneRunePerPlayer(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()

		-- Generate 1-4 random player ids
		local numPlayers = PropertyGen.int(1, 4)
		local userIds = {}
		for p = 1, numPlayers do
			local uid = PropertyGen.int(1, 999999)
			harness.runeManager.initPlayer(uid)
			userIds[p] = uid
		end

		-- Record total inventory count for each player before
		local beforeCounts = {}
		for _, uid in ipairs(userIds) do
			local inv = harness.runeManager.getInventory(uid)
			local total = 0
			for t = 1, 10 do
				total += (inv[t] or 0)
			end
			beforeCounts[uid] = total
		end

		-- Generate random round and call awardBossDrop
		local round = PropertyGen.int(1, 100)
		local runeTypeId = harness.runeManager.awardBossDrop(userIds, round)

		-- Verify: returned runeTypeId is in [1, 10]
		if runeTypeId < 1 or runeTypeId > 10 then
			return false
		end

		-- Verify: each player's total inventory increased by exactly 1
		for _, uid in ipairs(userIds) do
			local inv = harness.runeManager.getInventory(uid)
			local total = 0
			for t = 1, 10 do
				total += (inv[t] or 0)
			end
			if total ~= beforeCounts[uid] + 1 then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 2: Inventory Non-Negative Invariant
-- For any sequence of rune operations (init, award, apply, return), all
-- rune inventory counts for all players should remain non-negative, and a
-- freshly initialized player should have zero counts for all 10 types.
-- **Validates: Requirements 2.1, 2.2**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property2_InventoryNonNegativeInvariant(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()
		local uid = PropertyGen.int(1, 999999)
		harness.runeManager.initPlayer(uid)

		-- Verify all 10 counts are 0 after init
		local inv = harness.runeManager.getInventory(uid)
		for t = 1, 10 do
			if (inv[t] or 0) ~= 0 then
				return false
			end
		end

		-- Helper to check all counts >= 0
		local function allNonNegative()
			local currentInv = harness.runeManager.getInventory(uid)
			for t = 1, 10 do
				if (currentInv[t] or 0) < 0 then
					return false
				end
			end
			return true
		end

		-- Do random operations: award some runes
		local numAwards = PropertyGen.int(1, 5)
		for _ = 1, numAwards do
			local round = PropertyGen.int(1, 100)
			harness.runeManager.awardBossDrop({ uid }, round)
			if not allNonNegative() then
				return false
			end
		end

		-- Apply some runes (with valid setup)
		harness.runeManager.setGamePhase("Intermission")
		local turretId = "turret_" .. tostring(uid)
		harness.addMockTurret(turretId, 1, uid)

		local currentInv = harness.runeManager.getInventory(uid)
		for t = 1, 10 do
			if (currentInv[t] or 0) > 0 then
				harness.runeManager.applyRune(uid, turretId, t)
				if not allNonNegative() then
					return false
				end
			end
		end

		-- Return all runes
		harness.runeManager.returnAllRunes()
		if not allNonNegative() then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 3: Ownership Validation
-- For any player and any turret not owned by that player, applyRune should
-- return (false, "Not your turret") with no state change.
-- **Validates: Requirements 3.2, 3.5**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property3_OwnershipValidation(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()
		harness.runeManager.setGamePhase("Intermission")

		-- Create player A with runes
		local playerA = PropertyGen.int(1, 499999)
		local playerB = PropertyGen.int(500000, 999999)
		local runeTypeId = PropertyGen.runeTypeId()

		harness.runeManager.initPlayer(playerA)
		local invA = harness.runeManager.getInventory(playerA)
		invA[runeTypeId] = 3

		-- Create turret owned by player B
		local turretId = "turret_ownership_" .. tostring(_i)
		harness.addMockTurret(turretId, 1, playerB)

		-- Record state before
		local countBefore = invA[runeTypeId]
		local slotBefore = #harness.runeManager.getTurretRunes(turretId)

		-- Call applyRune(playerA, turretId, runeTypeId)
		local success, reason = harness.runeManager.applyRune(playerA, turretId, runeTypeId)

		-- Verify returns (false, "Not your turret")
		if success ~= false then return false end
		if reason ~= "Not your turret" then return false end

		-- Verify player A's inventory unchanged
		if invA[runeTypeId] ~= countBefore then return false end

		-- Verify turret rune slot unchanged
		if #harness.runeManager.getTurretRunes(turretId) ~= slotBefore then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 4: Empty Inventory Validation
-- For any player with zero count of a given rune type, applyRune should
-- return (false, "No runes of this type available") with no state change.
-- **Validates: Requirements 3.3, 3.6**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property4_EmptyInventoryValidation(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()
		harness.runeManager.setGamePhase("Intermission")

		local uid = PropertyGen.int(1, 999999)
		local runeTypeId = PropertyGen.runeTypeId()

		-- Create player with zero count of the random rune type
		harness.runeManager.initPlayer(uid)
		-- Inventory is already all zeros after init

		-- Create turret owned by player
		local turretId = "turret_empty_" .. tostring(_i)
		harness.addMockTurret(turretId, 1, uid)

		-- Record state before
		local slotBefore = #harness.runeManager.getTurretRunes(turretId)

		-- Call applyRune with that zero-count rune type
		local success, reason = harness.runeManager.applyRune(uid, turretId, runeTypeId)

		-- Verify returns (false, "No runes of this type available")
		if success ~= false then return false end
		if reason ~= "No runes of this type available" then return false end

		-- Verify turret rune slot unchanged
		if #harness.runeManager.getTurretRunes(turretId) ~= slotBefore then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 5: Phase Validation
-- For any game phase that is not "Intermission", applyRune should return
-- (false, "Runes can only be applied during intermission") with no state change.
-- **Validates: Requirements 3.7, 3.8**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property5_PhaseValidation(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()

		-- Set game phase to random non-Intermission value
		local phases = { "LOBBY", "Wave", "GameOver" }
		local phase = phases[PropertyGen.int(1, #phases)]
		harness.runeManager.setGamePhase(phase)

		-- Set up valid player/turret/inventory
		local uid = PropertyGen.int(1, 999999)
		local runeTypeId = PropertyGen.runeTypeId()
		harness.runeManager.initPlayer(uid)
		local inv = harness.runeManager.getInventory(uid)
		inv[runeTypeId] = 3

		local turretId = "turret_phase_" .. tostring(_i)
		harness.addMockTurret(turretId, 1, uid)

		-- Record state before
		local countBefore = inv[runeTypeId]
		local slotBefore = #harness.runeManager.getTurretRunes(turretId)

		-- Call applyRune
		local success, reason = harness.runeManager.applyRune(uid, turretId, runeTypeId)

		-- Verify returns (false, "Runes can only be applied during intermission")
		if success ~= false then return false end
		if reason ~= "Runes can only be applied during intermission" then return false end

		-- Verify inventory and rune slot unchanged
		if inv[runeTypeId] ~= countBefore then return false end
		if #harness.runeManager.getTurretRunes(turretId) ~= slotBefore then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 6: Valid Application Transfer
-- For any valid application (correct owner, non-zero inventory, intermission
-- phase), applyRune should decrement inventory by 1 and grow rune slot by 1.
-- **Validates: Requirements 3.4**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property6_ValidApplicationTransfer(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()

		local uid = PropertyGen.int(1, 999999)
		local runeTypeId = PropertyGen.runeTypeId()
		local turretTypeId = PropertyGen.int(1, 6)
		local turretId = "turret_apply_" .. tostring(_i)

		-- Set up valid scenario
		harness.setupValidScenario(uid, turretId, turretTypeId, runeTypeId)

		-- Record inventory count before
		local inv = harness.runeManager.getInventory(uid)
		local countBefore = inv[runeTypeId]
		local slotBefore = #harness.runeManager.getTurretRunes(turretId)

		-- Call applyRune
		local success, reason = harness.runeManager.applyRune(uid, turretId, runeTypeId)

		-- Verify returns (true, nil)
		if success ~= true then return false end
		if reason ~= nil then return false end

		-- Verify inventory count decremented by 1
		if inv[runeTypeId] ~= countBefore - 1 then return false end

		-- Verify turret rune slot length increased by 1
		if #harness.runeManager.getTurretRunes(turretId) ~= slotBefore + 1 then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 7: Combination Table Completeness
-- For all pairs (a, b) where 1 <= a < b <= 10, getPairEffect returns a
-- valid type and is order-independent.
-- **Validates: Requirements 4.1**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property7_CombinationTableCompleteness(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		for a = 1, 9 do
			for b = a + 1, 10 do
				local effectAB = RuneCombinationData.getPairEffect(a, b)
				local effectBA = RuneCombinationData.getPairEffect(b, a)

				-- Verify both return valid type
				local validTypes = { synergy = true, clash = true, neutral = true }
				if not validTypes[effectAB.type] then return false end
				if not validTypes[effectBA.type] then return false end

				-- Verify they return the same result (order-independent)
				if effectAB.type ~= effectBA.type then return false end
				if effectAB.damage ~= effectBA.damage then return false end
				if effectAB.range ~= effectBA.range then return false end
				if effectAB.fireRate ~= effectBA.fireRate then return false end
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 8: Combined Multiplier Computation
-- For any rune slot, computeCombinedMultipliers should match manual
-- computation of single + pair effects.
-- **Validates: Requirements 4.2, 4.5, 4.6**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property8_CombinedMultiplierComputation(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		-- Generate random rune slot
		local runeSlot = PropertyGen.runeSlot(5)

		-- Call computeCombinedMultipliers
		local computed = RuneCombinationData.computeCombinedMultipliers(runeSlot)

		-- Manually compute: start with {1,1,1}
		local manualDamage = 1
		local manualRange = 1
		local manualFireRate = 1

		-- Multiply by each rune's single effect
		for _, runeTypeId in ipairs(runeSlot) do
			local effect = RuneCombinationData.getSingleEffect(runeTypeId)
			manualDamage *= effect.damage
			manualRange *= effect.range
			manualFireRate *= effect.fireRate
		end

		-- Multiply by each unique pair effect
		for i = 1, #runeSlot - 1 do
			for j = i + 1, #runeSlot do
				local pairEffect = RuneCombinationData.getPairEffect(runeSlot[i], runeSlot[j])
				manualDamage *= pairEffect.damage
				manualRange *= pairEffect.range
				manualFireRate *= pairEffect.fireRate
			end
		end

		-- Verify results match (within floating point tolerance ~0.001)
		local tolerance = 0.001
		if math.abs(computed.damage - manualDamage) > tolerance then return false end
		if math.abs(computed.range - manualRange) > tolerance then return false end
		if math.abs(computed.fireRate - manualFireRate) > tolerance then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 9: Synergy/Clash Direction
-- For each synergy pair, at least one multiplier > 1.
-- For each clash pair, at least one multiplier < 1.
-- **Validates: Requirements 4.3, 4.4**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property9_SynergyClashDirection(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		for key, effect in pairs(RuneCombinationData.PairEffects) do
			local damage = effect.damage or 1
			local range = effect.range or 1
			local fireRate = effect.fireRate or 1

			if effect.type == "synergy" then
				-- At least one multiplier > 1
				if not (damage > 1 or range > 1 or fireRate > 1) then
					return false
				end
			elseif effect.type == "clash" then
				-- At least one multiplier < 1
				if not (damage < 1 or range < 1 or fireRate < 1) then
					return false
				end
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 10: Single-Rune Effects
-- For each rune type id 1-10, getSingleEffect returns correct multipliers
-- matching the requirements.
-- **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property10_SingleRuneEffects(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local expected = {
			[1]  = { damage = 1.15, range = 1,    fireRate = 1 },                          -- Ember
			[2]  = { damage = 1,    range = 1,    fireRate = 1,    special = "slow" },      -- Frost
			[3]  = { damage = 1,    range = 1,    fireRate = 1.2 },                         -- Spark
			[4]  = { damage = 1,    range = 1,    fireRate = 1,    special = "poison" },    -- Spore
			[5]  = { damage = 1.1,  range = 1,    fireRate = 1,    special = "critChance" },-- Shadow
			[6]  = { damage = 1.05, range = 1.1,  fireRate = 1 },                          -- Radiance
			[7]  = { damage = 1,    range = 1.25, fireRate = 1 },                          -- Stone
			[8]  = { damage = 1,    range = 1.05, fireRate = 1.15 },                       -- Gale
			[9]  = { damage = 1.2,  range = 1,    fireRate = 1.1 },                        -- Arcane
			[10] = { damage = 1.3,  range = 1,    fireRate = 0.9 },                        -- Void
		}

		for id = 1, 10 do
			local effect = RuneCombinationData.getSingleEffect(id)
			local exp = expected[id]
			local tolerance = 0.001

			if math.abs(effect.damage - exp.damage) > tolerance then return false end
			if math.abs(effect.range - exp.range) > tolerance then return false end
			if math.abs(effect.fireRate - exp.fireRate) > tolerance then return false end

			-- Check special if expected
			if exp.special then
				if effect.special ~= exp.special then return false end
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 11: Rune Slot Persistence
-- Applied runes persist across game phase transitions.
-- **Validates: Requirements 6.1, 6.3**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property11_RuneSlotPersistence(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()

		local uid = PropertyGen.int(1, 999999)
		harness.runeManager.initPlayer(uid)
		harness.runeManager.setGamePhase("Intermission")

		-- Set up turret and apply some runes
		local turretId = "turret_persist_" .. tostring(_i)
		local turretTypeId = PropertyGen.int(1, 6)
		harness.addMockTurret(turretId, turretTypeId, uid)

		-- Give player some runes and apply them
		local inv = harness.runeManager.getInventory(uid)
		local numRunes = PropertyGen.int(1, 4)
		for r = 1, numRunes do
			local rTypeId = PropertyGen.runeTypeId()
			inv[rTypeId] = (inv[rTypeId] or 0) + 1
			harness.runeManager.applyRune(uid, turretId, rTypeId)
		end

		-- Record rune slot contents
		local slotBefore = harness.runeManager.getTurretRunes(turretId)
		local slotCopy = {}
		for idx, v in ipairs(slotBefore) do
			slotCopy[idx] = v
		end

		-- Change game phase: Intermission -> Wave -> Intermission
		harness.runeManager.setGamePhase("Wave")
		harness.runeManager.setGamePhase("Intermission")

		-- Verify rune slot contents unchanged
		local slotAfter = harness.runeManager.getTurretRunes(turretId)
		if #slotAfter ~= #slotCopy then return false end
		for idx = 1, #slotCopy do
			if slotAfter[idx] ~= slotCopy[idx] then return false end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-system, Property 12: Rune Return Round Trip
-- After returnAllRunes, all turret slots are empty and each player's
-- inventory matches the total runes (inventory + turret runes) from before.
-- **Validates: Requirements 7.1, 7.2, 7.3**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePropertyTests.property12_RuneReturnRoundTrip(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RuneTestHarness.new()
		harness.runeManager.setGamePhase("Intermission")

		-- Set up multiple players with turrets
		local numPlayers = PropertyGen.int(1, 3)
		local playerData = {}

		for p = 1, numPlayers do
			local uid = p * 100000 + PropertyGen.int(1, 99999)
			harness.runeManager.initPlayer(uid)

			-- Give player random runes
			local inv = harness.runeManager.getInventory(uid)
			for t = 1, 10 do
				inv[t] = PropertyGen.int(0, 3)
			end

			-- Add a turret for this player
			local turretId = "turret_return_" .. tostring(_i) .. "_" .. tostring(p)
			local turretTypeId = PropertyGen.int(1, 6)
			harness.addMockTurret(turretId, turretTypeId, uid)

			-- Apply some runes to the turret
			local numApply = PropertyGen.int(0, 3)
			for _ = 1, numApply do
				local rTypeId = PropertyGen.runeTypeId()
				if (inv[rTypeId] or 0) > 0 then
					harness.runeManager.applyRune(uid, turretId, rTypeId)
				end
			end

			playerData[p] = { uid = uid, turretId = turretId }
		end

		-- Record total rune counts per player (inventory + turret runes)
		local totalsBefore = {}
		for _, pd in ipairs(playerData) do
			local totals = {}
			local inv = harness.runeManager.getInventory(pd.uid)
			for t = 1, 10 do
				totals[t] = (inv[t] or 0)
			end
			local turretRunes = harness.runeManager.getTurretRunes(pd.turretId)
			for _, rTypeId in ipairs(turretRunes) do
				totals[rTypeId] = (totals[rTypeId] or 0) + 1
			end
			totalsBefore[pd.uid] = totals
		end

		-- Call returnAllRunes
		harness.runeManager.returnAllRunes()

		-- Verify all turret rune slots are empty
		for _, pd in ipairs(playerData) do
			local turretRunes = harness.runeManager.getTurretRunes(pd.turretId)
			if #turretRunes ~= 0 then return false end
		end

		-- Verify each player's inventory matches the total from before
		for _, pd in ipairs(playerData) do
			local inv = harness.runeManager.getInventory(pd.uid)
			local expectedTotals = totalsBefore[pd.uid]
			for t = 1, 10 do
				if (inv[t] or 0) ~= (expectedTotals[t] or 0) then
					return false
				end
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Runner
-- ═══════════════════════════════════════════════════════════════════════════

function RunePropertyTests.runAll(): { { name: string, passed: boolean, failedAt: number? } }
	local tests = {
		{ name = "Property 1: Boss Drop Awards Exactly One Rune Per Player",  fn = RunePropertyTests.property1_BossDropAwardsExactlyOneRunePerPlayer },
		{ name = "Property 2: Inventory Non-Negative Invariant",              fn = RunePropertyTests.property2_InventoryNonNegativeInvariant },
		{ name = "Property 3: Ownership Validation",                          fn = RunePropertyTests.property3_OwnershipValidation },
		{ name = "Property 4: Empty Inventory Validation",                    fn = RunePropertyTests.property4_EmptyInventoryValidation },
		{ name = "Property 5: Phase Validation",                              fn = RunePropertyTests.property5_PhaseValidation },
		{ name = "Property 6: Valid Application Transfer",                    fn = RunePropertyTests.property6_ValidApplicationTransfer },
		{ name = "Property 7: Combination Table Completeness",                fn = RunePropertyTests.property7_CombinationTableCompleteness },
		{ name = "Property 8: Combined Multiplier Computation",               fn = RunePropertyTests.property8_CombinedMultiplierComputation },
		{ name = "Property 9: Synergy/Clash Direction",                       fn = RunePropertyTests.property9_SynergyClashDirection },
		{ name = "Property 10: Single-Rune Effects",                          fn = RunePropertyTests.property10_SingleRuneEffects },
		{ name = "Property 11: Rune Slot Persistence",                        fn = RunePropertyTests.property11_RuneSlotPersistence },
		{ name = "Property 12: Rune Return Round Trip",                       fn = RunePropertyTests.property12_RuneReturnRoundTrip },
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

	print(string.format("\n=== Results: %d/%d passed, %d failed ===", passCount, #tests, failCount))

	RunePropertyTests.results = results
	return results
end

return RunePropertyTests
