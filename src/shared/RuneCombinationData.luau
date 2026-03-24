-- RuneCombinationData.luau
-- Shared rune combination data: single-rune effects, pair synergies/clashes,
-- and utility functions for computing combined stat multipliers.
-- Used by both server (RuneManager) and client (RuneHUD preview).

local RuneCombinationData = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Single-Rune Effects
-- Each rune type grants stat multipliers and/or a special effect.
-- Missing stat keys default to 1.0 (no change).
-- ═══════════════════════════════════════════════════════════════════════════

RuneCombinationData.SingleEffects = {
	[1] = { -- Ember
		damage = 1.15,
	},
	[2] = { -- Frost
		special = "slow",
		specialParams = { factor = 0.7, duration = 2 },
	},
	[3] = { -- Spark
		fireRate = 1.2,
	},
	[4] = { -- Spore
		special = "poison",
		specialParams = { damagePerSecond = 3, duration = 4 },
	},
	[5] = { -- Shadow
		damage = 1.1,
		special = "critChance",
		specialParams = { chance = 0.1, multiplier = 2 },
	},
	[6] = { -- Radiance
		range = 1.1,
		damage = 1.05,
	},
	[7] = { -- Stone
		range = 1.25,
	},
	[8] = { -- Gale
		fireRate = 1.15,
		range = 1.05,
	},
	[9] = { -- Arcane
		damage = 1.2,
		fireRate = 1.1,
	},
	[10] = { -- Void
		damage = 1.3,
		fireRate = 0.9,
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Pair Effects (Synergies and Clashes)
-- Keyed by canonical pair key "min_max" for consistent lookup.
-- ═══════════════════════════════════════════════════════════════════════════

RuneCombinationData.PairEffects = {
	-- Synergies
	["1_3"] = { type = "synergy", damage = 1.2 },                          -- Ember + Spark
	["2_8"] = { type = "synergy", range = 1.15, fireRate = 1.1 },          -- Frost + Gale
	["4_6"] = { type = "synergy", range = 1.2 },                           -- Spore + Radiance
	["5_10"] = { type = "synergy", damage = 1.25 },                        -- Shadow + Void
	["7_9"] = { type = "synergy", damage = 1.15, range = 1.1 },            -- Stone + Arcane

	-- Clashes
	["1_2"] = { type = "clash", damage = 0.85 },                           -- Ember + Frost
	["5_6"] = { type = "clash", damage = 0.85 },                           -- Shadow + Radiance
	["4_10"] = { type = "clash", fireRate = 0.9 },                         -- Spore + Void
	["3_7"] = { type = "clash", fireRate = 0.9 },                          -- Spark + Stone
	["7_8"] = { type = "clash", range = 0.9 },                             -- Gale + Stone
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Utility Functions
-- ═══════════════════════════════════════════════════════════════════════════

-- Returns the single-rune effect for a given rune type id.
-- Falls back to default (all 1.0 multipliers) for unknown ids.
function RuneCombinationData.getSingleEffect(runeTypeId: number): {
	damage: number,
	range: number,
	fireRate: number,
	special: string?,
	specialParams: { [string]: number }?,
}
	local effect = RuneCombinationData.SingleEffects[runeTypeId]
	if not effect then
		return {
			damage = 1,
			range = 1,
			fireRate = 1,
		}
	end

	return {
		damage = effect.damage or 1,
		range = effect.range or 1,
		fireRate = effect.fireRate or 1,
		special = effect.special,
		specialParams = effect.specialParams,
	}
end

-- Returns the pair effect for two rune types using canonical key ordering.
-- Falls back to neutral default for unknown or same-type pairs.
function RuneCombinationData.getPairEffect(runeTypeA: number, runeTypeB: number): {
	type: string,
	damage: number,
	range: number,
	fireRate: number,
}
	if runeTypeA == runeTypeB then
		return {
			type = "neutral",
			damage = 1,
			range = 1,
			fireRate = 1,
		}
	end

	local minId = math.min(runeTypeA, runeTypeB)
	local maxId = math.max(runeTypeA, runeTypeB)
	local key = tostring(minId) .. "_" .. tostring(maxId)

	local effect = RuneCombinationData.PairEffects[key]
	if not effect then
		return {
			type = "neutral",
			damage = 1,
			range = 1,
			fireRate = 1,
		}
	end

	return {
		type = effect.type,
		damage = effect.damage or 1,
		range = effect.range or 1,
		fireRate = effect.fireRate or 1,
	}
end

-- Computes combined stat multipliers for a turret's rune slot.
-- 1. Start with base multipliers { damage = 1, range = 1, fireRate = 1, specials = {} }
-- 2. For each rune occurrence, multiply by its single-rune stat multipliers (stacks multiplicatively)
-- 3. For each unique pair (i < j), look up pair effect and multiply
-- 4. Return the combined result
function RuneCombinationData.computeCombinedMultipliers(runeSlot: { number }): {
	damage: number,
	range: number,
	fireRate: number,
	specials: { { special: string, specialParams: { [string]: number }? } },
}
	local result = {
		damage = 1,
		range = 1,
		fireRate = 1,
		specials = {} :: { { special: string, specialParams: { [string]: number }? } },
	}

	if not runeSlot or #runeSlot == 0 then
		return result
	end

	-- Step 2: Apply single-rune effects for each rune occurrence (multiplicative stacking)
	for _, runeTypeId in ipairs(runeSlot) do
		local effect = RuneCombinationData.getSingleEffect(runeTypeId)
		result.damage *= effect.damage
		result.range *= effect.range
		result.fireRate *= effect.fireRate

		if effect.special then
			table.insert(result.specials, {
				special = effect.special,
				specialParams = effect.specialParams,
			})
		end
	end

	-- Step 3: Apply pair effects for each unique pair (i < j)
	for i = 1, #runeSlot - 1 do
		for j = i + 1, #runeSlot do
			local pairEffect = RuneCombinationData.getPairEffect(runeSlot[i], runeSlot[j])
			result.damage *= pairEffect.damage
			result.range *= pairEffect.range
			result.fireRate *= pairEffect.fireRate
		end
	end

	return result
end

return RuneCombinationData
