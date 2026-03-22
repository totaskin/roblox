-- TowerData.luau
-- Combo recipes: sorted resource id lists map to tower effects
-- Combos can be 1..5 resources. Key is ids sorted and joined by "_"

local function makeKey(ids: { number }): string
	local sorted = table.clone(ids)
	table.sort(sorted)
	return table.concat(sorted, "_")
end

-- damage/range/fireRate are multipliers on the base tower stats
-- base: damage=10, range=20, fireRate=1
local Combos = {
	-- Single resource towers (basic)
	[makeKey({1})]  = { name="Ember Tower",     damage=1.2, range=1.0, fireRate=1.0, slowFactor=1.0, aoeRadius=0,  cursed=false, special="burn",   description="Sets enemies on fire, dealing damage over time." },
	[makeKey({2})]  = { name="Frost Tower",     damage=0.8, range=1.1, fireRate=0.9, slowFactor=0.6, aoeRadius=0,  cursed=false, special="freeze", description="Slows enemies significantly." },
	[makeKey({3})]  = { name="Spark Tower",     damage=1.0, range=1.2, fireRate=1.5, slowFactor=1.0, aoeRadius=0,  cursed=false, special="chain",  description="Chains lightning to nearby enemies." },
	[makeKey({4})]  = { name="Spore Tower",     damage=0.7, range=1.0, fireRate=1.2, slowFactor=0.8, aoeRadius=3,  cursed=false, special="poison", description="Poisons enemies in a small area." },
	[makeKey({5})]  = { name="Shadow Tower",    damage=1.5, range=0.8, fireRate=0.8, slowFactor=1.0, aoeRadius=0,  cursed=false, special="drain",  description="Drains enemy health and heals the base slightly." },
	[makeKey({6})]  = { name="Radiance Tower",  damage=0.9, range=1.3, fireRate=1.0, slowFactor=1.0, aoeRadius=5,  cursed=false, special="holy",   description="Deals bonus damage to bosses." },
	[makeKey({7})]  = { name="Stone Tower",     damage=1.3, range=0.9, fireRate=0.7, slowFactor=1.0, aoeRadius=0,  cursed=false, special="stun",   description="Chance to stun enemies briefly." },
	[makeKey({8})]  = { name="Gale Tower",      damage=0.6, range=1.5, fireRate=1.8, slowFactor=1.0, aoeRadius=0,  cursed=false, special="push",   description="Pushes enemies back along the path." },
	[makeKey({9})]  = { name="Arcane Tower",    damage=1.4, range=1.1, fireRate=1.1, slowFactor=1.0, aoeRadius=0,  cursed=false, special="amplify",description="Amplifies damage from nearby towers." },
	[makeKey({10})] = { name="Void Tower",      damage=2.0, range=1.0, fireRate=0.6, slowFactor=1.0, aoeRadius=0,  cursed=false, special="void",   description="Instantly kills weak enemies. Rare and powerful." },

	-- Two-resource combos
	[makeKey({1,2})]  = { name="Steam Tower",     damage=1.1, range=1.1, fireRate=1.2, slowFactor=0.8, aoeRadius=4,  cursed=false, special="steam",  description="Scalding steam slows and damages in an area." },
	[makeKey({1,3})]  = { name="Plasma Tower",    damage=1.8, range=1.0, fireRate=1.0, slowFactor=1.0, aoeRadius=0,  cursed=false, special="burn",   description="Superheated plasma melts through armor." },
	[makeKey({1,5})]  = { name="Hellfire Tower",  damage=2.2, range=0.9, fireRate=0.8, slowFactor=1.0, aoeRadius=6,  cursed=false, special="burn",   description="Rains hellfire on a wide area." },
	[makeKey({2,8})]  = { name="Blizzard Tower",  damage=0.9, range=1.4, fireRate=0.8, slowFactor=0.4, aoeRadius=8,  cursed=false, special="freeze", description="Freezes all enemies in a large radius." },
	[makeKey({3,8})]  = { name="Storm Tower",     damage=1.3, range=1.3, fireRate=1.4, slowFactor=1.0, aoeRadius=5,  cursed=false, special="chain",  description="Calls down storms hitting multiple enemies." },
	[makeKey({5,10})] = { name="Abyss Tower",     damage=2.5, range=0.8, fireRate=0.7, slowFactor=1.0, aoeRadius=0,  cursed=false, special="void",   description="Tears enemies into the void. Extremely powerful." },
	[makeKey({6,9})]  = { name="Arclight Tower",  damage=1.6, range=1.4, fireRate=1.2, slowFactor=1.0, aoeRadius=3,  cursed=false, special="holy",   description="Blasts of holy arcane energy." },
	[makeKey({4,7})]  = { name="Overgrowth Tower",damage=1.0, range=1.0, fireRate=1.0, slowFactor=0.7, aoeRadius=5,  cursed=false, special="root",   description="Roots enemies in place briefly." },

	-- Cursed / bad combos
	[makeKey({5,6})]  = { name="Cursed Tower",    damage=0.3, range=0.7, fireRate=0.5, slowFactor=1.0, aoeRadius=0,  cursed=true,  special=nil,      description="Shadow and Light cancel each other. Nearly useless." },
	[makeKey({1,4})]  = { name="Ash Tower",       damage=0.5, range=0.8, fireRate=0.6, slowFactor=1.0, aoeRadius=0,  cursed=true,  special=nil,      description="Fire burns the spores away. Weak and smoky." },
	[makeKey({2,3})]  = { name="Short Circuit",   damage=0.4, range=0.6, fireRate=0.4, slowFactor=1.0, aoeRadius=0,  cursed=true,  special=nil,      description="Ice shorts the lightning. Barely functional." },
	[makeKey({7,8})]  = { name="Dust Tower",      damage=0.6, range=0.7, fireRate=0.7, slowFactor=1.0, aoeRadius=0,  cursed=true,  special=nil,      description="Wind scatters the stones. Disappointing." },

	-- Three-resource combos
	[makeKey({1,2,3})]   = { name="Tempest Tower",   damage=2.0, range=1.3, fireRate=1.3, slowFactor=0.7, aoeRadius=6,  cursed=false, special="chain",  description="Fire, ice and lightning combine into a raging tempest." },
	[makeKey({4,6,9})]   = { name="Life Tower",      damage=1.2, range=1.5, fireRate=1.0, slowFactor=0.8, aoeRadius=4,  cursed=false, special="holy",   description="Nature, light and arcane sustain allies and punish enemies." },
	[makeKey({5,9,10})]  = { name="Oblivion Tower",  damage=3.0, range=1.0, fireRate=0.6, slowFactor=1.0, aoeRadius=0,  cursed=false, special="void",   description="Shadow, arcane and void obliterate single targets." },
	[makeKey({1,3,8})]   = { name="Firestorm Tower", damage=2.3, range=1.2, fireRate=1.2, slowFactor=1.0, aoeRadius=7,  cursed=false, special="burn",   description="A spinning vortex of fire and lightning." },
	[makeKey({2,7,4})]   = { name="Glacier Tower",   damage=1.5, range=1.1, fireRate=0.8, slowFactor=0.3, aoeRadius=6,  cursed=false, special="freeze", description="Encases enemies in ice and stone." },

	-- Four-resource combos
	[makeKey({1,2,3,8})] = { name="Hurricane Tower", damage=2.5, range=1.5, fireRate=1.4, slowFactor=0.6, aoeRadius=10, cursed=false, special="chain",  description="A massive elemental hurricane." },
	[makeKey({5,6,9,10})]= { name="Eclipse Tower",   damage=3.5, range=1.2, fireRate=0.8, slowFactor=1.0, aoeRadius=5,  cursed=false, special="void",   description="Light and dark collapse into a singularity." },
	[makeKey({1,4,5,6})] = { name="Chaos Tower",     damage=0.1, range=2.0, fireRate=3.0, slowFactor=1.0, aoeRadius=15, cursed=true,  special=nil,      description="Chaotic energies fire wildly, hitting allies too. Dangerous." },

	-- Five-resource combos (rare, powerful or cursed)
	[makeKey({1,2,3,4,5})]    = { name="Primal Tower",    damage=4.0, range=1.4, fireRate=1.2, slowFactor=0.5, aoeRadius=8,  cursed=false, special="burn",   description="The five primal forces united. Devastating." },
	[makeKey({6,7,8,9,10})]   = { name="Ascendant Tower", damage=4.5, range=1.5, fireRate=1.0, slowFactor=0.4, aoeRadius=10, cursed=false, special="holy",   description="Transcendent power. Slows and destroys all in range." },
	[makeKey({1,3,5,7,9})]    = { name="Odd Tower",       damage=2.0, range=1.0, fireRate=2.0, slowFactor=1.0, aoeRadius=3,  cursed=false, special="amplify",description="Odd-numbered resources resonate strangely but effectively." },
	[makeKey({2,4,6,8,10})]   = { name="Even Tower",      damage=1.5, range=2.0, fireRate=0.8, slowFactor=0.5, aoeRadius=12, cursed=false, special="freeze", description="Even-numbered resources spread wide and slow everything." },
	[makeKey({1,2,3,4,10})]   = { name="Cursed Primal",   damage=0.5, range=0.5, fireRate=0.5, slowFactor=1.0, aoeRadius=0,  cursed=true,  special=nil,      description="Void corrupts the primal elements. A terrible mistake." },
	[makeKey({5,6,7,8,9})]    = { name="Null Tower",      damage=0.0, range=1.0, fireRate=1.0, slowFactor=1.0, aoeRadius=0,  cursed=true,  special=nil,      description="These forces annihilate each other. Does nothing." },
}

-- Fallback for unknown combos
local DEFAULT_COMBO = {
	name="Basic Tower", damage=1.0, range=1.0, fireRate=1.0,
	slowFactor=1.0, aoeRadius=0, cursed=false, special=nil,
	description="A plain tower with no special properties."
}

local BASE_STATS = { damage=10, range=20, fireRate=1 }

local function getCombo(resourceIds: { number })
	local key = makeKey(resourceIds)
	return Combos[key] or DEFAULT_COMBO
end

local function resolveStats(resourceIds: { number })
	local combo = getCombo(resourceIds)
	return {
		name        = combo.name,
		description = combo.description,
		cursed      = combo.cursed,
		special     = combo.special,
		slowFactor  = combo.slowFactor,
		aoeRadius   = combo.aoeRadius * BASE_STATS.range / 20, -- scale with range base
		damage      = BASE_STATS.damage  * combo.damage,
		range       = BASE_STATS.range   * combo.range,
		fireRate    = BASE_STATS.fireRate * combo.fireRate,
	}
end

return {
	makeKey      = makeKey,
	getCombo     = getCombo,
	resolveStats = resolveStats,
	Combos       = Combos,
	BASE_STATS   = BASE_STATS,
}
