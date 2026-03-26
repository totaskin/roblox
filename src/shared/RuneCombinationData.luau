-- RuneCombinationData.luau
-- Shared rune combination data: single-rune effects, pair synergies/clashes,
-- triple combos, and utility functions for computing combined stat multipliers.
-- Used by both server (RuneManager) and client (RuneHUD preview).
--
-- Design philosophy:
-- - Single runes: modest bonuses, some with tradeoffs
-- - 2-rune synergies: ~20% of pairs are good (9 out of 45), nice boost
-- - 2-rune clashes: ~35% of pairs are bad (16 out of 45), penalties
-- - 3-rune legendary combos: very rare, very powerful (only 5 exist)

local RuneCombinationData = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Single-Rune Effects
-- Each rune type grants stat multipliers and/or a special effect.
-- Missing stat keys default to 1.0 (no change).
-- Some runes have tradeoffs (boost one stat, reduce another).
-- ═══════════════════════════════════════════════════════════════════════════

RuneCombinationData.SingleEffects = {
	[1] = { -- Ember: fire damage, slightly slower
		damage = 1.12,
		fireRate = 0.95,
	},
	[2] = { -- Frost: slow effect, reduced damage
		damage = 0.9,
		special = "slow",
		specialParams = { factor = 0.5, duration = 3 }, -- 50% slow for 3 seconds
	},
	[3] = { -- Spark: fast attacks, less damage
		fireRate = 1.15,
		damage = 0.92,
	},
	[4] = { -- Spore: poison DoT, reduced range
		range = 0.9,
		special = "poison",
		specialParams = { damagePerSecond = 3, duration = 4 },
	},
	[5] = { -- Shadow: crit chance, reduced range
		range = 0.92,
		special = "critChance",
		specialParams = { chance = 0.1, multiplier = 2 },
	},
	[6] = { -- Radiance: range boost, slower attacks
		range = 1.15,
		fireRate = 0.93,
	},
	[7] = { -- Stone: big range, much slower
		range = 1.2,
		fireRate = 0.85,
	},
	[8] = { -- Gale: balanced speed and range
		fireRate = 1.08,
		range = 1.05,
	},
	[9] = { -- Arcane: balanced damage and speed
		damage = 1.1,
		fireRate = 1.05,
	},
	[10] = { -- Void: high damage, very slow
		damage = 1.25,
		fireRate = 0.8,
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Pair Effects (Synergies and Clashes)
-- Keyed by canonical pair key "min_max" for consistent lookup.
-- 
-- Out of 45 possible pairs:
-- - 9 synergies (~20%): good combos, nice boosts
-- - 16 clashes (~35%): bad combos, penalties
-- - 20 neutral (~45%): no special interaction
-- ═══════════════════════════════════════════════════════════════════════════

RuneCombinationData.PairEffects = {
	-- ═══ SYNERGIES (9 total - ~20% of pairs) ═══
	-- These are the "good" 2-rune combos players should discover
	
	["1_3"] = { type = "synergy", damage = 1.25, fireRate = 1.1 },         -- Ember + Spark = "Inferno"
	["2_7"] = { type = "synergy", range = 1.3, damage = 1.1 },             -- Frost + Stone = "Glacier"
	["4_6"] = { type = "synergy", range = 1.25, damage = 1.15 },           -- Spore + Radiance = "Bloom"
	["5_10"] = { type = "synergy", damage = 1.35 },                        -- Shadow + Void = "Abyss"
	["8_9"] = { type = "synergy", fireRate = 1.2, damage = 1.15 },         -- Gale + Arcane = "Storm"
	["1_9"] = { type = "synergy", damage = 1.3 },                          -- Ember + Arcane = "Hellfire"
	["3_8"] = { type = "synergy", fireRate = 1.25 },                       -- Spark + Gale = "Lightning"
	["2_4"] = { type = "synergy", damage = 1.2 },                          -- Frost + Spore = "Blight"
	["6_7"] = { type = "synergy", range = 1.35 },                          -- Radiance + Stone = "Beacon"

	-- ═══ CLASHES (16 total - ~35% of pairs) ═══
	-- These are "bad" combos that reduce effectiveness
	
	["1_2"] = { type = "clash", damage = 0.75, fireRate = 0.9 },           -- Ember + Frost = cancel out
	["5_6"] = { type = "clash", damage = 0.8, range = 0.85 },              -- Shadow + Radiance = oppose
	["4_10"] = { type = "clash", fireRate = 0.8, damage = 0.85 },          -- Spore + Void = corrupt
	["3_7"] = { type = "clash", fireRate = 0.75 },                         -- Spark + Stone = grounded
	["1_4"] = { type = "clash", damage = 0.85 },                           -- Ember + Spore = burn spores
	["2_3"] = { type = "clash", fireRate = 0.85, damage = 0.9 },           -- Frost + Spark = freeze circuits
	["5_8"] = { type = "clash", range = 0.85 },                            -- Shadow + Gale = disperse
	["6_10"] = { type = "clash", damage = 0.8 },                           -- Radiance + Void = annihilate
	["7_8"] = { type = "clash", fireRate = 0.8, range = 0.9 },             -- Stone + Gale = heavy winds
	["1_7"] = { type = "clash", fireRate = 0.8 },                          -- Ember + Stone = smothered
	["2_9"] = { type = "clash", damage = 0.85 },                           -- Frost + Arcane = frozen magic
	["3_10"] = { type = "clash", fireRate = 0.75, damage = 0.9 },          -- Spark + Void = absorbed
	["4_5"] = { type = "clash", range = 0.8 },                             -- Spore + Shadow = wither
	["6_8"] = { type = "clash", fireRate = 0.85 },                         -- Radiance + Gale = scattered light
	["9_10"] = { type = "clash", fireRate = 0.7 },                         -- Arcane + Void = unstable
	["2_5"] = { type = "clash", damage = 0.85, range = 0.9 },              -- Frost + Shadow = cold darkness
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Triple Combos (Legendary - very rare, very powerful)
-- Only 5 legendary 3-rune combos exist out of 120 possible combinations.
-- These give massive bonuses when all 3 specific runes are combined.
-- ═══════════════════════════════════════════════════════════════════════════

RuneCombinationData.TripleEffects = {
	-- Key format: "a_b_c" where a < b < c (sorted)
	["1_3_9"] = {  -- Ember + Spark + Arcane = "Phoenix"
		name = "Phoenix",
		damage = 1.5,
		fireRate = 1.3,
	},
	["2_7_6"] = {  -- Frost + Radiance + Stone = "Aurora" (sorted: 2_6_7)
		name = "Aurora",
		range = 1.6,
		damage = 1.2,
	},
	["5_10_4"] = { -- Shadow + Void + Spore = "Plague" (sorted: 4_5_10)
		name = "Plague",
		damage = 1.6,
		special = "megaPoison",
		specialParams = { damagePerSecond = 8, duration = 6 },
	},
	["3_8_6"] = {  -- Spark + Gale + Radiance = "Supernova" (sorted: 3_6_8)
		name = "Supernova",
		fireRate = 1.5,
		range = 1.3,
	},
	["1_9_10"] = { -- Ember + Arcane + Void = "Oblivion" (sorted: 1_9_10)
		name = "Oblivion",
		damage = 1.8,
		fireRate = 0.9,
	},
}

-- Corrected triple keys (must be sorted a < b < c)
RuneCombinationData.TripleEffectsSorted = {
	["1_3_9"] = RuneCombinationData.TripleEffects["1_3_9"],   -- Phoenix
	["2_6_7"] = {  -- Aurora (corrected sort)
		name = "Aurora",
		range = 1.6,
		damage = 1.2,
	},
	["4_5_10"] = { -- Plague (corrected sort)
		name = "Plague",
		damage = 1.6,
		special = "megaPoison",
		specialParams = { damagePerSecond = 8, duration = 6 },
	},
	["3_6_8"] = {  -- Supernova (corrected sort)
		name = "Supernova",
		fireRate = 1.5,
		range = 1.3,
	},
	["1_9_10"] = RuneCombinationData.TripleEffects["1_9_10"], -- Oblivion
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Utility Functions
-- ═══════════════════════════════════════════════════════════════════════════

-- Returns the single-rune effect for a given rune type id.
function RuneCombinationData.getSingleEffect(runeTypeId: number): {
	damage: number,
	range: number,
	fireRate: number,
	special: string?,
	specialParams: { [string]: number }?,
}
	local effect = RuneCombinationData.SingleEffects[runeTypeId]
	if not effect then
		return { damage = 1, range = 1, fireRate = 1 }
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
function RuneCombinationData.getPairEffect(runeTypeA: number, runeTypeB: number): {
	type: string,
	damage: number,
	range: number,
	fireRate: number,
}
	if runeTypeA == runeTypeB then
		return { type = "neutral", damage = 1, range = 1, fireRate = 1 }
	end

	local minId = math.min(runeTypeA, runeTypeB)
	local maxId = math.max(runeTypeA, runeTypeB)
	local key = tostring(minId) .. "_" .. tostring(maxId)

	local effect = RuneCombinationData.PairEffects[key]
	if not effect then
		return { type = "neutral", damage = 1, range = 1, fireRate = 1 }
	end

	return {
		type = effect.type,
		damage = effect.damage or 1,
		range = effect.range or 1,
		fireRate = effect.fireRate or 1,
	}
end

-- Returns the triple effect for three rune types, or nil if no legendary combo.
function RuneCombinationData.getTripleEffect(runeA: number, runeB: number, runeC: number): {
	name: string,
	damage: number,
	range: number,
	fireRate: number,
	special: string?,
	specialParams: { [string]: number }?,
}?
	-- Sort the three runes
	local sorted = { runeA, runeB, runeC }
	table.sort(sorted)
	local key = tostring(sorted[1]) .. "_" .. tostring(sorted[2]) .. "_" .. tostring(sorted[3])

	local effect = RuneCombinationData.TripleEffectsSorted[key]
	if not effect then
		return nil
	end

	return {
		name = effect.name,
		damage = effect.damage or 1,
		range = effect.range or 1,
		fireRate = effect.fireRate or 1,
		special = effect.special,
		specialParams = effect.specialParams,
	}
end

-- Computes combined stat multipliers for a turret's rune slot.
-- Priority: Triple combo > Pair effects + Single effects
function RuneCombinationData.computeCombinedMultipliers(runeSlot: { number }): {
	damage: number,
	range: number,
	fireRate: number,
	specials: { { special: string, specialParams: { [string]: number }? } },
	legendaryCombo: string?,
}
	local result = {
		damage = 1,
		range = 1,
		fireRate = 1,
		specials = {} :: { { special: string, specialParams: { [string]: number }? } },
		legendaryCombo = nil :: string?,
	}

	if not runeSlot or #runeSlot == 0 then
		return result
	end

	-- Check for legendary triple combo first (if 3 runes)
	if #runeSlot == 3 then
		local tripleEffect = RuneCombinationData.getTripleEffect(runeSlot[1], runeSlot[2], runeSlot[3])
		if tripleEffect then
			-- Legendary combo overrides normal calculation with big bonuses
			result.damage = tripleEffect.damage
			result.range = tripleEffect.range
			result.fireRate = tripleEffect.fireRate
			result.legendaryCombo = tripleEffect.name

			if tripleEffect.special then
				table.insert(result.specials, {
					special = tripleEffect.special,
					specialParams = tripleEffect.specialParams,
				})
			end

			-- Still add single-rune specials (slow, poison, crit)
			for _, runeTypeId in ipairs(runeSlot) do
				local singleEffect = RuneCombinationData.getSingleEffect(runeTypeId)
				if singleEffect.special then
					table.insert(result.specials, {
						special = singleEffect.special,
						specialParams = singleEffect.specialParams,
					})
				end
			end

			return result
		end
	end

	-- Normal calculation: single effects + pair effects
	-- Step 1: Apply single-rune effects (multiplicative)
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

	-- Step 2: Apply pair effects for each unique pair (i < j)
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
