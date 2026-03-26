-- WaveData.luau
-- Enemy definitions and wave generation logic

local ENEMY_TYPES = {
	Grunt = {
		name="Bombardiro Crocodilo", health=60, speed=12, reward=15, isBoss=false, size=1.8,
	},
	Runner = {
		name="Tung Tung Tung Sahur", health=40, speed=18, reward=10, isBoss=false, size=1.4,
	},
	Brute = {
		name="Tralalero Tralala", health=180, speed=7, reward=20, isBoss=false, size=2.2,
	},
	Swarm = {
		name="Lirili Larila", health=20, speed=15, reward=6, isBoss=false, size=1.0,
	},
	Armored = {
		name="Cappuccino Assassino", health=300, speed=7, reward=25, isBoss=false, size=2.0,
	},
	-- Bosses (every 5 rounds)
	BossGrunt = {
		name="La Vaca Saturno Saturnita", health=400, speed=7, reward=60, isBoss=true, size=3.5,
	},
	BossRunner = {
		name="Brr Brr Patapim", health=300, speed=14, reward=80, isBoss=true, size=3.0,
	},
	BossBrute = {
		name="Spaghettino Macaronino", health=1000, speed=5, reward=120, isBoss=true, size=4.5,
	},
	BossVoid = {
		name="Glorbo Fruttodrillo", health=4000, speed=7, reward=300, isBoss=true, size=5.5,
	},
}

-- Scales enemy stats based on round number and optional strength multiplier
-- strengthMult is used when enemy count is capped to make fewer enemies stronger
local function scaleEnemy(baseType: string, round: number, strengthMult: number?)
	local base = ENEMY_TYPES[baseType]
	assert(base, "Unknown enemy type: " .. baseType)
	-- Accelerating difficulty: scaling % increases each round
	-- Round 1: 1.0x, Round 2: 1.4x, Round 3: 2.2x, Round 5: 6.7x, Round 10: 117x
	local scale = 1
	for r = 2, round do
		local rampRate = 1.3 + (r - 1) * 0.05 -- starts at 1.35, grows by 0.05 each round
		scale = scale * rampRate
	end
	-- Apply strength multiplier (from enemy count cap)
	local sMult = strengthMult or 1
	return {
		type     = baseType,
		name     = base.name,
		health   = math.floor(base.health * scale * sMult),
		speed    = base.speed + round * 0.04 + round * round * 0.01, -- accelerating speed creep
		reward   = math.floor(base.reward * (1 + (round - 1) * 0.08)), -- 8% linear reward scaling
		isBoss   = base.isBoss,
		size     = base.size,
	}
end

-- Picks boss type based on round milestone
local function getBossType(round: number): string
	if round >= 100 then return "BossVoid"
	elseif round >= 50 then return "BossBrute"
	elseif round >= 20 then return "BossRunner"
	else return "BossGrunt"
	end
end

-- Generates wave config for a given round
local function generateWave(round: number)
	local isBossRound = (round % 5 == 0)
	local enemies = {}

	-- Scale enemy count with round — capped at 60 for performance
	local uncappedCount = math.floor(8 + round * 3 + round * round * 0.5)
	local baseCount = math.min(60, uncappedCount)
	
	-- Strength multiplier: when count is capped, enemies get stronger instead
	-- After cap kicks in (~round 10), each round adds proportional strength
	local strengthMult = uncappedCount / baseCount -- 1.0 when not capped, grows after

	if isBossRound then
		-- Boss wave: fewer normal enemies + 1 boss
		local normalCount = math.floor(baseCount * 0.5)
		table.insert(enemies, { enemyType="Grunt",  count=normalCount, interval=0.8 })
		table.insert(enemies, { enemyType=getBossType(round), count=1, interval=0 })
	else
		-- Normal wave: mix of enemy types based on round progression
		if round < 3 then
			table.insert(enemies, { enemyType="Grunt", count=baseCount, interval=1.0 })
		elseif round < 8 then
			table.insert(enemies, { enemyType="Grunt",  count=math.floor(baseCount*0.5), interval=0.9 })
			table.insert(enemies, { enemyType="Runner", count=math.floor(baseCount*0.5), interval=0.6 })
		elseif round < 18 then
			table.insert(enemies, { enemyType="Grunt",  count=math.floor(baseCount*0.35), interval=0.9 })
			table.insert(enemies, { enemyType="Runner", count=math.floor(baseCount*0.3), interval=0.6 })
			table.insert(enemies, { enemyType="Brute",  count=math.floor(baseCount*0.35), interval=1.5 })
		elseif round < 45 then
			table.insert(enemies, { enemyType="Runner",  count=math.floor(baseCount*0.25), interval=0.5 })
			table.insert(enemies, { enemyType="Brute",   count=math.floor(baseCount*0.3), interval=1.0 })
			table.insert(enemies, { enemyType="Swarm",   count=math.floor(baseCount*0.25), interval=0.3 })
			table.insert(enemies, { enemyType="Armored", count=math.floor(baseCount*0.2), interval=1.4 })
		else
			table.insert(enemies, { enemyType="Brute",   count=math.floor(baseCount*0.25), interval=0.8 })
			table.insert(enemies, { enemyType="Swarm",   count=math.floor(baseCount*0.25), interval=0.25 })
			table.insert(enemies, { enemyType="Armored", count=math.floor(baseCount*0.5), interval=1.0 })
		end
	end

	return {
		round       = round,
		enemies     = enemies,
		isBossRound = isBossRound,
		strengthMult = strengthMult,
	}
end

return {
	ENEMY_TYPES   = ENEMY_TYPES,
	scaleEnemy    = scaleEnemy,
	generateWave  = generateWave,
	getBossType   = getBossType,
}
