-- Types.luau
-- Shared type definitions across client and server

export type ResourceId = number -- 1..10

export type Resource = {
	id: ResourceId,
	name: string,
	color: Color3,
	hint: string, -- flavor hint for players
}

export type TowerCombo = {
	resources: { ResourceId }, -- sorted list of resource ids used
	name: string,
	description: string,
	damage: number,
	range: number,
	fireRate: number, -- attacks per second
	slowFactor: number, -- 1 = no slow, 0.5 = half speed
	aoeRadius: number, -- 0 = single target
	cursed: boolean, -- bad effect tower
	special: string?, -- optional special tag e.g. "burn", "freeze", "chain"
}

export type EnemyType = {
	name: string,
	health: number,
	speed: number,
	reward: number, -- money on kill
	isBoss: boolean,
	size: number, -- scale multiplier
}

export type WaveConfig = {
	round: number,
	enemies: { { enemyType: string, count: number, interval: number } },
	isBossRound: boolean,
}

export type PlayerState = {
	userId: number,
	money: number,
	resources: { [ResourceId]: number }, -- count per resource
}

export type TowerInstance = {
	id: string,
	comboKey: string,
	gridX: number,
	gridZ: number,
	ownerId: number,
}

return {}
