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

--- Return a random Color3 for player color testing.
function PropertyGen.playerColor(): Color3
	return Color3.fromRGB(rng:NextInteger(0, 255), rng:NextInteger(0, 255), rng:NextInteger(0, 255))
end

--- Return a random player display name string.
function PropertyGen.playerDisplayName(): string
	local names = { "Alex", "Jordan", "Sam", "Taylor", "Morgan", "Casey", "Riley", "Quinn", "Avery", "Dakota" }
	return names[rng:NextInteger(1, #names)] .. "_" .. rng:NextInteger(1, 9999)
end

-- Map-specific generators

--- Return a random map name from the available maps.
function PropertyGen.mapName(): string
	local maps = { "Map1", "Map2", "Map3" }
	return maps[rng:NextInteger(1, #maps)]
end

--- Return a random pad index in [1, 3].
function PropertyGen.padIndex(): number
	return rng:NextInteger(1, 3)
end

-- Purchase-specific generators

-- Base ID for placeholder product IDs (must match RunePurchaseManager)
local PLACEHOLDER_BASE_ID = 1000000000

--- Return a random product ID (valid or invalid).
--- Valid IDs: PLACEHOLDER_BASE_ID + 1 through 10 (single runes) and PLACEHOLDER_BASE_ID + 100 (bundle)
--- Invalid IDs: random numbers outside the valid range
function PropertyGen.productId(): number
	-- 70% chance of valid product ID, 30% chance of invalid
	if rng:NextNumber() < 0.7 then
		-- Valid product ID
		if rng:NextNumber() < 0.9 then
			-- Single rune product (1-10)
			return PLACEHOLDER_BASE_ID + rng:NextInteger(1, 10)
		else
			-- Bundle product
			return PLACEHOLDER_BASE_ID + 100
		end
	else
		-- Invalid product ID - generate something outside valid range
		local invalidType = rng:NextInteger(1, 4)
		if invalidType == 1 then
			-- Completely random small number
			return rng:NextInteger(1, 999999)
		elseif invalidType == 2 then
			-- Base ID without offset
			return PLACEHOLDER_BASE_ID
		elseif invalidType == 3 then
			-- Base ID with invalid offset (11-99)
			return PLACEHOLDER_BASE_ID + rng:NextInteger(11, 99)
		else
			-- Base ID with invalid offset (101+)
			return PLACEHOLDER_BASE_ID + rng:NextInteger(101, 999)
		end
	end
end

--- Return a random unique purchase ID string.
--- Format: "purchase_" followed by random alphanumeric characters (mimics Roblox format)
function PropertyGen.purchaseId(): string
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	local length = rng:NextInteger(16, 24)
	local result = "purchase_"
	for _ = 1, length do
		local idx = rng:NextInteger(1, #chars)
		result = result .. string.sub(chars, idx, idx)
	end
	return result
end

--- Return a mock purchase receipt structure matching Roblox's format.
--- @param playerId number The player's UserId
--- @param productId number The Developer Product ID
--- @return table Mock receipt structure
function PropertyGen.purchaseReceipt(playerId: number, productId: number): any
	return {
		PlayerId = playerId,
		ProductId = productId,
		PurchaseId = PropertyGen.purchaseId(),
		CurrencySpent = 0,
		CurrencyType = Enum.CurrencyType.Robux,
	}
end

return PropertyGen
