-- EnemyPath.luau
-- Waypoint paths for each map. Enemies follow these in order.
-- Coordinates are world-space Vector3 positions.
-- Maps have winding paths with different lengths and layouts.

local Maps = {
	-- Map 1: Classic S-curve
	Map1 = {
		name = "Greenfield",
		gridSize = Vector3.new(200, 0, 200),
		-- 50 tower grid spots defined as {x, z} offsets from map origin
		towerSlots = {
			{-60,20},{-60,40},{-60,60},{-40,20},{-40,40},{-40,60},
			{-20,20},{-20,40},{-20,60},{0,20},{0,40},{0,60},
			{20,20},{20,40},{20,60},{40,20},{40,40},{40,60},
			{60,20},{60,40},{60,60},{-60,-20},{-60,-40},{-60,-60},
			{-40,-20},{-40,-40},{-40,-60},{-20,-20},{-20,-40},{-20,-60},
			{0,-20},{0,-40},{0,-60},{20,-20},{20,-40},{20,-60},
			{40,-20},{40,-40},{40,-60},{60,-20},{60,-40},{60,-60},
			{-80,0},{-80,40},{-80,-40},{80,0},{80,40},{80,-40},
			{0,80},{0,-80},
		},
		waypoints = {
			Vector3.new(-90, 0, -90),
			Vector3.new(-90, 0,  0),
			Vector3.new(-50, 0,  0),
			Vector3.new(-50, 0,  70),
			Vector3.new(  0, 0,  70),
			Vector3.new(  0, 0,  0),
			Vector3.new( 50, 0,  0),
			Vector3.new( 50, 0, -70),
			Vector3.new( 90, 0, -70),
			Vector3.new( 90, 0,  90),
		},
	},

	-- Map 2: Spiral inward
	Map2 = {
		name = "Dustlands",
		gridSize = Vector3.new(200, 0, 200),
		towerSlots = {
			{-70,70},{-50,70},{-30,70},{-10,70},{10,70},{30,70},{50,70},{70,70},
			{70,50},{70,30},{70,10},{70,-10},{70,-30},{70,-50},{70,-70},
			{50,-70},{30,-70},{10,-70},{-10,-70},{-30,-70},{-50,-70},{-70,-70},
			{-70,-50},{-70,-30},{-70,-10},{-70,10},{-70,30},{-70,50},
			{-50,50},{-30,50},{-10,50},{10,50},{30,50},{50,50},
			{50,30},{50,10},{50,-10},{50,-30},{50,-50},
			{30,-50},{10,-50},{-10,-50},{-30,-50},{-50,-50},
			{-50,-30},{-50,-10},{-50,10},{-50,30},
			{-30,30},{-10,30},
		},
		waypoints = {
			Vector3.new(-90, 0, -90),
			Vector3.new( 90, 0, -90),
			Vector3.new( 90, 0,  90),
			Vector3.new(-90, 0,  90),
			Vector3.new(-90, 0, -30),
			Vector3.new( 30, 0, -30),
			Vector3.new( 30, 0,  30),
			Vector3.new(-30, 0,  30),
			Vector3.new(-30, 0, -10),
			Vector3.new(  0, 0, -10),
			Vector3.new(  0, 0,  0),
		},
	},

	-- Map 3: Zigzag gauntlet
	Map3 = {
		name = "Ironpass",
		gridSize = Vector3.new(240, 0, 160),
		towerSlots = {
			{-100,50},{-100,30},{-100,10},{-100,-10},{-100,-30},{-100,-50},
			{-80,50},{-80,30},{-80,10},{-80,-10},{-80,-30},{-80,-50},
			{-60,50},{-60,30},{-60,10},{-60,-10},{-60,-30},{-60,-50},
			{-40,50},{-40,30},{-40,10},{-40,-10},{-40,-30},{-40,-50},
			{-20,50},{-20,30},{-20,10},{-20,-10},{-20,-30},{-20,-50},
			{0,50},{0,30},{0,10},{0,-10},{0,-30},{0,-50},
			{20,50},{20,30},{20,10},{20,-10},{20,-30},{20,-50},
			{40,50},{40,30},{40,10},{40,-10},{40,-30},{40,-50},
			{60,50},{60,30},
		},
		waypoints = {
			Vector3.new(-110, 0,  60),
			Vector3.new(-110, 0, -60),
			Vector3.new( -70, 0, -60),
			Vector3.new( -70, 0,  60),
			Vector3.new( -30, 0,  60),
			Vector3.new( -30, 0, -60),
			Vector3.new(  10, 0, -60),
			Vector3.new(  10, 0,  60),
			Vector3.new(  50, 0,  60),
			Vector3.new(  50, 0, -60),
			Vector3.new(  90, 0, -60),
			Vector3.new(  90, 0,  60),
			Vector3.new( 110, 0,  60),
		},
	},
}

-- Returns the map config by name
local function getMap(mapName: string)
	return Maps[mapName] or Maps.Map1
end

-- Returns all map names
local function getMapNames(): { string }
	local names = {}
	for k in pairs(Maps) do table.insert(names, k) end
	return names
end

return {
	Maps        = Maps,
	getMap      = getMap,
	getMapNames = getMapNames,
}
