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

local GameManager = {}

-- Game state
local State = {
	LOBBY        = "Lobby",
	INTERMISSION = "Intermission",
	WAVE         = "Wave",
	GAME_OVER    = "GameOver",
}

local currentState  = State.LOBBY
local currentRound  = 0
local baseHealth    = 20
local spawnQueue: { { enemyType: string, count: number, interval: number } } = {}
local spawnIndex    = 1
local spawnTimer    = 0
local enemiesAlive  = 0
local intermissionTime = 15 -- seconds between waves

-- Remotes
local Remotes: Folder
local function getRemote(name: string): RemoteEvent
	return Remotes:FindFirstChild(name) or Instance.new("RemoteEvent", Remotes)
end

local function broadcast(remoteName: string, ...)
	getRemote(remoteName):FireAllClients(...)
end

-- Player lifecycle
local function onPlayerAdded(player: Player)
	local userId = player.UserId
	EconomyManager.initPlayer(userId)
	ResourceManager.initPlayer(userId)
	broadcast("PlayerJoined", player.Name)
end

local function onPlayerRemoving(player: Player)
	EconomyManager.removePlayer(player.UserId)
	ResourceManager.removePlayer(player.UserId)
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
	currentState = State.GAME_OVER
	EnemyManager.clearAll()
	broadcast("GameOver", reason, currentRound)
	print("[GameManager] Game over:", reason, "| Reached round:", currentRound)
end

local function startIntermission()
	currentState = State.INTERMISSION
	broadcast("Intermission", intermissionTime, currentRound)
	print("[GameManager] Intermission before round", currentRound + 1)

	task.delay(intermissionTime, function()
		if currentState == State.INTERMISSION then
			GameManager.startNextWave()
		end
	end)
end

function GameManager.startNextWave()
	currentRound += 1
	local waveConfig = WaveData.generateWave(currentRound)
	currentState = State.WAVE
	enemiesAlive = 0

	-- Flatten spawn queue
	spawnQueue = {}
	for _, group in ipairs(waveConfig.enemies) do
		for i = 1, group.count do
			table.insert(spawnQueue, { enemyType = group.enemyType, interval = group.interval })
			enemiesAlive += 1
		end
	end
	spawnIndex = 1
	spawnTimer = 0

	broadcast("WaveStarted", currentRound, waveConfig.isBossRound, enemiesAlive)
	print("[GameManager] Wave", currentRound, "started |", enemiesAlive, "enemies | Boss:", waveConfig.isBossRound)
end

-- Called when an enemy is killed
local function onEnemyKilled(enemyData: any)
	-- Award money to all players
	for _, userId in ipairs(getPlayerUserIds()) do
		EconomyManager.addMoney(userId, enemyData.reward)
	end

	-- Boss drop
	if enemyData.isBoss then
		local resourceId = ResourceManager.awardBossDrop(getPlayerUserIds(), currentRound)
		broadcast("BossDrop", resourceId)
		print("[GameManager] Boss killed! Dropped resource", resourceId)
	end

	-- Broadcast kill reward
	broadcast("EnemyKilled", enemyData.reward, enemyData.isBoss)

	enemiesAlive -= 1
	if enemiesAlive <= 0 and currentState == State.WAVE then
		print("[GameManager] Wave", currentRound, "cleared!")
		broadcast("WaveCleared", currentRound)
		startIntermission()
	end
end

-- Called when an enemy reaches the base
local function onEnemyReachedEnd()
	baseHealth -= 1
	broadcast("BaseDamaged", baseHealth)
	print("[GameManager] Base hit! Health:", baseHealth)

	enemiesAlive -= 1
	if baseHealth <= 0 then
		setGameOver("Base destroyed")
		return
	end

	if enemiesAlive <= 0 and currentState == State.WAVE then
		broadcast("WaveCleared", currentRound)
		startIntermission()
	end
end

-- Main update loop
local function update(dt: number)
	if currentState == State.WAVE then
		-- Spawn enemies from queue
		if spawnIndex <= #spawnQueue then
			spawnTimer -= dt
			if spawnTimer <= 0 then
				local entry = spawnQueue[spawnIndex]
				EnemyManager.spawnEnemy(entry.enemyType, currentRound)
				spawnTimer = entry.interval
				spawnIndex += 1
			end
		end

		EnemyManager.update(dt)
		TowerManager.update(dt)
	end
end

-- Remote: client requests tower placement
local function onPlaceTower(player: Player, gridX: number, gridZ: number, worldX: number, worldZ: number, resourceIds: { number })
	local userId = player.UserId
	local cost = TowerManager.getTowerCost(#resourceIds)

	if not EconomyManager.spend(userId, cost) then
		getRemote("PlaceTowerResult"):FireClient(player, false, "Not enough money")
		return
	end

	if not ResourceManager.consumeResources(userId, resourceIds) then
		-- Refund
		EconomyManager.addMoney(userId, cost)
		getRemote("PlaceTowerResult"):FireClient(player, false, "Insufficient resources")
		return
	end

	local mapData = EnemyPath.getMap(EnemyManager.setMap and "Map1" or "Map1")
	local worldPos = Vector3.new(worldX, 0, worldZ)
	local success, result = TowerManager.placeTower(userId, gridX, gridZ, worldPos, resourceIds)

	if not success then
		-- Refund both
		EconomyManager.addMoney(userId, cost)
		ResourceManager.addResource(userId, resourceIds[1], #resourceIds) -- approximate refund
		getRemote("PlaceTowerResult"):FireClient(player, false, result)
		return
	end

	broadcast("TowerPlaced", gridX, gridZ, worldX, worldZ, resourceIds, result)
	getRemote("PlaceTowerResult"):FireClient(player, true, result)

	-- Sync money
	getRemote("MoneyUpdate"):FireClient(player, EconomyManager.getMoney(userId))
end

-- Remote: client requests resource inventory
local function onRequestInventory(player: Player)
	local inv = ResourceManager.getInventory(player.UserId)
	getRemote("InventoryUpdate"):FireClient(player, inv)
end

function GameManager.init()
	Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
	Remotes.Name = "Remotes"

	-- Create all remotes upfront
	local remoteNames = {
		"PlaceTower", "PlaceTowerResult", "MoneyUpdate", "InventoryUpdate",
		"WaveStarted", "WaveCleared", "Intermission", "GameOver",
		"EnemyKilled", "BossDrop", "BaseDamaged", "PlayerJoined", "TowerPlaced",
		"RequestInventory",
	}
	for _, name in ipairs(remoteNames) do
		if not Remotes:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = Remotes
		end
	end

	-- Wire up enemy callbacks
	EnemyManager.onKilled(onEnemyKilled)
	EnemyManager.onReachedEnd(onEnemyReachedEnd)
	EnemyManager.setMap("Map1")

	-- Wire up player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end

	-- Wire up remotes
	Remotes.PlaceTower.OnServerEvent:Connect(onPlaceTower)
	Remotes.RequestInventory.OnServerEvent:Connect(onRequestInventory)

	-- Main loop
	RunService.Heartbeat:Connect(update)

	-- Start first intermission
	startIntermission()

	print("[GameManager] Initialized. Waiting for first wave...")
end

return GameManager
