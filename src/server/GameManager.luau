-- GameManager.luau
-- Central state machine: lobby → wave → intermission → wave → ...
-- Coordinates all other server managers

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaveData       = require(game.ReplicatedStorage.Shared.WaveData)
local EnemyPath      = require(game.ReplicatedStorage.Shared.EnemyPath)
local EnemyManager   = require(script.Parent.EnemyManager)
local TowerManager   = require(script.Parent.TowerManager)
local ResourceManager= require(script.Parent.ResourceManager)
local EconomyManager = require(script.Parent.EconomyManager)
local TurretManager  = require(script.Parent.TurretManager)
local GamepassManager = require(script.Parent.GamepassManager)
local RuneManager    = require(script.Parent.RuneManager)
local MapBuilder     = require(script.Parent.MapBuilder)

local GameManager = {}

-- Game state enum (shared, not per-instance)
local State = {
	LOBBY        = "Lobby",
	INTERMISSION = "Intermission",
	WAVE         = "Wave",
	GAME_OVER    = "GameOver",
}

-- ---------------------------------------------------------------------------
-- createInstance: encapsulates all per-game state and logic.
-- Each call returns an isolated instance table.
-- ---------------------------------------------------------------------------
local function createInstance(players: { Player }?, areaId: number?, loadouts: { [number]: { number } }?)
	-- Set player loadouts for turret system
	if loadouts then
		TurretManager.setPlayerLoadouts(loadouts)
	end

	-- Per-instance state variables
	local self = {
		players              = players,
		areaId               = areaId,
		currentState         = State.LOBBY,
		currentRound         = 0,
		baseHealth           = 20,
		spawnQueue           = {} :: { { enemyType: string, count: number, interval: number } },
		spawnIndex           = 1,
		spawnTimer           = 0,
		enemiesAlive         = 0,
		intermissionTime     = 15,
		intermissionRemaining = 0,
		gameSpeed            = 1,
		Remotes              = nil :: Folder?,
	}

	-- Per-instance private state for lifecycle management
	local _heartbeatConnection: RBXScriptConnection? = nil
	local _gameOverCallback: ((roundReached: number) -> ())?  = nil

	-- ------------------------------------------------------------------
	-- Helpers
	-- ------------------------------------------------------------------
	local function getRemote(name: string): RemoteEvent
		return self.Remotes:FindFirstChild(name) or Instance.new("RemoteEvent", self.Remotes)
	end

	local function broadcast(remoteName: string, ...)
		getRemote(remoteName):FireAllClients(...)
	end

	-- Player lifecycle
	local function onPlayerAdded(player: Player)
		local userId = player.UserId
		GamepassManager.initPlayer(player)
		EconomyManager.initPlayer(userId)
		EconomyManager.initSessionCoins(userId, 100)
		EconomyManager.initKillEarnings(userId)
		ResourceManager.initPlayer(userId)
		RuneManager.initPlayer(userId)
		broadcast("PlayerJoined", player.Name)
	end

	local function onPlayerRemoving(player: Player)
		EconomyManager.removePlayer(player.UserId)
		ResourceManager.removePlayer(player.UserId)
		GamepassManager.removePlayer(player.UserId)
		RuneManager.removePlayer(player.UserId)
	end

	local function getPlayerUserIds(): { number }
		local ids = {}
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(ids, p.UserId)
		end
		return ids
	end

	-- State transitions
	local function setGameOver(reason: string)
		self.currentState = State.GAME_OVER
		RuneManager.returnAllRunes()
		EnemyManager.clearAll()

		-- Bank kill earnings for each player before broadcasting game over
		for _, userId in ipairs(getPlayerUserIds()) do
			local killEarnings = EconomyManager.getKillEarnings(userId)
			EconomyManager.bankKillEarnings(userId)
			local newPersistentBalance = EconomyManager.getPersistentCoins(userId)
			-- Fire TurretGameOver remote to each player with their banking info
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId == userId then
					getRemote("TurretGameOver"):FireClient(p, killEarnings, newPersistentBalance)
					break
				end
			end
		end

		-- Fire final rune inventory to each player after rune return
		for _, p in ipairs(Players:GetPlayers()) do
			getRemote("RuneInventoryUpdate"):FireClient(p, RuneManager.getInventory(p.UserId))
		end

		broadcast("GameOver", reason, self.currentRound)
		print("[GameManager] Game over:", reason, "| Reached round:", self.currentRound)
		if _gameOverCallback then
			_gameOverCallback(self.currentRound)
		end
	end

	local function startIntermission()
		self.currentState = State.INTERMISSION
		RuneManager.setGamePhase("Intermission")
		self.intermissionRemaining = self.intermissionTime
		broadcast("Intermission", self.intermissionTime, self.currentRound)
		print("[GameManager] Intermission before round", self.currentRound + 1)

		task.delay(self.intermissionTime, function()
			if self.currentState == State.INTERMISSION then
				self.startNextWave()
			end
		end)
	end

	local function onEnemyKilled(enemyData: any)
		if self.currentState == State.GAME_OVER then return end

		for _, userId in ipairs(getPlayerUserIds()) do
			local mult = GamepassManager.getCoinMultiplier(userId)
			local reward = enemyData.reward * mult
			EconomyManager.addMoney(userId, reward)
			EconomyManager.addSessionCoins(userId, reward)
			EconomyManager.addKillEarnings(userId, reward)
		end

		-- Fire session coins and kill earnings updates to each player
		for _, p in ipairs(Players:GetPlayers()) do
			local uid = p.UserId
			getRemote("SessionCoinsUpdate"):FireClient(p, EconomyManager.getSessionCoins(uid))
			getRemote("KillEarningsUpdate"):FireClient(p, EconomyManager.getKillEarnings(uid))
		end

		if enemyData.isBoss then
			local resourceId = ResourceManager.awardBossDrop(getPlayerUserIds(), self.currentRound)
			broadcast("BossDrop", resourceId)
			print("[GameManager] Boss killed! Dropped resource", resourceId)

			local runeTypeId = RuneManager.awardBossDrop(getPlayerUserIds(), self.currentRound)
			for _, p in ipairs(Players:GetPlayers()) do
				getRemote("RuneInventoryUpdate"):FireClient(p, RuneManager.getInventory(p.UserId))
			end
		end

		broadcast("EnemyKilled", enemyData.reward, enemyData.isBoss)

		self.enemiesAlive -= 1
		if self.enemiesAlive <= 0 and self.currentState == State.WAVE then
			print("[GameManager] Wave", self.currentRound, "cleared!")
			broadcast("WaveCleared", self.currentRound)
			startIntermission()
		end
	end

	local function onEnemyReachedEnd(enemyData: any)
		if self.currentState == State.GAME_OVER then return end

		local damage = 1
		if enemyData and enemyData.isBoss then
			damage = 10
		end
		self.baseHealth -= damage
		broadcast("BaseDamaged", self.baseHealth)
		print("[GameManager] Base hit! Health:", self.baseHealth)

		self.enemiesAlive -= 1
		if self.baseHealth <= 0 then
			setGameOver("Base destroyed")
			return
		end

		if self.enemiesAlive <= 0 and self.currentState == State.WAVE then
			broadcast("WaveCleared", self.currentRound)
			startIntermission()
		end
	end

	local function update(dt: number)
		if self.currentState == State.GAME_OVER then return end
		local scaledDt = dt * self.gameSpeed

		if self.currentState == State.INTERMISSION then
			self.intermissionRemaining = math.max(0, self.intermissionRemaining - scaledDt)
			-- Support turrets (coin printer, medic) tick between waves too
			TurretManager.updateSupport(scaledDt)
		end

		if self.currentState == State.WAVE then
			if self.spawnIndex <= #self.spawnQueue then
				self.spawnTimer -= scaledDt
				if self.spawnTimer <= 0 then
					local entry = self.spawnQueue[self.spawnIndex]
					EnemyManager.spawnEnemy(entry.enemyType, self.currentRound)
					self.spawnTimer = entry.interval
					self.spawnIndex += 1
				end
			end

			EnemyManager.update(scaledDt)
			TowerManager.update(scaledDt)
			TurretManager.update(scaledDt)
		end
	end

	local function onPlaceTower(player: Player, gridX: number, gridZ: number, worldX: number, worldZ: number, resourceIds: { number })
		local userId = player.UserId
		local cost = TowerManager.getTowerCost(#resourceIds)

		if not EconomyManager.spend(userId, cost) then
			getRemote("PlaceTowerResult"):FireClient(player, false, "Not enough money")
			return
		end

		if not ResourceManager.consumeResources(userId, resourceIds) then
			EconomyManager.addMoney(userId, cost)
			getRemote("PlaceTowerResult"):FireClient(player, false, "Insufficient resources")
			return
		end

		local _mapData = EnemyPath.getMap("Map1")
		local worldPos = Vector3.new(worldX, 0, worldZ)
		local success, result = TowerManager.placeTower(userId, gridX, gridZ, worldPos, resourceIds)

		if not success then
			EconomyManager.addMoney(userId, cost)
			ResourceManager.addResource(userId, resourceIds[1], #resourceIds)
			getRemote("PlaceTowerResult"):FireClient(player, false, result)
			return
		end

		broadcast("TowerPlaced", gridX, gridZ, worldX, worldZ, resourceIds, result)
		getRemote("PlaceTowerResult"):FireClient(player, true, result)
		getRemote("MoneyUpdate"):FireClient(player, EconomyManager.getMoney(userId))
	end

	local function onRequestInventory(player: Player)
		local inv = ResourceManager.getInventory(player.UserId)
		getRemote("InventoryUpdate"):FireClient(player, inv)
	end

	-- Task 9.4: Handle turret placement (separate from combo tower PlaceTower)
	local function onPlaceTurret(player: Player, turretTypeId: number, gridX: number, gridZ: number, worldX: number, worldZ: number)
		local userId = player.UserId
		local success, result = TurretManager.placeTurret(userId, turretTypeId, gridX, gridZ, Vector3.new(worldX, 0, worldZ))

		if not success then
			getRemote("PlaceTurretResult"):FireClient(player, false, result)
			return
		end

		getRemote("PlaceTurretResult"):FireClient(player, true, result)
		broadcast("TurretPlaced", turretTypeId, gridX, gridZ, worldX, worldZ, result)
		-- Update session coins for the placing player
		getRemote("SessionCoinsUpdate"):FireClient(player, EconomyManager.getSessionCoins(userId))
	end

	-- Task 9.5: Handle turret upgrade
	local function onUpgradeTurret(player: Player, turretInstanceId: string)
		local userId = player.UserId
		local success, result = TurretManager.upgradeTurret(turretInstanceId, userId)

		if not success then
			getRemote("UpgradeTurretResult"):FireClient(player, false, result)
			return
		end

		-- Get updated turret info for broadcast
		local turrets = TurretManager.getTurrets()
		local turret = turrets[turretInstanceId]
		if turret then
			broadcast("TurretUpgraded", turretInstanceId, turret.level, turret.stats)
		end

		getRemote("UpgradeTurretResult"):FireClient(player, true, nil)
		-- Update session coins for the upgrading player
		getRemote("SessionCoinsUpdate"):FireClient(player, EconomyManager.getSessionCoins(userId))
	end

	-- ------------------------------------------------------------------
	-- Public instance methods
	-- ------------------------------------------------------------------

	function self.startNextWave()
		if self.currentState == State.GAME_OVER then return end
		self.currentRound += 1
		local waveConfig = WaveData.generateWave(self.currentRound)
		self.currentState = State.WAVE
		RuneManager.setGamePhase("Wave")
		self.enemiesAlive = 0

		self.spawnQueue = {}
		for _, group in ipairs(waveConfig.enemies) do
			for _ = 1, group.count do
				table.insert(self.spawnQueue, { enemyType = group.enemyType, interval = group.interval })
				self.enemiesAlive += 1
			end
		end
		self.spawnIndex = 1
		self.spawnTimer = 0

		broadcast("WaveStarted", self.currentRound, waveConfig.isBossRound, self.enemiesAlive)
		print("[GameManager] Wave", self.currentRound, "started |", self.enemiesAlive, "enemies | Boss:", waveConfig.isBossRound)
	end

	function self.init()
		self.Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
		self.Remotes.Name = "Remotes"

		local remoteNames = {
			"PlaceTower", "PlaceTowerResult", "MoneyUpdate", "InventoryUpdate",
			"WaveStarted", "WaveCleared", "Intermission", "GameOver",
			"EnemyKilled", "BossDrop", "BaseDamaged", "PlayerJoined", "TowerPlaced",
			"RequestInventory", "RequestState",
			"LobbyState", "LobbyCountdown", "LobbyJoinResult", "LobbyReturnToLobby", "LobbyShowResults",
			-- Turret system remotes
			"PlaceTurret", "PlaceTurretResult", "TurretPlaced",
			"UpgradeTurret", "UpgradeTurretResult", "TurretUpgraded",
			"SessionCoinsUpdate", "KillEarningsUpdate", "TurretGameOver",
			-- Speed control
			"SetGameSpeed", "GameSpeedChanged",
			-- Rune system remotes
			"ApplyRune", "ApplyRuneResult", "RuneInventoryUpdate", "TurretRunesUpdate",
		}
		for _, name in ipairs(remoteNames) do
			if not self.Remotes:FindFirstChild(name) then
				local r = Instance.new("RemoteEvent")
				r.Name = name
				r.Parent = self.Remotes
			end
		end

		EnemyManager.onKilled(onEnemyKilled)
		EnemyManager.onReachedEnd(onEnemyReachedEnd)
		EnemyManager.setMapOffset(Vector3.new(0, 0, -10000))
		EnemyManager.setMap("Map1")

		-- Support tower callbacks
		TurretManager.onSupportMoney(function(ownerId, amount)
			local mult = GamepassManager.getCoinMultiplier(ownerId)
			local boosted = amount * mult
			EconomyManager.addSessionCoins(ownerId, boosted)
			-- Notify the player of updated balance
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId == ownerId then
					getRemote("SessionCoinsUpdate"):FireClient(p, EconomyManager.getSessionCoins(ownerId))
					break
				end
			end
		end)

		TurretManager.onSupportHealth(function(amount)
			if self.currentState == State.GAME_OVER then return end
			self.baseHealth = math.min(self.baseHealth + amount, 20)
			broadcast("BaseDamaged", self.baseHealth)
		end)

		-- Wire rune data into TurretManager for projectile visuals (avoids circular dependency)
		TurretManager.onGetTurretRunes(function(turretInstanceId)
			return RuneManager.getTurretRunes(turretInstanceId)
		end)

		MapBuilder.build("Map1", Vector3.new(0, 0, -10000))

		Players.PlayerAdded:Connect(onPlayerAdded)
		Players.PlayerRemoving:Connect(onPlayerRemoving)
		for _, p in ipairs(Players:GetPlayers()) do
			onPlayerAdded(p)
		end

		self.Remotes.PlaceTower.OnServerEvent:Connect(onPlaceTower)
		self.Remotes.RequestInventory.OnServerEvent:Connect(onRequestInventory)
		self.Remotes.PlaceTurret.OnServerEvent:Connect(onPlaceTurret)
		self.Remotes.UpgradeTurret.OnServerEvent:Connect(onUpgradeTurret)

		self.Remotes.ApplyRune.OnServerEvent:Connect(function(player, turretInstanceId, runeTypeId)
			if type(turretInstanceId) ~= "string" or type(runeTypeId) ~= "number" then return end
			local success, reason = RuneManager.applyRune(player.UserId, turretInstanceId, runeTypeId)
			getRemote("ApplyRuneResult"):FireClient(player, success, reason)
			if success then
				getRemote("RuneInventoryUpdate"):FireClient(player, RuneManager.getInventory(player.UserId))
				broadcast("TurretRunesUpdate", turretInstanceId, RuneManager.getTurretRunes(turretInstanceId), TurretManager.getTurrets()[turretInstanceId].stats)
			end
		end)

		self.Remotes.SetGameSpeed.OnServerEvent:Connect(function(player, speed)
			local s = tonumber(speed)
			if s and (s == 1 or s == 2 or s == 3) then
				self.gameSpeed = s
				broadcast("GameSpeedChanged", s)
			end
		end)

		self.Remotes.RequestState.OnServerEvent:Connect(function(player)
			if self.currentState == State.INTERMISSION then
				self.Remotes.Intermission:FireClient(player, math.ceil(self.intermissionRemaining), self.currentRound)
			elseif self.currentState == State.WAVE then
				self.Remotes.WaveStarted:FireClient(player, self.currentRound, WaveData.generateWave(self.currentRound).isBossRound, self.enemiesAlive)
			end
			self.Remotes.MoneyUpdate:FireClient(player, EconomyManager.getMoney(player.UserId))
		end)

		_heartbeatConnection = RunService.Heartbeat:Connect(update)

		print("[GameManager] Initialized. Waiting for first wave...")
	end

	-- ------------------------------------------------------------------
	-- Lifecycle methods (used by LobbyManager)
	-- ------------------------------------------------------------------

	function self.start()
		-- Broadcast initial state to clients so HUD resets from any previous game
		broadcast("BaseDamaged", self.baseHealth)
		for _, p in ipairs(Players:GetPlayers()) do
			local uid = p.UserId
			getRemote("MoneyUpdate"):FireClient(p, EconomyManager.getMoney(uid))
			getRemote("SessionCoinsUpdate"):FireClient(p, EconomyManager.getSessionCoins(uid))
		end
		startIntermission()
	end

	function self.stop()
		if _heartbeatConnection then
			_heartbeatConnection:Disconnect()
			_heartbeatConnection = nil
		end
		EnemyManager.clearAll()
		TurretManager.clearAll()
		RuneManager.clearAll()
		self.currentState = State.LOBBY
		self.currentRound = 0
		self.enemiesAlive = 0
		self.spawnQueue = {}
		self.spawnIndex = 1
		self.spawnTimer = 0
		print("[GameManager] Instance stopped.")
	end

	function self.onGameOver(callback: (roundReached: number) -> ())
		_gameOverCallback = callback
	end

	return self
end

-- ---------------------------------------------------------------------------
-- Module-level singleton (backward-compatible init())
-- ---------------------------------------------------------------------------
local _singletonInstance = nil

function GameManager.init()
	_singletonInstance = createInstance()
	_singletonInstance.init()
	_singletonInstance.start()
end

function GameManager.startNextWave()
	if _singletonInstance then
		_singletonInstance.startNextWave()
	end
end

-- ---------------------------------------------------------------------------
-- GameManager.new: creates a scoped instance for a specific set of players
-- and area. Does NOT auto-start — call instance.start() to begin.
-- ---------------------------------------------------------------------------
function GameManager.new(players: { Player }, areaId: number, loadouts: { [number]: { number } }?)
	return createInstance(players, areaId, loadouts)
end

return GameManager
