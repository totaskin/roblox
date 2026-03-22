-- EnemyManager.luau
-- Spawns enemies, moves them along waypoints, handles death and base damage

local RunService   = game:GetService("RunService")
local WaveData     = require(game.ReplicatedStorage.Shared.WaveData)
local EnemyPath    = require(game.ReplicatedStorage.Shared.EnemyPath)

local EnemyManager = {}

local activeEnemies: { [string]: any } = {}
local enemyIdCounter = 0
local mapName = "Map1"
local onEnemyKilled: ((enemyData: any) -> ())? = nil
local onEnemyReachedEnd: (() -> ())? = nil

local WAYPOINT_REACH_DIST = 4 -- studs

local function newEnemyId(): string
	enemyIdCounter += 1
	return "enemy_" .. enemyIdCounter
end

function EnemyManager.setMap(name: string)
	mapName = name
end

function EnemyManager.onKilled(callback: (enemyData: any) -> ())
	onEnemyKilled = callback
end

function EnemyManager.onReachedEnd(callback: () -> ())
	onEnemyReachedEnd = callback
end

-- Spawns a single enemy model in workspace
local function spawnEnemyModel(enemyData: any, startPos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = enemyData.name

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(2, 2, 2) * enemyData.size
	body.Position = startPos
	body.Anchored = true
	body.BrickColor = enemyData.isBoss and BrickColor.new("Bright red") or BrickColor.new("Medium stone grey")
	body.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = enemyData.health
	humanoid.Health = enemyData.health
	humanoid.Parent = model

	model.PrimaryPart = body
	model.Parent = workspace

	return model
end

-- Register and spawn one enemy
function EnemyManager.spawnEnemy(enemyType: string, round: number)
	local mapData = EnemyPath.getMap(mapName)
	local waypoints = mapData.waypoints
	local startPos = waypoints[1]

	local scaledEnemy = WaveData.scaleEnemy(enemyType, round)
	local id = newEnemyId()

	local model = spawnEnemyModel(scaledEnemy, startPos)

	activeEnemies[id] = {
		id            = id,
		data          = scaledEnemy,
		model         = model,
		waypointIndex = 2,
		health        = scaledEnemy.health,
		isBoss        = scaledEnemy.isBoss,
		reward        = scaledEnemy.reward,
	}

	return id
end

-- Called every frame to move all enemies
function EnemyManager.update(dt: number)
	local mapData = EnemyPath.getMap(mapName)
	local waypoints = mapData.waypoints
	local toRemove = {}

	for id, enemy in pairs(activeEnemies) do
		if not enemy.model or not enemy.model.Parent then
			table.insert(toRemove, id)
			continue
		end

		local root = enemy.model.PrimaryPart
		if not root then continue end

		local target = waypoints[enemy.waypointIndex]
		if not target then
			-- Reached the end
			enemy.model:Destroy()
			table.insert(toRemove, id)
			if onEnemyReachedEnd then onEnemyReachedEnd() end
			continue
		end

		local pos = root.Position
		local dir = (target - pos)
		local dist = dir.Magnitude

		if dist < WAYPOINT_REACH_DIST then
			enemy.waypointIndex += 1
		else
			local move = dir.Unit * enemy.data.speed * dt
			root.Position = pos + move
		end
	end

	for _, id in ipairs(toRemove) do
		activeEnemies[id] = nil
	end
end

-- Deal damage to an enemy, returns true if killed
function EnemyManager.damageEnemy(enemyId: string, damage: number): boolean
	local enemy = activeEnemies[enemyId]
	if not enemy then return false end

	enemy.health -= damage
	-- Update humanoid health for visual
	local humanoid = enemy.model and enemy.model:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Health = math.max(0, enemy.health)
	end

	if enemy.health <= 0 then
		if enemy.model then enemy.model:Destroy() end
		activeEnemies[enemyId] = nil
		if onEnemyKilled then onEnemyKilled(enemy) end
		return true
	end
	return false
end

function EnemyManager.getActiveEnemies(): { [string]: any }
	return activeEnemies
end

function EnemyManager.clearAll()
	for _, enemy in pairs(activeEnemies) do
		if enemy.model then enemy.model:Destroy() end
	end
	activeEnemies = {}
end

-- Apply slow to an enemy
function EnemyManager.applySlow(enemyId: string, factor: number, duration: number)
	local enemy = activeEnemies[enemyId]
	if not enemy then return end
	local originalSpeed = enemy.data.speed
	enemy.data.speed = originalSpeed * factor
	task.delay(duration, function()
		if activeEnemies[enemyId] then
			activeEnemies[enemyId].data.speed = originalSpeed
		end
	end)
end

return EnemyManager
