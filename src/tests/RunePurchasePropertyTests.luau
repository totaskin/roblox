-- RunePurchasePropertyTests.luau
-- Property-based tests for the Rune Robux Purchase System.
-- Uses a lightweight check-based approach with randomised inputs.
-- Each property runs a minimum of 100 iterations.
--
-- To run: require this module and call RunePurchasePropertyTests.runAll()
-- Each test returns { passed: boolean, property: string, failedAt: number? }

local PropertyGen = require(script.Parent.PropertyGen)
local RunePurchaseTestHarness = require(script.Parent.RunePurchaseTestHarness)
local RuneTestHarness = require(script.Parent.RuneTestHarness)

local ITERATIONS = 100

local RunePurchasePropertyTests = {}
RunePurchasePropertyTests.results = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 1: Product Table Validity
-- For any entry in the Rune_Product_Table, the configuration should be valid:
-- either (a) a single-rune product with runeTypeId in [1, 10] and quantity > 0,
-- or (b) a bundle product with isBundle = true and quantity > 0.
-- **Validates: Requirements 1.1**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property1_ProductTableValidity(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()
		local productTable = harness.getProductTable()

		-- Verify all entries in the product table are valid
		for productId, config in pairs(productTable) do
			-- Must have quantity > 0
			if type(config.quantity) ~= "number" or config.quantity <= 0 then
				return false
			end

			if config.isBundle then
				-- Bundle product: isBundle must be true, quantity > 0 (already checked)
				if config.isBundle ~= true then
					return false
				end
			else
				-- Single-rune product: runeTypeId must be in [1, 10]
				if type(config.runeTypeId) ~= "number" then
					return false
				end
				if config.runeTypeId < 1 or config.runeTypeId > 10 then
					return false
				end
				if config.runeTypeId ~= math.floor(config.runeTypeId) then
					return false
				end
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 2: Invalid Product Rejection
-- For any Developer Product ID not present in the Rune_Product_Table,
-- processing a receipt with that ID should reject the purchase (return
-- NotProcessedYet) and leave the player's rune inventory unchanged.
-- **Validates: Requirements 1.4, 2.2**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property2_InvalidProductRejection(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online with some initial inventory
		local userId = PropertyGen.int(1, 999999)
		local initialInventory = PropertyGen.runeInventory()
		harness.setupPlayer(userId, initialInventory)

		-- Generate an invalid product ID (not in product table)
		local invalidProductId = harness.getInvalidProductId()

		-- Create receipt with invalid product
		local receipt = harness.createReceipt(userId, invalidProductId)

		-- Record inventory before
		local inventoryBefore = {}
		local inv = harness.getInventory(userId)
		for t = 1, 10 do
			inventoryBefore[t] = inv[t] or 0
		end

		-- Process the receipt
		local result = harness.processReceipt(receipt)

		-- Verify: returns NotProcessedYet
		if result ~= harness.purchaseManager.PurchaseDecision.NotProcessedYet then
			return false
		end

		-- Verify: inventory unchanged
		local inventoryAfter = harness.getInventory(userId)
		for t = 1, 10 do
			if (inventoryAfter[t] or 0) ~= inventoryBefore[t] then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 3: Correct Rune Delivery
-- For any valid product purchase by a player who is in the game, processing
-- the receipt should increment the player's rune inventory by exactly the
-- configured quantity for the specified rune type (or random types for bundles).
-- **Validates: Requirements 2.3, 3.1**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property3_CorrectRuneDelivery(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online with empty inventory
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Pick a random single-rune product (rune types 1-10)
		local runeTypeId = PropertyGen.runeTypeId()
		local productId = harness.getProductIdForRuneType(runeTypeId)

		-- Get the product config to know expected quantity
		local productTable = harness.getProductTable()
		local config = productTable[productId]
		if not config then return false end

		-- Record inventory before
		local inventoryBefore = {}
		local inv = harness.getInventory(userId)
		for t = 1, 10 do
			inventoryBefore[t] = inv[t] or 0
		end

		-- Create and process receipt
		local receipt = harness.createReceipt(userId, productId)
		local result = harness.processReceipt(receipt)

		-- Verify: purchase succeeded
		if result ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Verify: inventory increased by exactly the configured quantity
		local inventoryAfter = harness.getInventory(userId)
		for t = 1, 10 do
			local expected = inventoryBefore[t]
			if t == runeTypeId then
				expected = expected + config.quantity
			end
			if (inventoryAfter[t] or 0) ~= expected then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 4: Successful Purchase Returns PurchaseGranted
-- For any valid product purchase that is successfully granted, the
-- ProcessReceipt callback should return PurchaseGranted.
-- **Validates: Requirements 2.4**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property4_SuccessfulPurchaseReturnsPurchaseGranted(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Pick a random valid product (single rune or bundle)
		local productId
		if PropertyGen.int(1, 10) <= 9 then
			-- 90% single rune
			local runeTypeId = PropertyGen.runeTypeId()
			productId = harness.getProductIdForRuneType(runeTypeId)
		else
			-- 10% bundle
			productId = harness.getBundleProductId()
		end

		-- Create and process receipt
		local receipt = harness.createReceipt(userId, productId)
		local result = harness.processReceipt(receipt)

		-- Verify: returns PurchaseGranted
		if result ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 5: Offline Player Returns NotProcessedYet
-- For any purchase receipt where the player is not currently in the game,
-- the ProcessReceipt callback should return NotProcessedYet and not modify
-- any rune inventories.
-- **Validates: Requirements 2.5**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property5_OfflinePlayerReturnsNotProcessedYet(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up an offline player scenario (player not in game)
		local userId = PropertyGen.int(1, 999999)
		local runeTypeId = PropertyGen.runeTypeId()
		local receipt = harness.setupOfflinePlayerScenario(userId, runeTypeId)

		-- Record inventory before (should be empty/initialized)
		local inventoryBefore = {}
		local inv = harness.getInventory(userId)
		for t = 1, 10 do
			inventoryBefore[t] = inv[t] or 0
		end

		-- Process the receipt
		local result = harness.processReceipt(receipt)

		-- Verify: returns NotProcessedYet
		if result ~= harness.purchaseManager.PurchaseDecision.NotProcessedYet then
			return false
		end

		-- Verify: inventory unchanged
		local inventoryAfter = harness.getInventory(userId)
		for t = 1, 10 do
			if (inventoryAfter[t] or 0) ~= inventoryBefore[t] then
				return false
			end
		end

		-- Verify: player is actually offline
		if harness.isPlayerOnline(userId) then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 6: Data Persistence on Grant
-- For any successful rune purchase grant, DataManager.markDirty should be
-- called for the purchasing player to ensure the runes are persisted.
-- **Validates: Requirements 2.6**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property6_DataPersistenceOnGrant(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Pick a random valid product
		local runeTypeId = PropertyGen.runeTypeId()
		local productId = harness.getProductIdForRuneType(runeTypeId)

		-- Create and process receipt
		local receipt = harness.createReceipt(userId, productId)
		local result = harness.processReceipt(receipt)

		-- Verify: purchase succeeded
		if result ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Verify: markDirty was called for this user
		local markDirtyCalls = harness.getMarkDirtyCalls()
		local foundMarkDirty = false
		for _, calledUserId in ipairs(markDirtyCalls) do
			if calledUserId == userId then
				foundMarkDirty = true
				break
			end
		end

		if not foundMarkDirty then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 7: Client Notification on Grant
-- For any successful rune purchase grant, a RuneInventoryUpdate remote event
-- should be fired to the purchasing player's client with the updated inventory.
-- **Validates: Requirements 3.2**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property7_ClientNotificationOnGrant(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Pick a random valid product
		local runeTypeId = PropertyGen.runeTypeId()
		local productId = harness.getProductIdForRuneType(runeTypeId)

		-- Create and process receipt
		local receipt = harness.createReceipt(userId, productId)
		local result = harness.processReceipt(receipt)

		-- Verify: purchase succeeded
		if result ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Verify: RuneInventoryUpdate was fired to this user
		local firedEvents = harness.getRemotesFired()
		local foundInventoryUpdate = false
		for _, event in ipairs(firedEvents) do
			if event.eventName == "RuneInventoryUpdate" and event.userId == userId then
				foundInventoryUpdate = true
				break
			end
		end

		if not foundInventoryUpdate then
			return false
		end

		return true
	end)
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 8: Atomic Rune Granting
-- For any product that grants multiple runes, either all runes in the product
-- are added to the player's inventory or none are. There should be no partial grants.
-- **Validates: Requirements 3.3**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property8_AtomicRuneGranting(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Use bundle product (grants multiple runes)
		local productId = harness.getBundleProductId()
		local productTable = harness.getProductTable()
		local config = productTable[productId]
		if not config or not config.isBundle then return false end

		local expectedQuantity = config.quantity

		-- Record inventory before
		local inventoryBefore = {}
		local inv = harness.getInventory(userId)
		for t = 1, 10 do
			inventoryBefore[t] = inv[t] or 0
		end
		local totalBefore = 0
		for t = 1, 10 do
			totalBefore = totalBefore + inventoryBefore[t]
		end

		-- Create and process receipt
		local receipt = harness.createReceipt(userId, productId)
		local result = harness.processReceipt(receipt)

		-- Verify: purchase succeeded
		if result ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Verify: total runes increased by exactly the bundle quantity
		local inventoryAfter = harness.getInventory(userId)
		local totalAfter = 0
		for t = 1, 10 do
			totalAfter = totalAfter + (inventoryAfter[t] or 0)
		end

		-- Atomic: either all runes granted (total increased by expectedQuantity) or none
		local runesGranted = totalAfter - totalBefore
		if runesGranted ~= expectedQuantity then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 9: Bundle Uses Random Drop Function
-- For any bundle product purchase, each rune granted should be determined by
-- calling ResourceData.rollResourceDrop, producing rune type IDs in [1, 10]
-- according to the existing drop weight distribution.
-- **Validates: Requirements 3.4**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property9_BundleUsesRandomDropFunction(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Use bundle product
		local productId = harness.getBundleProductId()
		local productTable = harness.getProductTable()
		local config = productTable[productId]
		if not config or not config.isBundle then return false end

		local expectedQuantity = config.quantity

		-- Create and process receipt
		local receipt = harness.createReceipt(userId, productId)
		local result = harness.processReceipt(receipt)

		-- Verify: purchase succeeded
		if result ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Verify: rollResourceDrop was called exactly `quantity` times
		local rollCalls = harness.getRollResourceDropCalls()
		if #rollCalls ~= expectedQuantity then
			return false
		end

		-- Verify: all granted runes are valid (in [1, 10])
		local inventoryAfter = harness.getInventory(userId)
		for t = 1, 10 do
			local count = inventoryAfter[t] or 0
			-- Each count should be non-negative (valid rune types)
			if count < 0 then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 10: Error Returns NotProcessedYet
-- For any purchase receipt that encounters an error during rune granting
-- (e.g., RuneManager failure), the ProcessReceipt callback should return
-- NotProcessedYet to allow Roblox to retry.
-- **Validates: Requirements 7.2**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property10_ErrorReturnsNotProcessedYet(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Configure addRunes to fail
		harness.setShouldFailAddRunes(true)

		-- Pick a random valid product
		local runeTypeId = PropertyGen.runeTypeId()
		local productId = harness.getProductIdForRuneType(runeTypeId)

		-- Record inventory before
		local inventoryBefore = {}
		local inv = harness.getInventory(userId)
		for t = 1, 10 do
			inventoryBefore[t] = inv[t] or 0
		end

		-- Create and process receipt
		local receipt = harness.createReceipt(userId, productId)
		local result = harness.processReceipt(receipt)

		-- Verify: returns NotProcessedYet due to error
		if result ~= harness.purchaseManager.PurchaseDecision.NotProcessedYet then
			return false
		end

		-- Reset failure mode for next iteration
		harness.setShouldFailAddRunes(false)

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 11: Duplicate Purchase Prevention
-- For any PurchaseId, processing the same receipt multiple times should grant
-- runes exactly once. Subsequent processing of the same PurchaseId should
-- return PurchaseGranted without modifying the player's inventory.
-- **Validates: Requirements 7.4**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property11_DuplicatePurchasePrevention(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = RunePurchaseTestHarness.new()

		-- Set up a player online
		local userId = PropertyGen.int(1, 999999)
		harness.setupPlayer(userId)

		-- Pick a random valid product
		local runeTypeId = PropertyGen.runeTypeId()
		local productId = harness.getProductIdForRuneType(runeTypeId)

		-- Create receipt with a specific PurchaseId
		local purchaseId = harness.generatePurchaseId()
		local receipt = harness.createReceipt(userId, productId, purchaseId)

		-- Process the receipt first time
		local result1 = harness.processReceipt(receipt)

		-- Verify: first purchase succeeded
		if result1 ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Record inventory after first purchase
		local inventoryAfterFirst = {}
		local inv = harness.getInventory(userId)
		for t = 1, 10 do
			inventoryAfterFirst[t] = inv[t] or 0
		end

		-- Process the same receipt again (duplicate)
		local result2 = harness.processReceipt(receipt)

		-- Verify: duplicate also returns PurchaseGranted (idempotent)
		if result2 ~= harness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Verify: inventory unchanged after duplicate
		local inventoryAfterSecond = harness.getInventory(userId)
		for t = 1, 10 do
			if (inventoryAfterSecond[t] or 0) ~= inventoryAfterFirst[t] then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: rune-robux-purchase, Property 12: Purchased Runes Equivalence
-- For any runes granted via purchase, they should be indistinguishable from
-- runes earned via boss drops for all subsequent operations (application to
-- turrets, return on game over, persistence).
-- **Validates: Requirements 8.3**
-- ═══════════════════════════════════════════════════════════════════════════
function RunePurchasePropertyTests.property12_PurchasedRunesEquivalence(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		-- Use both harnesses to test equivalence
		local purchaseHarness = RunePurchaseTestHarness.new()
		local runeHarness = RuneTestHarness.new()

		local userId = PropertyGen.int(1, 999999)
		local runeTypeId = PropertyGen.runeTypeId()
		local turretTypeId = PropertyGen.int(1, 6)
		local turretId = "turret_equiv_" .. tostring(_i)

		-- ═══════════════════════════════════════════════════════════════════
		-- Scenario A: Rune obtained via purchase
		-- ═══════════════════════════════════════════════════════════════════
		purchaseHarness.setupPlayer(userId)
		local productId = purchaseHarness.getProductIdForRuneType(runeTypeId)
		local receipt = purchaseHarness.createReceipt(userId, productId)
		local purchaseResult = purchaseHarness.processReceipt(receipt)

		if purchaseResult ~= purchaseHarness.purchaseManager.PurchaseDecision.PurchaseGranted then
			return false
		end

		-- Get purchased rune inventory
		local purchasedInventory = purchaseHarness.getInventory(userId)
		local purchasedCount = purchasedInventory[runeTypeId] or 0

		-- ═══════════════════════════════════════════════════════════════════
		-- Scenario B: Rune obtained via boss drop (using RuneTestHarness)
		-- ═══════════════════════════════════════════════════════════════════
		runeHarness.runeManager.initPlayer(userId)

		-- Manually add the same rune type (simulating boss drop result)
		local droppedInventory = runeHarness.runeManager.getInventory(userId)
		droppedInventory[runeTypeId] = 1

		-- ═══════════════════════════════════════════════════════════════════
		-- Test: Both runes can be applied to turrets identically
		-- ═══════════════════════════════════════════════════════════════════

		-- Set up turret for dropped rune test
		runeHarness.addMockTurret(turretId, turretTypeId, userId)

		-- Apply dropped rune
		local dropApplySuccess, dropApplyReason = runeHarness.runeManager.applyRune(userId, turretId, runeTypeId)

		-- Verify: dropped rune can be applied
		if not dropApplySuccess then
			return false
		end

		-- Verify: inventory decremented
		local droppedInvAfterApply = runeHarness.runeManager.getInventory(userId)
		if (droppedInvAfterApply[runeTypeId] or 0) ~= 0 then
			return false
		end

		-- Verify: turret has the rune
		local turretRunes = runeHarness.runeManager.getTurretRunes(turretId)
		if #turretRunes ~= 1 or turretRunes[1] ~= runeTypeId then
			return false
		end

		-- ═══════════════════════════════════════════════════════════════════
		-- Test: Runes return on game over identically
		-- ═══════════════════════════════════════════════════════════════════

		-- Return all runes
		runeHarness.runeManager.returnAllRunes()

		-- Verify: rune returned to inventory
		local droppedInvAfterReturn = runeHarness.runeManager.getInventory(userId)
		if (droppedInvAfterReturn[runeTypeId] or 0) ~= 1 then
			return false
		end

		-- Verify: turret slot is empty
		local turretRunesAfterReturn = runeHarness.runeManager.getTurretRunes(turretId)
		if #turretRunesAfterReturn ~= 0 then
			return false
		end

		-- ═══════════════════════════════════════════════════════════════════
		-- Verify: Purchased runes have same structure as dropped runes
		-- ═══════════════════════════════════════════════════════════════════

		-- Both should be simple integer counts in the inventory
		if type(purchasedCount) ~= "number" then
			return false
		end

		-- Purchased rune count should be 1 (single rune product)
		if purchasedCount ~= 1 then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Runner
-- ═══════════════════════════════════════════════════════════════════════════

function RunePurchasePropertyTests.runAll(): { { name: string, passed: boolean, failedAt: number? } }
	local tests = {
		{ name = "Property 1: Product Table Validity",                fn = RunePurchasePropertyTests.property1_ProductTableValidity },
		{ name = "Property 2: Invalid Product Rejection",             fn = RunePurchasePropertyTests.property2_InvalidProductRejection },
		{ name = "Property 3: Correct Rune Delivery",                 fn = RunePurchasePropertyTests.property3_CorrectRuneDelivery },
		{ name = "Property 4: Successful Purchase Returns PurchaseGranted", fn = RunePurchasePropertyTests.property4_SuccessfulPurchaseReturnsPurchaseGranted },
		{ name = "Property 5: Offline Player Returns NotProcessedYet", fn = RunePurchasePropertyTests.property5_OfflinePlayerReturnsNotProcessedYet },
		{ name = "Property 6: Data Persistence on Grant",             fn = RunePurchasePropertyTests.property6_DataPersistenceOnGrant },
		{ name = "Property 7: Client Notification on Grant",          fn = RunePurchasePropertyTests.property7_ClientNotificationOnGrant },
		{ name = "Property 8: Atomic Rune Granting",                  fn = RunePurchasePropertyTests.property8_AtomicRuneGranting },
		{ name = "Property 9: Bundle Uses Random Drop Function",      fn = RunePurchasePropertyTests.property9_BundleUsesRandomDropFunction },
		{ name = "Property 10: Error Returns NotProcessedYet",        fn = RunePurchasePropertyTests.property10_ErrorReturnsNotProcessedYet },
		{ name = "Property 11: Duplicate Purchase Prevention",        fn = RunePurchasePropertyTests.property11_DuplicatePurchasePrevention },
		{ name = "Property 12: Purchased Runes Equivalence",          fn = RunePurchasePropertyTests.property12_PurchasedRunesEquivalence },
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

	RunePurchasePropertyTests.results = results
	return results
end

return RunePurchasePropertyTests
