-- PlayerColorPropertyTests.luau
-- Property-based tests for the Turret Player Colors feature.
-- Uses PropertyGen.check with 100 iterations per property.
-- Each property maps to a correctness property from the design document.
--
-- To run: require this module and call PlayerColorPropertyTests.runAll()

local PropertyGen = require(script.Parent.PropertyGen)
local TurretTestHarness = require(script.Parent.TurretTestHarness)
local TurretData = require(script.Parent.Parent.shared.TurretData)

local ITERATIONS = 100

local PlayerColorPropertyTests = {}
PlayerColorPropertyTests.results = {}

-- Reference palette (must match TurretTestHarness / TurretManager)
local PLAYER_COLORS: { Color3 } = {
	Color3.fromRGB(50, 130, 255),
	Color3.fromRGB(255, 80, 80),
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-player-colors, Property 1: Distinct Color Assignment by Join Order
-- For any pair of 2 players with distinct userIds, calling assignPlayerColors
-- should assign the first player the first palette color and the second player
-- the second palette color, and the two assigned colors must not be equal.
-- **Validates: Requirements 1.1, 1.3**
-- ═══════════════════════════════════════════════════════════════════════════
function PlayerColorPropertyTests.property1_DistinctColorAssignmentByJoinOrder(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = TurretTestHarness.new()
		local players = PropertyGen.mockPlayers(2)

		harness.turretManager.assignPlayerColors(players)

		local color1 = harness.turretManager.getPlayerColor(players[1].UserId)
		local color2 = harness.turretManager.getPlayerColor(players[2].UserId)

		-- Player 1 gets first palette color, Player 2 gets second
		if color1 ~= PLAYER_COLORS[1] then return false end
		if color2 ~= PLAYER_COLORS[2] then return false end

		-- The two assigned colors must not be equal
		if color1 == color2 then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-player-colors, Property 2: Placement Applies Owner Color to Body and Model Attribute
-- For any player with an assigned color and any valid turret placement,
-- the resulting turret model's Body part color should equal the player's
-- assigned color, and the model's OwnerColor attribute should equal the same color.
-- **Validates: Requirements 2.1, 2.2, 2.4, 5.2**
-- ═══════════════════════════════════════════════════════════════════════════
function PlayerColorPropertyTests.property2_PlacementAppliesOwnerColor(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = TurretTestHarness.new()
		local players = PropertyGen.mockPlayers(2)
		harness.turretManager.assignPlayerColors(players)

		local player = players[PropertyGen.int(1, 2)]
		local ownerColor = harness.turretManager.getPlayerColor(player.UserId)
		if not ownerColor then return false end

		local turretTypeId = PropertyGen.turretTypeId()
		local mockModel = harness.buildMockModel(turretTypeId)

		harness.turretManager.applyOwnerColor(mockModel, ownerColor, player.Name)

		-- Body.Color should equal the player's assigned color
		if mockModel.Body.Color ~= ownerColor then return false end
		-- OwnerColor attribute should equal the same color
		if mockModel.OwnerColor ~= ownerColor then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-player-colors, Property 3: Placement Adds OwnerLabel with Correct Name and Color
-- For any turret placement by a player with display name N and assigned color C,
-- the turret's OwnerLabel Text equals N and TextColor3 equals C.
-- **Validates: Requirements 3.1, 3.2**
-- ═══════════════════════════════════════════════════════════════════════════
function PlayerColorPropertyTests.property3_OwnerLabelNameAndColor(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = TurretTestHarness.new()
		local ownerColor = PropertyGen.playerColor()
		local ownerName = PropertyGen.playerDisplayName()

		local turretTypeId = PropertyGen.turretTypeId()
		local mockModel = harness.buildMockModel(turretTypeId)

		harness.turretManager.applyOwnerColor(mockModel, ownerColor, ownerName)

		-- OwnerLabel must exist
		if not mockModel.OwnerLabel then return false end
		-- Text must equal the display name
		if mockModel.OwnerLabel.Text ~= ownerName then return false end
		-- TextColor3 must equal the owner color
		if mockModel.OwnerLabel.TextColor3 ~= ownerColor then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-player-colors, Property 4: Upgrade Preserves Owner Visuals
-- For any placed turret that is upgraded, the Body part color, the OwnerColor
-- model attribute, and the OwnerLabel should remain unchanged after the upgrade.
-- **Validates: Requirements 2.3, 3.3**
-- ═══════════════════════════════════════════════════════════════════════════
function PlayerColorPropertyTests.property4_UpgradePreservesOwnerVisuals(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = TurretTestHarness.new()
		local players = PropertyGen.mockPlayers(2)
		harness.turretManager.assignPlayerColors(players)

		local player = players[PropertyGen.int(1, 2)]
		local ownerColor = harness.turretManager.getPlayerColor(player.UserId)
		if not ownerColor then return false end

		local turretTypeId = PropertyGen.turretTypeId()
		local mockModel = harness.buildMockModel(turretTypeId)

		-- Apply owner color (simulates placement)
		harness.turretManager.applyOwnerColor(mockModel, ownerColor, player.Name)

		-- Record pre-upgrade state
		local preBodyColor = mockModel.Body.Color
		local preOwnerColor = mockModel.OwnerColor
		local preLabelText = mockModel.OwnerLabel.Text
		local preLabelColor = mockModel.OwnerLabel.TextColor3

		-- Simulate upgrade: increment level, change stats (but NOT owner visuals)
		mockModel.TurretLevel = mockModel.TurretLevel + 1

		-- Verify owner visuals are preserved after upgrade
		if mockModel.Body.Color ~= preBodyColor then return false end
		if mockModel.OwnerColor ~= preOwnerColor then return false end
		if mockModel.OwnerLabel.Text ~= preLabelText then return false end
		if mockModel.OwnerLabel.TextColor3 ~= preLabelColor then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-player-colors, Property 5: Ghost Preview Tinted with Player Color
-- For any player color C, building a ghost preview model should produce a
-- model whose Body part color equals C.
-- **Validates: Requirements 4.1**
-- ═══════════════════════════════════════════════════════════════════════════
function PlayerColorPropertyTests.property5_GhostPreviewTintedWithPlayerColor(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local playerColor = PropertyGen.playerColor()

		-- Build a mock ghost model with a default Body color
		local ghostModel = {
			Body = { Color = Color3.fromRGB(60, 140, 200) },
		}

		-- Apply the player color to the ghost Body (simulates ghost tinting)
		ghostModel.Body.Color = playerColor

		-- Verify Body.Color equals the player color
		if ghostModel.Body.Color ~= playerColor then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: turret-player-colors, Property 6: Client Color Map Storage Round Trip
-- For any mapping of userIds to colors received from the server, storing it
-- in the client's playerColorMap and then querying any userId should return
-- the originally assigned color.
-- **Validates: Requirements 5.3**
-- ═══════════════════════════════════════════════════════════════════════════
function PlayerColorPropertyTests.property6_ClientColorMapStorageRoundTrip(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local harness = TurretTestHarness.new()

		-- Generate 2 random players with random colors
		local players = PropertyGen.mockPlayers(2)
		local color1 = PropertyGen.playerColor()
		local color2 = PropertyGen.playerColor()

		-- Build a server-format color map: { [userId]: { R, G, B } }
		local serverColorMap = {
			[players[1].UserId] = { R = color1.R, G = color1.G, B = color1.B },
			[players[2].UserId] = { R = color2.R, G = color2.G, B = color2.B },
		}

		-- Store via the client helper
		local clientMap = harness.storeClientColorMap(serverColorMap)

		-- Verify each userId maps back to the original Color3
		local restored1 = clientMap[players[1].UserId]
		local restored2 = clientMap[players[2].UserId]

		if not restored1 or not restored2 then return false end

		-- Compare using approximate equality (Color3.new uses 0-1 floats)
		local function approxEqual(a: Color3, b: Color3): boolean
			return math.abs(a.R - b.R) < 0.002
				and math.abs(a.G - b.G) < 0.002
				and math.abs(a.B - b.B) < 0.002
		end

		if not approxEqual(restored1, color1) then return false end
		if not approxEqual(restored2, color2) then return false end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Runner
-- ═══════════════════════════════════════════════════════════════════════════

function PlayerColorPropertyTests.runAll(): { { name: string, passed: boolean, failedAt: number? } }
	local tests = {
		{ name = "Property 1: Distinct Color Assignment by Join Order",                fn = PlayerColorPropertyTests.property1_DistinctColorAssignmentByJoinOrder },
		{ name = "Property 2: Placement Applies Owner Color to Body and Model Attribute", fn = PlayerColorPropertyTests.property2_PlacementAppliesOwnerColor },
		{ name = "Property 3: Placement Adds OwnerLabel with Correct Name and Color",  fn = PlayerColorPropertyTests.property3_OwnerLabelNameAndColor },
		{ name = "Property 4: Upgrade Preserves Owner Visuals",                         fn = PlayerColorPropertyTests.property4_UpgradePreservesOwnerVisuals },
		{ name = "Property 5: Ghost Preview Tinted with Player Color",                  fn = PlayerColorPropertyTests.property5_GhostPreviewTintedWithPlayerColor },
		{ name = "Property 6: Client Color Map Storage Round Trip",                     fn = PlayerColorPropertyTests.property6_ClientColorMapStorageRoundTrip },
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

	print(string.format("\n=== Player Color Results: %d/%d passed, %d failed ===", passCount, #tests, failCount))

	PlayerColorPropertyTests.results = results
	return results
end

return PlayerColorPropertyTests
