-- PropertyGen.luau
-- Lightweight property-based testing helpers for Luau.
-- Provides random generators and a `check` runner that executes a property
-- function N times with randomised inputs.

local PropertyGen = {}

local rng = Random.new(os.clock())

--- Run `propertyFn` for `iterations` iterations. `propertyFn` receives the
--- iteration index and must return true (pass) or false/nil (fail).
--- Returns true if all iterations passed, or false + the iteration that failed.
function PropertyGen.check(iterations: number, propertyFn: (i: number) -> boolean): (boolean, number?)
	for i = 1, iterations do
		local ok = propertyFn(i)
		if not ok then
			return false, i
		end
	end
	return true, nil
end

--- Return a random integer in [min, max].
function PropertyGen.int(min: number, max: number): number
	return rng:NextInteger(min, max)
end

--- Return a random area index (1, 2, or 3).
function PropertyGen.areaIndex(): number
	return rng:NextInteger(1, 3)
end

--- Return a random status string.
function PropertyGen.status(): string
	local statuses = { "EMPTY", "WAITING", "IN_GAME", "RESULTS" }
	return statuses[rng:NextInteger(1, #statuses)]
end

--- Return a random occupant count (0, 1, or 2).
function PropertyGen.occupantCount(): number
	return rng:NextInteger(0, 2)
end

--- Return a random countdown value (0-10).
function PropertyGen.countdown(): number
	return rng:NextInteger(0, 10)
end

--- Create a mock Player object with a unique UserId and Name.
function PropertyGen.mockPlayer(id: number?): any
	local uid = id or rng:NextInteger(1, 999999)
	return {
		UserId = uid,
		Name = "Player_" .. uid,
		Character = nil, -- tests can set this if needed
	}
end

--- Return a table of N unique mock players.
function PropertyGen.mockPlayers(n: number): { any }
	local players = {}
	local usedIds = {}
	for _ = 1, n do
		local uid
		repeat
			uid = rng:NextInteger(1, 999999)
		until not usedIds[uid]
		usedIds[uid] = true
		table.insert(players, PropertyGen.mockPlayer(uid))
	end
	return players
end

--- Generate a random AreaStateSnapshot.
function PropertyGen.areaStateSnapshot(indexOverride: number?): any
	local status = PropertyGen.status()
	local occupantCount = PropertyGen.occupantCount()
	local countdown = 0

	if status == "WAITING" then
		countdown = PropertyGen.countdown()
	end

	-- If IN_GAME or RESULTS, occupantCount should be 1 or 2
	if status == "IN_GAME" or status == "RESULTS" then
		occupantCount = math.max(1, occupantCount)
	end

	return {
		index = indexOverride or PropertyGen.areaIndex(),
		status = status,
		occupantCount = occupantCount,
		countdown = countdown,
	}
end

-- Turret-specific generators

--- Return a random turret type id in [1, 6].
function PropertyGen.turretTypeId(): number
	return rng:NextInteger(1, 6)
end

--- Return a random session coin amount in [1, 1000].
function PropertyGen.sessionCoinAmount(): number
	return rng:NextInteger(1, 1000)
end

--- Return a random persistent coin amount in [1, 5000].
function PropertyGen.persistentCoinAmount(): number
	return rng:NextInteger(1, 5000)
end

--- Return a random turret level in [1, 3].
function PropertyGen.turretLevel(): number
	return rng:NextInteger(1, 3)
end

--- Return a random grid position (gridX, gridZ).
function PropertyGen.gridPosition(): (number, number)
	return rng:NextInteger(-50, 50), rng:NextInteger(-50, 50)
end

--- Return a random enemy position as a Vector3 within maxRange of center.
function PropertyGen.enemyPosition(center: Vector3?, maxRange: number?): Vector3
	local cx = center and center.X or 0
	local cz = center and center.Z or 0
	local r = maxRange or 30
	local angle = rng:NextNumber() * math.pi * 2
	local dist = rng:NextNumber() * r
	return Vector3.new(cx + math.cos(angle) * dist, 0, cz + math.sin(angle) * dist)
end

--- Return a random loadout of 3 turret ids from the given unlocked set.
function PropertyGen.loadout(unlockedIds: { number }): { number }
	local result = {}
	for i = 1, 3 do
		result[i] = unlockedIds[rng:NextInteger(1, #unlockedIds)]
	end
	return result
end

--- Return a random rune type id in [1, 10].
function PropertyGen.runeTypeId(): number
	return rng:NextInteger(1, 10)
end

--- Return a random rune slot (list of rune type ids) with size in [0, maxSize].
function PropertyGen.runeSlot(maxSize: number?): { number }
	local size = rng:NextInteger(0, maxSize or 5)
	local slot = {}
	for i = 1, size do
		slot[i] = rng:NextInteger(1, 10)
	end
	return slot
end

--- Return a random rune inventory table with counts in [0, 5] for all 10 types.
function PropertyGen.runeInventory(): { [number]: number }
	local inv = {}
	for i = 1, 10 do
		inv[i] = rng:NextInteger(0, 5)
	end
	return inv
end

return PropertyGen
