-- TurretData.luau
-- Shared turret type definitions: stats, prices, upgrade multipliers
-- Each turret is a fixed-stat blueprint (not combo-based)

export type TurretType = {
	id: number,
	name: string,
	description: string,
	damage: number,
	range: number,
	fireRate: number,
	shopPrice: number,
	placementCost: number,
	upgradeMultipliers: {
		damage: number,
		range: number,
		fireRate: number,
	},
	supportType: string?, -- nil = combat, "money" = coin gen, "health" = base heal
	supportValue: number?, -- coins per tick or HP per tick
	supportInterval: number?, -- seconds between ticks
}

local Turrets: { TurretType } = {
	{
		id = 1,
		name = "Scout Turret",
		description = "A basic turret with balanced stats. Free for all players.",
		damage = 10,       -- 10 × 2.0 = 20 DPS
		range = 20,
		fireRate = 2.0,
		shopPrice = 0,
		placementCost = 50,
		upgradeMultipliers = { damage = 1.2, range = 1.05, fireRate = 1.05 },
	},
	{
		id = 2,
		name = "Marksman Turret",
		description = "Long-range precision turret with high damage per shot.",
		damage = 30,       -- 30 × 1.2 = 36 DPS, long range sniper
		range = 28,
		fireRate = 1.2,
		shopPrice = 1000,
		placementCost = 100,
		upgradeMultipliers = { damage = 1.35, range = 1.1, fireRate = 1.1 },
	},
	{
		id = 3,
		name = "Rapid Turret",
		description = "Fast-firing turret that overwhelms enemies with volume.",
		damage = 6,        -- 6 × 6.0 = 36 DPS, short range shredder
		range = 14,
		fireRate = 6.0,
		shopPrice = 10000,
		placementCost = 80,
		upgradeMultipliers = { damage = 1.25, range = 1.05, fireRate = 1.2 },
	},
	{
		id = 4,
		name = "Cannon Turret",
		description = "Slow but devastating. Each shot hits like a truck.",
		damage = 80,       -- 80 × 0.6 = 48 DPS, boss killer
		range = 18,
		fireRate = 0.6,
		shopPrice = 100000,
		placementCost = 150,
		upgradeMultipliers = { damage = 1.4, range = 1.1, fireRate = 1.05 },
	},
	{
		id = 5,
		name = "Frost Turret",
		description = "Chills enemies with icy blasts, slowing them down.",
		damage = 15,       -- 15 × 2.5 = 37.5 DPS + slow effect
		range = 22,
		fireRate = 2.5,
		shopPrice = 1000000,
		placementCost = 120,
		upgradeMultipliers = { damage = 1.3, range = 1.15, fireRate = 1.15 },
	},
	{
		id = 6,
		name = "Tesla Turret",
		description = "Electrifies the battlefield with arcing bolts of lightning.",
		damage = 40,       -- 40 × 3.0 = 120 DPS, endgame powerhouse
		range = 22,
		fireRate = 3.0,
		shopPrice = 10000000,
		placementCost = 200,
		upgradeMultipliers = { damage = 1.35, range = 1.1, fireRate = 1.15 },
	},
	{
		id = 7,
		name = "Coin Printer",
		description = "Generates session coins over time. More money, more turrets.",
		damage = 0,
		range = 0,
		fireRate = 0,
		shopPrice = 500,
		placementCost = 80,
		upgradeMultipliers = { damage = 1.5, range = 1, fireRate = 1 },
		supportType = "money",
		supportValue = 5,
		supportInterval = 4,
	},
	{
		id = 8,
		name = "Medic Station",
		description = "Slowly restores base health each wave. Keep your base alive.",
		damage = 0,
		range = 0,
		fireRate = 0,
		shopPrice = 2000,
		placementCost = 120,
		upgradeMultipliers = { damage = 1.4, range = 1, fireRate = 1 },
		supportType = "health",
		supportValue = 1,
		supportInterval = 8,
	},
}

-- Lookup table for fast id-based access
local TurretsById: { [number]: TurretType } = {}
for _, turret in Turrets do
	TurretsById[turret.id] = turret
end

local function getTurretById(id: number): TurretType?
	return TurretsById[id]
end

local function getAllTurrets(): { TurretType }
	return Turrets
end

return {
	getTurretById = getTurretById,
	getAllTurrets = getAllTurrets,
	Turrets = Turrets,
}
