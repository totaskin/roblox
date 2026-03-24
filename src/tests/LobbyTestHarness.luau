-- LobbyTestHarness.luau
-- A test-friendly reimplementation of LobbyManager core logic.
-- Mirrors the real LobbyManager's state machine and validation rules
-- but removes all Roblox service dependencies (no Instance, no Workspace, etc.).
-- This allows property-based tests to exercise join/leave/launch/dismiss logic
-- directly with mock player tables.

local LobbyTestHarness = {}

export type MockPlayer = {
	UserId: number,
	Name: string,
	Character: any?,
}

export type AreaState = {
	index: number,
	status: "EMPTY" | "WAITING" | "IN_GAME" | "RESULTS",
	occupants: { MockPlayer },
	countdownRemaining: number,
	gameManager: any?,
	roundReached: number,
	dismissedPlayers: { [MockPlayer]: boolean },
}

export type LobbyInstance = {
	areas: { AreaState },
	broadcastCount: number,
	lastBroadcastSnapshots: { any }?,
	firedJoinResults: { { player: MockPlayer, success: boolean, reason: string? } },
	firedShowResults: { { player: MockPlayer, roundReached: number, areaIndex: number } },
	firedPlayerState: { { player: MockPlayer, snapshots: { any } } },
	lastGameManagerPlayers: { MockPlayer }?,
	lastGameManagerAreaId: number?,

	handleJoin: (player: MockPlayer, areaIndex: number) -> (),
	handleLeave: (player: MockPlayer, areaIndex: number) -> (),
	launchGame: (areaIndex: number) -> (),
	onGameOver: (areaIndex: number, roundReached: number) -> (),
	onPlayerDismissed: (player: MockPlayer, areaIndex: number) -> (),
	broadcastState: () -> (),
	getSnapshot: () -> { any },
	onPlayerAdded: (player: MockPlayer) -> (),
}

function LobbyTestHarness.new(): LobbyInstance
	local self = {} :: any

	-- Tracking tables for assertions
	self.broadcastCount = 0
	self.lastBroadcastSnapshots = nil
	self.firedJoinResults = {}
	self.firedShowResults = {}
	self.firedPlayerState = {}
	self.lastGameManagerPlayers = nil
	self.lastGameManagerAreaId = nil

	-- Initialise 3 areas
	self.areas = {} :: { AreaState }
	for i = 1, 3 do
		self.areas[i] = {
			index = i,
			status = "EMPTY",
			occupants = {},
			countdownRemaining = 0,
			gameManager = nil,
			roundReached = 0,
			dismissedPlayers = {},
		}
	end

	-- ── broadcastState ──────────────────────────────────────────────────
	function self.broadcastState()
		self.broadcastCount += 1
		self.lastBroadcastSnapshots = self.getSnapshot()
	end

	function self.getSnapshot(): { any }
		local snapshots = {}
		for _, area in ipairs(self.areas) do
			table.insert(snapshots, {
				index = area.index,
				status = area.status,
				occupantCount = #area.occupants,
				countdown = area.countdownRemaining,
			})
		end
		return snapshots
	end

	-- ── launchGame ──────────────────────────────────────────────────────
	function self.launchGame(areaIndex: number)
		local area = self.areas[areaIndex]
		if area.status ~= "WAITING" then return end

		area.status = "IN_GAME"

		-- Record which players were passed to GameManager
		local playersCopy = {}
		for _, p in ipairs(area.occupants) do
			table.insert(playersCopy, p)
		end
		self.lastGameManagerPlayers = playersCopy
		self.lastGameManagerAreaId = areaIndex

		-- Simulate creating a GameManager instance
		area.gameManager = { players = playersCopy, areaId = areaIndex }

		self.broadcastState()
	end

	-- ── onGameOver ──────────────────────────────────────────────────────
	function self.onGameOver(areaIndex: number, roundReached: number)
		local area = self.areas[areaIndex]
		area.status = "RESULTS"
		area.roundReached = roundReached

		for _, player in ipairs(area.occupants) do
			table.insert(self.firedShowResults, {
				player = player,
				roundReached = roundReached,
				areaIndex = areaIndex,
			})
		end

		self.broadcastState()
	end

	-- ── handleJoin ──────────────────────────────────────────────────────
	function self.handleJoin(player: any, areaIndex: number)
		local area = self.areas[areaIndex]

		-- Guard: in-game or results
		if area.status == "IN_GAME" or area.status == "RESULTS" then
			table.insert(self.firedJoinResults, {
				player = player,
				success = false,
				reason = "Game in progress",
			})
			return
		end

		-- Guard: area full
		if #area.occupants >= 2 then
			table.insert(self.firedJoinResults, {
				player = player,
				success = false,
				reason = "Area is full",
			})
			return
		end

		-- Guard: player already in any area
		for _, a in ipairs(self.areas) do
			for _, occ in ipairs(a.occupants) do
				if occ == player then
					return -- idempotent
				end
			end
		end

		-- Add player
		table.insert(area.occupants, player)
		table.insert(self.firedJoinResults, {
			player = player,
			success = true,
		})

		if #area.occupants == 1 then
			area.status = "WAITING"
			area.countdownRemaining = 10
		elseif #area.occupants == 2 then
			self.launchGame(areaIndex)
			return -- broadcastState called inside launchGame
		end

		self.broadcastState()
	end

	-- ── handleLeave ─────────────────────────────────────────────────────
	function self.handleLeave(player: any, areaIndex: number)
		local area = self.areas[areaIndex]

		local found = false
		for i, occ in ipairs(area.occupants) do
			if occ == player then
				table.remove(area.occupants, i)
				found = true
				break
			end
		end

		if not found then return end

		if area.status == "IN_GAME" or area.status == "RESULTS" then
			return
		end

		if #area.occupants == 0 and area.status == "WAITING" then
			area.status = "EMPTY"
			area.countdownRemaining = 0
		end

		self.broadcastState()
	end

	-- ── onPlayerDismissed ───────────────────────────────────────────────
	function self.onPlayerDismissed(player: any, areaIndex: number)
		local area = self.areas[areaIndex]
		area.dismissedPlayers[player] = true

		local allDismissed = true
		for _, occ in ipairs(area.occupants) do
			if not area.dismissedPlayers[occ] then
				allDismissed = false
				break
			end
		end

		if not allDismissed then return end

		-- Stop game manager
		if area.gameManager then
			area.gameManager = nil
		end

		-- Reset area
		area.status = "EMPTY"
		area.occupants = {}
		area.countdownRemaining = 0
		area.roundReached = 0
		area.dismissedPlayers = {}

		self.broadcastState()
	end

	-- ── onPlayerAdded (new player connects) ─────────────────────────────
	function self.onPlayerAdded(player: any)
		local snapshots = self.getSnapshot()
		table.insert(self.firedPlayerState, {
			player = player,
			snapshots = snapshots,
		})
		self.broadcastState()
	end

	return self
end

return LobbyTestHarness
