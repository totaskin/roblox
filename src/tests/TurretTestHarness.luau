-- TurretTestHarness.luau
-- A test-friendly reimplementation of turret system core logic.
-- Mirrors the real EconomyManager, LobbyManager, TurretManager, and EnemyManager
-- but removes all Roblox service dependencies (no Instance, no Workspace, etc.).
-- This allows property-based tests to exercise turret logic directly.

local TurretData = require(script.Parent.Parent.shared.TurretData)

local TurretTestHarness = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock EconomyManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockEconomyManager()
	local eco = {}
	local playerSessionCoins: { [number]: number } = {}
	local playerPersistentCoins: { [number]: number } = {}
	local playerKillEarnings: { [number]: number } = {}

	-- Session coins
	function eco.initSessionCoins(userId: number, startingAmount: number)
		playerSessionCoins[userId] = startingAmount
	end

	function eco.getSessionCoins(userId: number): number
		return playerSessionCoins[userId] or 0
	end

	function eco.addSessionCoins(userId: number, amount: number)
		if playerSessionCoins[userId] then
			playerSessionCoins[userId] += amount
		end
	end

	function eco.spendSessionCoins(userId: number, amount: number): boolean
		if (playerSessionCoins[userId] or 0) >= amount then
			playerSessionCoins[userId] -= amount
			return true
		end
		return false
	end

	-- Persistent coins
	function eco.initPersistentCoins(userId: number)
		playerPersistentCoins[userId] = 0
	end

	function eco.getPersistentCoins(userId: number): number
		return playerPersistentCoins[userId] or 0
	end

	function eco.addPersistentCoins(userId: number, amount: number)
		if playerPersistentCoins[userId] then
			playerPersistentCoins[userId] += amount
		end
	end

	function eco.spendPersistentCoins(userId: number, amount: number): boolean
		if (playerPersistentCoins[userId] or 0) >= amount then
			playerPersistentCoins[userId] -= amount
			return true
		end
		return false
	end

	-- Kill earnings
	function eco.initKillEarnings(userId: number)
		playerKillEarnings[userId] = 0
	end

	function eco.addKillEarnings(userId: number, amount: number)
		if playerKillEarnings[userId] then
			playerKillEarnings[userId] += amount
		end
	end

	function eco.getKillEarnings(userId: number): number
		return playerKillEarnings[userId] or 0
	end

	function eco.bankKillEarnings(userId: number)
		local earnings = playerKillEarnings[userId] or 0
		if earnings > 0 and playerPersistentCoins[userId] then
			playerPersistentCoins[userId] += earnings
		end
		playerKillEarnings[userId] = 0
	end

	return eco
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock LobbyManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockLobbyManager(economyManager: any)
	local lobby = {}
	lobby.playerUnlocks = {} :: { [number]: { [number]: boolean } }
	lobby.playerLoadouts = {} :: { [number]: { number } }

	function lobby.initPlayer(userId: number)
		lobby.playerUnlocks[userId] = { [1] = true } -- Scout Turret unlocked by default
		lobby.playerLoadouts[userId] = {}
		economyManager.initPersistentCoins(userId)
	end

	function lobby.buyTurret(userId: number, turretTypeId: number): (boolean, string?)
		local unlocks = lobby.playerUnlocks[userId]
		if not unlocks then return false, "Player not initialized" end

		local turretType = TurretData.getTurretById(turretTypeId)
		if not turretType then return false, "Invalid turret type" end

		if unlocks[turretTypeId] then return false, "Already unlocked" end

		local success = economyManager.spendPersistentCoins(userId, turretType.shopPrice)
		if not success then return false, "Not enough persistent coins" end

		unlocks[turretTypeId] = true
		return true, nil
	end

	function lobby.setLoadout(userId: number, turretIds: { number }): (boolean, string?)
		local unlocks = lobby.playerUnlocks[userId]
		if not unlocks then return false, "Player not initialized" end

		-- If only 1 turret unlocked, auto-fill all 3 slots
		local unlockedCount = 0
		local singleId = nil
		for id, _ in pairs(unlocks) do
			unlockedCount += 1
			singleId = id
		end
		if unlockedCount == 1 then
			lobby.playerLoadouts[userId] = { singleId, singleId, singleId }
			return true, nil
		end

		-- Validate exactly 3 turret ids
		if #turretIds ~= 3 then
			return false, "Must select exactly 3 turrets"
		end

		-- Validate all turret ids are unlocked
		for _, id in ipairs(turretIds) do
			if not unlocks[id] then
				return false, "Turret not unlocked"
			end
		end

		lobby.playerLoadouts[userId] = { turretIds[1], turretIds[2], turretIds[3] }
		return true, nil
	end

	function lobby.getLoadout(userId: number): { number }
		return lobby.playerLoadouts[userId] or {}
	end

	function lobby.getUnlocks(userId: number): { [number]: boolean }
		return lobby.playerUnlocks[userId] or {}
	end

	return lobby
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock TurretManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockTurretManager(economyManager: any, lobbyManager: any)
	local tm = {}
	tm.turrets = {} :: { [string]: any }
	tm.turretIdCounter = 0

	local function newTurretId(): string
		tm.turretIdCounter += 1
		return "turret_" .. tm.turretIdCounter
	end

	local function isInLoadout(userId: number, turretTypeId: number): boolean
		local loadout = lobbyManager.playerLoadouts[userId]
		if not loadout then return false end
		for _, id in ipairs(loadout) do
			if id == turretTypeId then return true end
		end
		return false
	end

	local function isSlotOccupied(gridX: number, gridZ: number): boolean
		for _, t in pairs(tm.turrets) do
			if t.gridX == gridX and t.gridZ == gridZ then
				return true
			end
		end
		return false
	end

	function tm.placeTurret(
		userId: number,
		turretTypeId: number,
		gridX: number,
		gridZ: number
	): (boolean, string?)
		-- Validate turret type exists
		local turretType = TurretData.getTurretById(turretTypeId)
		if not turretType then
			return false, "Invalid turret type"
		end

		-- Validate turret is in player's loadout
		if not isInLoadout(userId, turretTypeId) then
			return false, "Turret not in loadout"
		end

		-- Validate slot is unoccupied
		if isSlotOccupied(gridX, gridZ) then
			return false, "Slot already occupied"
		end

		-- Validate player has sufficient coins
		local cost = turretType.placementCost
		if economyManager.getSessionCoins(userId) < cost then
			return false, "Not enough coins"
		end

		-- Deduct coins
		local spent = economyManager.spendSessionCoins(userId, cost)
		if not spent then
			return false, "Not enough coins"
		end

		-- Create TurretInstance at level 1 with base stats (no model)
		local id = newTurretId()
		tm.turrets[id] = {
			id = id,
			turretTypeId = turretTypeId,
			ownerId = userId,
			gridX = gridX,
			gridZ = gridZ,
			level = 1,
			stats = {
				damage = turretType.damage,
				range = turretType.range,
				fireRate = turretType.fireRate,
			},
			cooldown = 0,
		}

		return true, id
	end

	function tm.getUpgradeCost(turretTypeId: number, targetLevel: number): number
		local turretType = TurretData.getTurretById(turretTypeId)
		if not turretType then return 0 end
		return turretType.placementCost * math.pow(2, targetLevel - 1)
	end

	function tm.upgradeTurret(turretInstanceId: string, userId: number): (boolean, string?)
		local turret = tm.turrets[turretInstanceId]
		if not turret then return false, "Turret not found" end

		if turret.ownerId ~= userId then return false, "Not your turret" end

		local targetLevel = turret.level + 1
		local cost = tm.getUpgradeCost(turret.turretTypeId, targetLevel)

		if economyManager.getSessionCoins(userId) < cost then
			return false, "Not enough coins"
		end

		local spent = economyManager.spendSessionCoins(userId, cost)
		if not spent then return false, "Not enough coins" end

		turret.level = targetLevel

		local turretType = TurretData.getTurretById(turret.turretTypeId)
		if turretType then
			local mult = turretType.upgradeMultipliers
			turret.stats.damage = turretType.damage * mult.damage ^ (turret.level - 1)
			turret.stats.range = turretType.range * mult.range ^ (turret.level - 1)
			turret.stats.fireRate = turretType.fireRate * mult.fireRate ^ (turret.level - 1)
		end

		return true, nil
	end

	function tm.clearAll()
		tm.turrets = {}
	end

	function tm.getTurrets(): { [string]: any }
		return tm.turrets
	end

	return tm
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Mock EnemyManager
-- ═══════════════════════════════════════════════════════════════════════════

local function createMockEnemyManager()
	local em = {}
	em.enemies = {} :: { [string]: any }
	em.enemyIdCounter = 0
	em.damageLog = {} :: { { enemyId: string, damage: number } }

	function em.addEnemy(position: Vector3, health: number?): string
		em.enemyIdCounter += 1
		local id = "enemy_" .. em.enemyIdCounter
		em.enemies[id] = {
			id = id,
			position = position,
			health = health or 100,
		}
		return id
	end

	function em.getActiveEnemies(): { [string]: any }
		return em.enemies
	end

	function em.damageEnemy(enemyId: string, damage: number): boolean
		local enemy = em.enemies[enemyId]
		if not enemy then return false end

		table.insert(em.damageLog, { enemyId = enemyId, damage = damage })

		enemy.health -= damage
		if enemy.health <= 0 then
			em.enemies[enemyId] = nil
			return true
		end
		return false
	end

	function em.clearAll()
		em.enemies = {}
		em.damageLog = {}
	end

	return em
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Targeting helper (mirrors TurretManager.findTarget without Roblox deps)
-- ═══════════════════════════════════════════════════════════════════════════

local function findClosestEnemy(turretPos: Vector3, range: number, enemies: { [string]: any }): (string?, Vector3?)
	local bestDist = math.huge
	local bestId = nil
	local bestPos = nil

	for id, enemy in pairs(enemies) do
		local pos = enemy.position
		local dist = (pos - turretPos).Magnitude
		if dist <= range and dist < bestDist then
			bestDist = dist
			bestId = id
			bestPos = pos
		end
	end

	return bestId, bestPos
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TurretTestHarness.new() — creates an isolated test instance with all mocks
-- ═══════════════════════════════════════════════════════════════════════════

function TurretTestHarness.new()
	local self = {} :: any

	self.economy = createMockEconomyManager()
	self.lobby = createMockLobbyManager(self.economy)
	self.turretManager = createMockTurretManager(self.economy, self.lobby)
	self.enemyManager = createMockEnemyManager()
	self.findClosestEnemy = findClosestEnemy

	-- Helper: set up a player with session coins and persistent coins
	function self.setupPlayerWithCoins(userId: number, sessionCoins: number, persistentCoins: number?)
		self.economy.initSessionCoins(userId, sessionCoins)
		self.economy.initPersistentCoins(userId)
		if persistentCoins and persistentCoins > 0 then
			self.economy.addPersistentCoins(userId, persistentCoins)
		end
	end

	-- Helper: set up a player with a loadout (also initializes lobby state)
	function self.setupPlayerWithLoadout(userId: number, turretIds: { number }, sessionCoins: number?)
		self.lobby.initPlayer(userId)
		self.economy.initSessionCoins(userId, sessionCoins or 500)

		-- Unlock all turrets in the loadout
		for _, id in ipairs(turretIds) do
			self.lobby.playerUnlocks[userId][id] = true
		end

		-- Set the loadout
		self.lobby.playerLoadouts[userId] = turretIds
	end

	-- Helper: add a mock enemy at a position
	function self.addMockEnemy(position: Vector3, health: number?): string
		return self.enemyManager.addEnemy(position, health)
	end

	return self
end

return TurretTestHarness
