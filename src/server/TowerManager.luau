-- TowerManager.luau
-- Handles tower placement, targeting, shooting and combo resolution

local TowerData    = require(game.ReplicatedStorage.Shared.TowerData)
local EnemyManager = require(script.Parent.EnemyManager)

local TowerManager = {}

local towers: { [string]: any } = {}
local towerIdCounter = 0

local TOWER_COST_BASE = 50 -- base cost, scales with number of resources used
local TOWER_COST_PER_RESOURCE = 30

local function newTowerId(): string
	towerIdCounter += 1
	return "tower_" .. towerIdCounter
end

function TowerManager.getTowerCost(resourceCount: number): number
	return TOWER_COST_BASE + resourceCount * TOWER_COST_PER_RESOURCE
end

-- Builds the tower model in workspace
local function buildTowerModel(position: Vector3, stats: any, resourceIds: { number }): Model
	local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)

	local model = Instance.new("Model")
	model.Name = stats.name

	-- Base
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(4, 1, 4)
	base.Position = position
	base.Anchored = true
	base.BrickColor = stats.cursed and BrickColor.new("Really black") or BrickColor.new("Dark stone grey")
	base.Parent = model

	-- Tower body — color blended from resources used
	local r, g, b = 0, 0, 0
	for _, id in ipairs(resourceIds) do
		local res = ResourceData.Resources[id]
		if res then
			r += res.color.R
			g += res.color.G
			b += res.color.B
		end
	end
	local count = #resourceIds
	local blendedColor = Color3.new(r/count, g/count, b/count)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 4, 2)
	body.Position = position + Vector3.new(0, 2.5, 0)
	body.Anchored = true
	body.Color = blendedColor
	body.Parent = model

	-- Range indicator (invisible, used for targeting)
	local rangeTag = Instance.new("NumberValue")
	rangeTag.Name = "Range"
	rangeTag.Value = stats.range
	rangeTag.Parent = model

	model.PrimaryPart = base
	model.Parent = workspace

	return model
end

-- Places a tower at a grid position
function TowerManager.placeTower(
	userId: number,
	gridX: number,
	gridZ: number,
	worldPos: Vector3,
	resourceIds: { number }
): (boolean, string?)
	if #resourceIds < 1 or #resourceIds > 5 then
		return false, "Must use 1 to 5 resources"
	end

	-- Check slot not already occupied
	for _, t in pairs(towers) do
		if t.gridX == gridX and t.gridZ == gridZ then
			return false, "Slot already occupied"
		end
	end

	local stats = TowerData.resolveStats(resourceIds)
	local id = newTowerId()
	local model = buildTowerModel(worldPos, stats, resourceIds)

	towers[id] = {
		id          = id,
		ownerId     = userId,
		gridX       = gridX,
		gridZ       = gridZ,
		position    = worldPos,
		stats       = stats,
		resourceIds = resourceIds,
		model       = model,
		cooldown    = 0,
	}

	return true, id
end

function TowerManager.removeTower(towerId: string)
	local t = towers[towerId]
	if t and t.model then t.model:Destroy() end
	towers[towerId] = nil
end

-- Find closest enemy within range
local function findTarget(towerPos: Vector3, range: number): (string?, Vector3?)
	local bestDist = math.huge
	local bestId = nil
	local bestPos = nil

	for id, enemy in pairs(EnemyManager.getActiveEnemies()) do
		local root = enemy.model and enemy.model.PrimaryPart
		if not root then continue end
		local dist = (root.Position - towerPos).Magnitude
		if dist <= range and dist < bestDist then
			bestDist = dist
			bestId = id
			bestPos = root.Position
		end
	end

	return bestId, bestPos
end

-- Find all enemies within radius (for AoE)
local function findEnemiesInRadius(center: Vector3, radius: number): { string }
	local found = {}
	for id, enemy in pairs(EnemyManager.getActiveEnemies()) do
		local root = enemy.model and enemy.model.PrimaryPart
		if not root then continue end
		if (root.Position - center).Magnitude <= radius then
			table.insert(found, id)
		end
	end
	return found
end

-- Fires a visual projectile (simple part)
local function fireProjectile(from: Vector3, to: Vector3, color: Color3)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.3, 0.3, 0.3)
	part.Position = from
	part.Anchored = true
	part.CanCollide = false
	part.Color = color
	part.Shape = Enum.PartType.Ball
	part.Parent = workspace

	local steps = 8
	local stepVec = (to - from) / steps
	for i = 1, steps do
		task.wait(0.02)
		part.Position = from + stepVec * i
	end
	part:Destroy()
end

-- Update all towers: find targets, shoot, apply effects
function TowerManager.update(dt: number)
	for _, tower in pairs(towers) do
		tower.cooldown -= dt
		if tower.cooldown > 0 then continue end

		local stats = tower.stats
		local targetId, targetPos = findTarget(tower.position, stats.range)
		if not targetId or not targetPos then continue end

		tower.cooldown = 1 / stats.fireRate

		-- AoE or single target
		local hitIds: { string }
		if stats.aoeRadius > 0 then
			hitIds = findEnemiesInRadius(targetPos, stats.aoeRadius)
		else
			hitIds = { targetId }
		end

		-- Determine projectile color from first resource
		local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)
		local projColor = Color3.new(1, 1, 1)
		if tower.resourceIds[1] then
			local res = ResourceData.Resources[tower.resourceIds[1]]
			if res then projColor = res.color end
		end

		-- Fire projectile visually (non-blocking)
		task.spawn(fireProjectile, tower.position + Vector3.new(0, 3, 0), targetPos, projColor)

		-- Apply damage and effects
		for _, hitId in ipairs(hitIds) do
			local killed = EnemyManager.damageEnemy(hitId, stats.damage)

			-- Apply slow if not killed
			if not killed and stats.slowFactor < 1 then
				EnemyManager.applySlow(hitId, stats.slowFactor, 2)
			end
		end
	end
end

function TowerManager.getTowers(): { [string]: any }
	return towers
end

function TowerManager.clearAll()
	for _, t in pairs(towers) do
		if t.model then t.model:Destroy() end
	end
	towers = {}
end

return TowerManager
