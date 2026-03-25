-- ResourceData.luau
-- Defines the 10 resource types with themes, colors and hints

local Resources = {
	[1]  = { id = 1,  name = "Ember",    color = Color3.fromRGB(255, 80,  20),  hint = "Burns with fierce heat. Fire-based effects." },
	[2]  = { id = 2,  name = "Frost",    color = Color3.fromRGB(100, 200, 255), hint = "Chills everything it touches. Ice-based effects." },
	[3]  = { id = 3,  name = "Spark",    color = Color3.fromRGB(255, 240, 50),  hint = "Crackles with energy. Lightning-based effects." },
	[4]  = { id = 4,  name = "Spore",    color = Color3.fromRGB(80,  200, 80),  hint = "Grows and spreads. Nature-based effects." },
	[5]  = { id = 5,  name = "Shadow",   color = Color3.fromRGB(60,  20,  80),  hint = "Drains and corrupts. Dark-based effects." },
	[6]  = { id = 6,  name = "Radiance", color = Color3.fromRGB(255, 255, 180), hint = "Purifies and empowers. Light-based effects." },
	[7]  = { id = 7,  name = "Stone",    color = Color3.fromRGB(140, 110, 80),  hint = "Sturdy and grounding. Earth-based effects." },
	[8]  = { id = 8,  name = "Gale",     color = Color3.fromRGB(180, 230, 255), hint = "Swift and unpredictable. Wind-based effects." },
	[9]  = { id = 9,  name = "Arcane",   color = Color3.fromRGB(180, 80,  255), hint = "Raw magical force. Arcane-based effects." },
	[10] = { id = 10, name = "Void",     color = Color3.fromRGB(10,  10,  30),  hint = "Tears reality apart. Void-based effects. Very rare." },
}

-- Returns the weighted resource drop based on total boss kills
-- Boss 1:    Ember ~50%, Void ~0.1%
-- Boss 1000: Distribution flattens, Void ~10%
local BASE_WEIGHT  = { 50, 20, 12, 7, 4, 3, 2, 1.5, 0.4, 0.1 }
local FINAL_WEIGHT = { 15, 15, 13, 12, 11, 10, 9, 8, 7, 10 }
local MAX_BOSS_KILLS = 1000

local function getDropWeights(bossKillCount: number): { number }
	local t = math.clamp(bossKillCount / MAX_BOSS_KILLS, 0, 1)
	local weights = {}
	for i = 1, 10 do
		weights[i] = BASE_WEIGHT[i] + (FINAL_WEIGHT[i] - BASE_WEIGHT[i]) * t
	end
	return weights
end

-- Picks a random resource id based on total boss kills
local function rollResourceDrop(bossKillCount: number): number
	local weights = getDropWeights(bossKillCount)
	local total = 0
	for _, w in ipairs(weights) do total += w end

	local roll = math.random() * total
	local cumulative = 0
	for i, w in ipairs(weights) do
		cumulative += w
		if roll <= cumulative then
			return i
		end
	end
	return 10 -- fallback
end

return {
	Resources = Resources,
	getDropWeights = getDropWeights,
	rollResourceDrop = rollResourceDrop,
}
