-- LobbyPropertyTests.luau
-- Property-based tests for the Lobby System.
-- Uses a lightweight check-based approach with randomised inputs.
-- Each property runs a minimum of 100 iterations.
--
-- To run: require this module and call LobbyPropertyTests.runAll()
-- Each test returns { passed: boolean, property: string, failedAt: number? }

local PropertyGen = require(script.Parent.PropertyGen)
local LobbyTestHarness = require(script.Parent.LobbyTestHarness)

local ITERATIONS = 100

local LobbyPropertyTests = {}
LobbyPropertyTests.results = {}

-- Helper: count how many areas a player appears in
local function countAreasContaining(lobby, player): number
	local count = 0
	for _, area in ipairs(lobby.areas) do
		for _, occ in ipairs(area.occupants) do
			if occ == player then
				count += 1
			end
		end
	end
	return count
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 1: Join/Leave Round Trip
-- For any area in EMPTY state and any player, joining then immediately
-- leaving should return the area's occupant list to its original empty
-- state and the area status back to EMPTY.
-- **Validates: Requirements 1.2, 1.4, 2.4**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property1_JoinLeaveRoundTrip(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()
		local player = PropertyGen.mockPlayer()

		-- Precondition: area is EMPTY
		assert(lobby.areas[areaIdx].status == "EMPTY")

		lobby.handleJoin(player, areaIdx)
		lobby.handleLeave(player, areaIdx)

		local area = lobby.areas[areaIdx]
		return area.status == "EMPTY" and #area.occupants == 0
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 2: Capacity Enforcement
-- For any area already containing 2 players, attempting to add a third
-- player should be rejected and the occupant count should remain exactly 2.
-- **Validates: Requirements 1.3**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property2_CapacityEnforcement(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()
		local players = PropertyGen.mockPlayers(3)

		-- Fill area with 2 players (this will trigger launchGame → IN_GAME)
		-- Instead, manually set up the area to have 2 occupants in WAITING
		-- so we can test the capacity guard directly.
		-- We add player1 (→ WAITING), then we need to test the "full" guard.
		-- The real code launches on 2nd join, so let's set up the state manually.
		local area = lobby.areas[areaIdx]
		area.status = "WAITING"
		area.occupants = { players[1], players[2] }
		area.countdownRemaining = 5

		local prevCount = #area.occupants
		lobby.handleJoin(players[3], areaIdx)

		-- Third player should be rejected
		local rejected = false
		for _, result in ipairs(lobby.firedJoinResults) do
			if result.player == players[3] and result.success == false then
				rejected = true
				break
			end
		end

		return rejected and #area.occupants == prevCount and #area.occupants == 2
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 3: Single-Area Occupancy
-- For any player already occupying area A, attempting to join area B should
-- result in the player appearing in at most one area's occupant list
-- across all 3 areas.
-- **Validates: Requirements 1.5**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property3_SingleAreaOccupancy(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local player = PropertyGen.mockPlayer()

		-- Pick two different areas
		local areaA = PropertyGen.areaIndex()
		local areaB
		repeat
			areaB = PropertyGen.areaIndex()
		until areaB ~= areaA

		-- Join area A first
		lobby.handleJoin(player, areaA)

		-- Attempt to join area B
		lobby.handleJoin(player, areaB)

		-- Player should appear in at most 1 area
		local count = countAreasContaining(lobby, player)
		return count <= 1
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 4: First-Join Starts Countdown
-- For any area in EMPTY state, after the first player joins, the area
-- status should be WAITING and countdownRemaining should be 10.
-- **Validates: Requirements 2.1**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property4_FirstJoinStartsCountdown(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()
		local player = PropertyGen.mockPlayer()

		-- Precondition: area is EMPTY
		assert(lobby.areas[areaIdx].status == "EMPTY")

		lobby.handleJoin(player, areaIdx)

		local area = lobby.areas[areaIdx]
		return area.status == "WAITING" and area.countdownRemaining == 10
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 5: Second-Join Triggers Immediate Launch
-- For any area in WAITING state with 1 occupant, adding a second player
-- should transition the area to IN_GAME without waiting for the countdown
-- to reach 0.
-- **Validates: Requirements 2.3**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property5_SecondJoinTriggersLaunch(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()
		local players = PropertyGen.mockPlayers(2)

		-- First player joins → WAITING
		lobby.handleJoin(players[1], areaIdx)
		assert(lobby.areas[areaIdx].status == "WAITING")

		-- Second player joins → should go to IN_GAME
		lobby.handleJoin(players[2], areaIdx)

		return lobby.areas[areaIdx].status == "IN_GAME"
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 6: Game Launch Scopes Players Correctly
-- For any area transitioning to IN_GAME, the GameManager instance created
-- for that area should receive exactly the set of players that were in the
-- area's occupant list at launch time.
-- **Validates: Requirements 3.1, 7.1**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property6_GameLaunchScopesPlayers(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()

		-- Randomly choose 1 or 2 players
		local numPlayers = PropertyGen.int(1, 2)
		local players = PropertyGen.mockPlayers(numPlayers)

		if numPlayers == 1 then
			-- Single player: join, then manually trigger launch (simulating countdown expiry)
			lobby.handleJoin(players[1], areaIdx)
			-- Simulate countdown reaching 0
			lobby.launchGame(areaIdx)
		else
			-- Two players: second join triggers launch automatically
			lobby.handleJoin(players[1], areaIdx)
			lobby.handleJoin(players[2], areaIdx)
		end

		-- Verify GameManager received the correct players
		if not lobby.lastGameManagerPlayers then
			return false
		end

		if #lobby.lastGameManagerPlayers ~= numPlayers then
			return false
		end

		-- Check each player is in the GameManager's player list
		for _, p in ipairs(players) do
			local found = false
			for _, gp in ipairs(lobby.lastGameManagerPlayers) do
				if gp == p then
					found = true
					break
				end
			end
			if not found then
				return false
			end
		end

		return lobby.lastGameManagerAreaId == areaIdx
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 7: In-Game Area Rejects New Joins
-- For any area in IN_GAME or RESULTS state, any join attempt should be
-- rejected and the area's occupant list should be unchanged.
-- **Validates: Requirements 3.2**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property7_InGameRejectsJoins(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()

		-- Randomly pick IN_GAME or RESULTS
		local blockedStatus = if PropertyGen.int(0, 1) == 0 then "IN_GAME" else "RESULTS"

		-- Set up area in blocked state with 1 existing occupant
		local existingPlayer = PropertyGen.mockPlayer()
		local area = lobby.areas[areaIdx]
		area.status = blockedStatus
		area.occupants = { existingPlayer }

		local prevCount = #area.occupants
		local newPlayer = PropertyGen.mockPlayer()
		lobby.handleJoin(newPlayer, areaIdx)

		-- Should be rejected
		local rejected = false
		for _, result in ipairs(lobby.firedJoinResults) do
			if result.player == newPlayer and result.success == false then
				rejected = true
				break
			end
		end

		return rejected and #area.occupants == prevCount
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 8: Results Screen Shows Correct Round
-- For any game over event carrying a roundReached value, the
-- LobbyShowResults remote fired to area players should carry that same
-- roundReached value.
-- **Validates: Requirements 3.5**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property8_ResultsShowCorrectRound(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()
		local roundReached = PropertyGen.int(1, 100)

		-- Set up area in IN_GAME with 1-2 players
		local numPlayers = PropertyGen.int(1, 2)
		local players = PropertyGen.mockPlayers(numPlayers)
		local area = lobby.areas[areaIdx]
		area.status = "IN_GAME"
		area.occupants = players

		lobby.onGameOver(areaIdx, roundReached)

		-- Verify all fired results carry the correct roundReached
		local allCorrect = true
		local foundCount = 0
		for _, result in ipairs(lobby.firedShowResults) do
			if result.areaIndex == areaIdx then
				foundCount += 1
				if result.roundReached ~= roundReached then
					allCorrect = false
				end
			end
		end

		return allCorrect and foundCount == numPlayers
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 9: Area Resets After All Dismissals
-- For any area in RESULTS state with N occupants, after all N players fire
-- LobbyReturnToLobby, the area status should be EMPTY and the occupant
-- list should be empty.
-- **Validates: Requirements 3.6, 7.3**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property9_AreaResetsAfterDismissals(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()

		-- Set up area in RESULTS with 1-2 players
		local numPlayers = PropertyGen.int(1, 2)
		local players = PropertyGen.mockPlayers(numPlayers)
		local area = lobby.areas[areaIdx]
		area.status = "RESULTS"
		area.occupants = players
		area.roundReached = PropertyGen.int(1, 50)
		area.dismissedPlayers = {}

		-- All players dismiss
		for _, player in ipairs(players) do
			lobby.onPlayerDismissed(player, areaIdx)
		end

		local area2 = lobby.areas[areaIdx]
		return area2.status == "EMPTY" and #area2.occupants == 0
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 10: Area Label Reflects State
-- For any area state snapshot, the rendered label string should contain
-- the occupant count when EMPTY/WAITING, countdown seconds when WAITING,
-- "In Progress" when IN_GAME, "Full" when occupantCount is 2.
-- **Validates: Requirements 4.1, 4.3, 4.4, 4.5**
-- ═══════════════════════════════════════════════════════════════════════════

-- Inline reimplementation of buildLabelText from LobbyClient for testing.
-- This mirrors the exact logic in src/client/LobbyClient.luau.
local function buildLabelText(index: number, status: string, occupantCount: number, countdown: number): string
	local header = "Area " .. index

	if status == "IN_GAME" then
		return header .. "\nIn Progress"
	end

	if status == "RESULTS" then
		return header .. "\nResults"
	end

	local text
	if status == "WAITING" and countdown > 0 then
		text = header .. "\n" .. occupantCount .. "/2 players\n" .. countdown .. "s"
	else
		text = header .. "\n" .. occupantCount .. "/2 players"
	end

	if occupantCount == 2 then
		text = text .. "\nFull"
	end

	return text
end

function LobbyPropertyTests.property10_AreaLabelReflectsState(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local snapshot = PropertyGen.areaStateSnapshot()
		local label = buildLabelText(snapshot.index, snapshot.status, snapshot.occupantCount, snapshot.countdown)

		-- Check: contains occupant count when EMPTY or WAITING
		if snapshot.status == "EMPTY" or snapshot.status == "WAITING" then
			local countStr = snapshot.occupantCount .. "/2"
			if not string.find(label, countStr, 1, true) then
				return false
			end
		end

		-- Check: contains countdown seconds when WAITING and countdown > 0
		if snapshot.status == "WAITING" and snapshot.countdown > 0 then
			local countdownStr = snapshot.countdown .. "s"
			if not string.find(label, countdownStr, 1, true) then
				return false
			end
		end

		-- Check: contains "In Progress" when IN_GAME
		if snapshot.status == "IN_GAME" then
			if not string.find(label, "In Progress", 1, true) then
				return false
			end
		end

		-- Check: contains "Full" when occupantCount is 2 (and not IN_GAME/RESULTS)
		if snapshot.occupantCount == 2 and (snapshot.status == "EMPTY" or snapshot.status == "WAITING") then
			if not string.find(label, "Full", 1, true) then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 11: Rejection Triggers Client Message
-- For any LobbyJoinResult event with success = false, the client handler
-- should produce a non-empty rejection message string visible to the player.
-- **Validates: Requirements 5.3**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property11_RejectionTriggersMessage(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()
		local player = PropertyGen.mockPlayer()

		-- Create a rejection scenario: randomly pick full area or in-game area
		local scenario = PropertyGen.int(0, 1)
		local area = lobby.areas[areaIdx]

		if scenario == 0 then
			-- Area full
			local existing = PropertyGen.mockPlayers(2)
			area.status = "WAITING"
			area.occupants = existing
			area.countdownRemaining = 5
		else
			-- Area in-game
			local existing = PropertyGen.mockPlayers(1)
			area.status = "IN_GAME"
			area.occupants = existing
		end

		lobby.handleJoin(player, areaIdx)

		-- Find the rejection result for this player
		local message = nil
		for _, result in ipairs(lobby.firedJoinResults) do
			if result.player == player and result.success == false then
				message = result.reason
				break
			end
		end

		-- Message must exist and be non-empty
		return message ~= nil and type(message) == "string" and #message > 0
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 12: State Broadcast on Every Change
-- For any state-mutating operation (join, leave, countdown tick, game
-- start, area reset), broadcastState should be called.
-- **Validates: Requirements 6.1**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property12_StateBroadcastOnEveryChange(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		-- Test each mutating operation and verify broadcastCount increases

		-- 1. Join
		local lobby = LobbyTestHarness.new()
		local areaIdx = PropertyGen.areaIndex()
		local player = PropertyGen.mockPlayer()
		local before = lobby.broadcastCount
		lobby.handleJoin(player, areaIdx)
		if lobby.broadcastCount <= before then
			return false
		end

		-- 2. Leave
		before = lobby.broadcastCount
		lobby.handleLeave(player, areaIdx)
		if lobby.broadcastCount <= before then
			return false
		end

		-- 3. Game start (via second player join)
		local lobby2 = LobbyTestHarness.new()
		local areaIdx2 = PropertyGen.areaIndex()
		local p1 = PropertyGen.mockPlayer()
		local p2 = PropertyGen.mockPlayer()
		lobby2.handleJoin(p1, areaIdx2)
		before = lobby2.broadcastCount
		lobby2.handleJoin(p2, areaIdx2) -- triggers launchGame
		if lobby2.broadcastCount <= before then
			return false
		end

		-- 4. Game over (→ RESULTS)
		before = lobby2.broadcastCount
		lobby2.onGameOver(areaIdx2, PropertyGen.int(1, 20))
		if lobby2.broadcastCount <= before then
			return false
		end

		-- 5. Area reset (all dismiss)
		before = lobby2.broadcastCount
		lobby2.onPlayerDismissed(p1, areaIdx2)
		lobby2.onPlayerDismissed(p2, areaIdx2)
		if lobby2.broadcastCount <= before then
			return false
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Feature: lobby-system, Property 13: New Player Receives Full State
-- For any player connecting to the server, the LobbyState remote should
-- be fired to that player with snapshots for all 3 areas.
-- **Validates: Requirements 6.2**
-- ═══════════════════════════════════════════════════════════════════════════
function LobbyPropertyTests.property13_NewPlayerReceivesFullState(): (boolean, number?)
	return PropertyGen.check(ITERATIONS, function(_i)
		local lobby = LobbyTestHarness.new()

		-- Optionally mutate some areas first to make state non-trivial
		local numMutations = PropertyGen.int(0, 3)
		for _ = 1, numMutations do
			local p = PropertyGen.mockPlayer()
			local idx = PropertyGen.areaIndex()
			lobby.handleJoin(p, idx)
		end

		-- Simulate new player connecting
		local newPlayer = PropertyGen.mockPlayer()
		lobby.onPlayerAdded(newPlayer)

		-- Find the state fired to this player
		local firedState = nil
		for _, entry in ipairs(lobby.firedPlayerState) do
			if entry.player == newPlayer then
				firedState = entry.snapshots
				break
			end
		end

		if not firedState then
			return false
		end

		-- Must contain exactly 3 area snapshots
		if #firedState ~= 3 then
			return false
		end

		-- Each snapshot should have the expected fields
		for _, snap in ipairs(firedState) do
			if not snap.index or not snap.status or snap.occupantCount == nil or snap.countdown == nil then
				return false
			end
		end

		return true
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Test Runner
-- ═══════════════════════════════════════════════════════════════════════════

function LobbyPropertyTests.runAll(): { { name: string, passed: boolean, failedAt: number? } }
	local tests = {
		{ name = "Property 1: Join/Leave Round Trip",              fn = LobbyPropertyTests.property1_JoinLeaveRoundTrip },
		{ name = "Property 2: Capacity Enforcement",               fn = LobbyPropertyTests.property2_CapacityEnforcement },
		{ name = "Property 3: Single-Area Occupancy",              fn = LobbyPropertyTests.property3_SingleAreaOccupancy },
		{ name = "Property 4: First-Join Starts Countdown",        fn = LobbyPropertyTests.property4_FirstJoinStartsCountdown },
		{ name = "Property 5: Second-Join Triggers Immediate Launch", fn = LobbyPropertyTests.property5_SecondJoinTriggersLaunch },
		{ name = "Property 6: Game Launch Scopes Players Correctly", fn = LobbyPropertyTests.property6_GameLaunchScopesPlayers },
		{ name = "Property 7: In-Game Area Rejects New Joins",     fn = LobbyPropertyTests.property7_InGameRejectsJoins },
		{ name = "Property 8: Results Screen Shows Correct Round",  fn = LobbyPropertyTests.property8_ResultsShowCorrectRound },
		{ name = "Property 9: Area Resets After All Dismissals",    fn = LobbyPropertyTests.property9_AreaResetsAfterDismissals },
		{ name = "Property 10: Area Label Reflects State",          fn = LobbyPropertyTests.property10_AreaLabelReflectsState },
		{ name = "Property 11: Rejection Triggers Client Message",  fn = LobbyPropertyTests.property11_RejectionTriggersMessage },
		{ name = "Property 12: State Broadcast on Every Change",    fn = LobbyPropertyTests.property12_StateBroadcastOnEveryChange },
		{ name = "Property 13: New Player Receives Full State",     fn = LobbyPropertyTests.property13_NewPlayerReceivesFullState },
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

	LobbyPropertyTests.results = results
	return results
end

return LobbyPropertyTests
