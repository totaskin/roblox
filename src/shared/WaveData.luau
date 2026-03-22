-- WaveData.luau
-- Enemy definitions and wave generation logic

local ENEMY_TYPES = {
	Grunt = {
		name="Grunt", health=50, speed=12, reward=5, isBoss=false, size=1.0,
	},
	Runner = {
		name="Runner", health=30, speed=20, reward=4, isBoss=false, size=0.8,
	},
	Brute = {
		name="Brute", health=150, speed=7, reward=12, isBoss=false, size=1.5,
	},
	Swarm = {
		name="Swarm", health=15, speed=16, reward=2, isBoss=false, size=0.6,
	},
	Armored = {
		name="Armored", health=200, speed=8, reward=15, isBoss=false, size=1.2,
	},
	-- Bosses (every 5 rounds)
	BossGrunt = {
		name="BossGrunt", health=500, speed=10, reward=50, isBoss=true, size=2.5,
	},
	BossRunner = {
		name="BossRunner", health=300, speed=16, reward=60, isBoss=true, size=2.0,
	},
	BossBrute = {
		name="BossBrute", health=1200, speed=6, reward=100, isBoss=true, size=3.5,
	},
	BossVoid = {
		name="BossVoid", health=5000, speed=8, reward=500, isBoss=true, size=4.0,
	},
}

-- Scales enemy stats based on round number
local function scaleEnemy(baseType: string, round: number)
	local base = ENEMY_TYPES[baseType]
	assert(base, "Unknown enemy type: " .. baseType)
	local scale = 1 + (round - 1) * 0.08 -- 8% stronger per round
	return {
		name     = base.name,
		health   = math.floor(base.health * scale),
		speed    = base.speed + round * 0.02, -- very slight speed creep
		reward   = base.reward,
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

	-- Scale enemy count with round
	local baseCount = math.floor(5 + round * 1.5)

	if isBossRound then
		-- Boss wave: fewer normal enemies + 1 boss
		local normalCount = math.floor(baseCount * 0.5)
		table.insert(enemies, { enemyType="Grunt",  count=normalCount, interval=0.8 })
		table.insert(enemies, { enemyType=getBossType(round), count=1, interval=0 })
	else
		-- Normal wave: mix of enemy types based on round progression
		if round < 5 then
			table.insert(enemies, { enemyType="Grunt", count=baseCount, interval=1.0 })
		elseif round < 15 then
			table.insert(enemies, { enemyType="Grunt",  count=math.floor(baseCount*0.6), interval=1.0 })
			table.insert(enemies, { enemyType="Runner", count=math.floor(baseCount*0.4), interval=0.7 })
		elseif round < 30 then
			table.insert(enemies, { enemyType="Grunt",  count=math.floor(baseCount*0.4), interval=0.9 })
			table.insert(enemies, { enemyType="Runner", count=math.floor(baseCount*0.3), interval=0.6 })
			table.insert(enemies, { enemyType="Brute",  count=math.floor(baseCount*0.3), interval=1.5 })
		elseif round < 60 then
			table.insert(enemies, { enemyType="Runner",  count=math.floor(baseCount*0.3), interval=0.6 })
			table.insert(enemies, { enemyType="Brute",   count=math.floor(baseCount*0.3), interval=1.2 })
			table.insert(enemies, { enemyType="Swarm",   count=math.floor(baseCount*0.4), interval=0.3 })
		else
			table.insert(enemies, { enemyType="Brute",   count=math.floor(baseCount*0.3), interval=1.0 })
			table.insert(enemies, { enemyType="Swarm",   count=math.floor(baseCount*0.3), interval=0.3 })
			table.insert(enemies, { enemyType="Armored", count=math.floor(baseCount*0.4), interval=1.2 })
		end
	end

	return {
		round       = round,
		enemies     = enemies,
		isBossRound = isBossRound,
	}
end

return {
	ENEMY_TYPES   = ENEMY_TYPES,
	scaleEnemy    = scaleEnemy,
	generateWave  = generateWave,
	getBossType   = getBossType,
}
