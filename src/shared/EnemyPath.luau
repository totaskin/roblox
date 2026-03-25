-- EnemyPath.luau
-- Waypoint paths for each map. Enemies follow these in order.
-- Coordinates are world-space Vector3 positions.
-- Paths are randomly generated each game with varied patterns.

-- Path pattern types
local PathPatterns = {
	"SPIRAL",      -- Spiral inward or outward
	"ZIGZAG",      -- Sharp diagonal zigzags
	"SNAKE",       -- Smooth S-curves
	"CROSS",       -- Cross the map multiple times
	"LOOP",        -- Path that loops around
}

-- Generate a spiral path
local function generateSpiral(): { Vector3 }
	local waypoints = {}
	local centerX, centerZ = 0, 0
	local maxRadius = 80
	local minRadius = 15
	local turns = math.random(2, 4)
	local pointsPerTurn = math.random(6, 10)
	local totalPoints = turns * pointsPerTurn
	local inward = math.random() > 0.5
	
	for i = 0, totalPoints do
		local t = i / totalPoints
		local angle = t * turns * math.pi * 2 + math.random() * 0.3
		local radius
		if inward then
			radius = maxRadius - (maxRadius - minRadius) * t
		else
			radius = minRadius + (maxRadius - minRadius) * t
		end
		radius = radius + math.random(-5, 5)
		
		local x = centerX + math.cos(angle) * radius
		local z = centerZ + math.sin(angle) * radius
		table.insert(waypoints, Vector3.new(x, 0, z))
	end
	
	return waypoints
end

-- Generate sharp zigzag path
local function generateZigzag(): { Vector3 }
	local waypoints = {}
	local startLeft = math.random() > 0.5
	local currentX = startLeft and -85 or 85
	local direction = startLeft and 1 or -1
	local currentZ = -70
	
	table.insert(waypoints, Vector3.new(currentX, 0, currentZ))
	
	local numZigs = math.random(4, 7)
	local zStep = 140 / numZigs
	
	for i = 1, numZigs do
		-- Move diagonally
		currentZ = currentZ + zStep + math.random(-10, 10)
		currentX = currentX + direction * math.random(30, 50)
		currentX = math.clamp(currentX, -85, 85)
		table.insert(waypoints, Vector3.new(currentX, 0, currentZ))
		
		-- Flip direction
		direction = -direction
	end
	
	-- Final point
	currentZ = 75
	table.insert(waypoints, Vector3.new(currentX + direction * 20, 0, currentZ))
	
	return waypoints
end

-- Generate smooth S-curve snake path
local function generateSnake(): { Vector3 }
	local waypoints = {}
	local amplitude = math.random(40, 70)
	local frequency = math.random(2, 4)
	local startZ = -75
	local endZ = 75
	local points = math.random(12, 20)
	
	for i = 0, points do
		local t = i / points
		local z = startZ + (endZ - startZ) * t
		local x = math.sin(t * frequency * math.pi * 2) * amplitude
		-- Add some noise
		x = x + math.random(-8, 8)
		z = z + math.random(-5, 5)
		table.insert(waypoints, Vector3.new(x, 0, z))
	end
	
	return waypoints
end

-- Generate cross pattern (goes back and forth across map)
local function generateCross(): { Vector3 }
	local waypoints = {}
	local corners = {
		Vector3.new(-80, 0, -70),
		Vector3.new(80, 0, 70),
		Vector3.new(-80, 0, 70),
		Vector3.new(80, 0, -70),
		Vector3.new(-80, 0, 0),
		Vector3.new(80, 0, 0),
	}
	
	-- Shuffle and pick 4-6 corners
	local numCorners = math.random(4, 6)
	local used = {}
	
	-- Start from a random corner
	local startIdx = math.random(1, #corners)
	table.insert(waypoints, corners[startIdx])
	used[startIdx] = true
	
	for i = 2, numCorners do
		-- Find furthest unused corner for more interesting paths
		local bestIdx = nil
		local bestDist = 0
		local lastPos = waypoints[#waypoints]
		
		for j, corner in ipairs(corners) do
			if not used[j] then
				local dist = (corner - lastPos).Magnitude
				if dist > bestDist then
					bestDist = dist
					bestIdx = j
				end
			end
		end
		
		if bestIdx then
			-- Add intermediate point for longer segments
			local midPoint = (lastPos + corners[bestIdx]) / 2
			midPoint = midPoint + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
			table.insert(waypoints, midPoint)
			table.insert(waypoints, corners[bestIdx])
			used[bestIdx] = true
		end
	end
	
	return waypoints
end

-- Generate loop path
local function generateLoop(): { Vector3 }
	local waypoints = {}
	
	-- Start outside
	local startX = math.random() > 0.5 and -90 or 90
	local startZ = math.random(-50, 50)
	table.insert(waypoints, Vector3.new(startX, 0, startZ))
	
	-- Create a loop shape
	local loopCenterX = math.random(-30, 30)
	local loopCenterZ = math.random(-20, 20)
	local loopRadius = math.random(35, 55)
	local loopPoints = math.random(8, 12)
	local startAngle = math.atan2(startZ - loopCenterZ, startX - loopCenterX)
	
	-- Enter the loop
	local entryX = loopCenterX + math.cos(startAngle) * loopRadius
	local entryZ = loopCenterZ + math.sin(startAngle) * loopRadius
	table.insert(waypoints, Vector3.new(entryX, 0, entryZ))
	
	-- Go around the loop (1.5 to 2 times around)
	local loopTurns = 1.5 + math.random() * 0.5
	for i = 1, math.floor(loopPoints * loopTurns) do
		local angle = startAngle + (i / loopPoints) * math.pi * 2
		local r = loopRadius + math.random(-8, 8)
		local x = loopCenterX + math.cos(angle) * r
		local z = loopCenterZ + math.sin(angle) * r
		table.insert(waypoints, Vector3.new(x, 0, z))
	end
	
	-- Exit to opposite side
	local exitX = -startX
	local exitZ = math.random(-50, 50)
	table.insert(waypoints, Vector3.new(exitX * 0.5, 0, exitZ))
	table.insert(waypoints, Vector3.new(exitX, 0, exitZ))
	
	return waypoints
end

-- Generate a random path using one of the patterns
local function generateRandomPath(seed: number?): { Vector3 }
	if seed then
		math.randomseed(seed)
	else
		math.randomseed(tick() + math.random(1, 100000))
	end
	
	local pattern = PathPatterns[math.random(1, #PathPatterns)]
	local waypoints
	
	if pattern == "SPIRAL" then
		waypoints = generateSpiral()
	elseif pattern == "ZIGZAG" then
		waypoints = generateZigzag()
	elseif pattern == "SNAKE" then
		waypoints = generateSnake()
	elseif pattern == "CROSS" then
		waypoints = generateCross()
	elseif pattern == "LOOP" then
		waypoints = generateLoop()
	else
		waypoints = generateSnake() -- fallback
	end
	
	print("[EnemyPath] Generated", pattern, "path with", #waypoints, "waypoints")
	return waypoints
end

-- Generate tower slots based on waypoints
local function generateTowerSlots(waypoints: { Vector3 }): { { number } }
	local slots = {}
	local slotSpacing = 18
	local pathMargin = 14
	
	-- For each path segment, place slots on both sides
	for i = 1, #waypoints - 1 do
		local a = waypoints[i]
		local b = waypoints[i + 1]
		local dir = (b - a).Unit
		local perpendicular = Vector3.new(-dir.Z, 0, dir.X)
		
		local segmentLength = (b - a).Magnitude
		local numSlots = math.max(1, math.floor(segmentLength / slotSpacing))
		
		for j = 1, numSlots do
			local t = j / (numSlots + 1)
			local pointOnPath = a + (b - a) * t
			
			for _, side in ipairs({-1, 1}) do
				local offset = perpendicular * (pathMargin + math.random(3, 12)) * side
				local slotPos = pointOnPath + offset
				
				if math.abs(slotPos.X) < 95 and math.abs(slotPos.Z) < 85 then
					table.insert(slots, { math.floor(slotPos.X), math.floor(slotPos.Z) })
				end
			end
		end
	end
	
	-- Add slots near waypoint bends
	for i = 2, #waypoints - 1 do
		local wp = waypoints[i]
		local prevDir = (wp - waypoints[i-1]).Unit
		local nextDir = (waypoints[i+1] - wp).Unit
		local bendAngle = math.acos(math.clamp(prevDir:Dot(nextDir), -1, 1))
		
		-- More slots at sharper bends
		if bendAngle > 0.5 then
			local perpPrev = Vector3.new(-prevDir.Z, 0, prevDir.X)
			local perpNext = Vector3.new(-nextDir.Z, 0, nextDir.X)
			
			for _, offset in ipairs({perpPrev * 20, perpNext * 20, -perpPrev * 20, -perpNext * 20}) do
				local slotPos = wp + offset
				if math.abs(slotPos.X) < 95 and math.abs(slotPos.Z) < 85 then
					table.insert(slots, { math.floor(slotPos.X), math.floor(slotPos.Z) })
				end
			end
		end
	end
	
	return slots
end

-- Cache for generated maps
local generatedMaps: { [string]: any } = {}

local MapThemes = {
	Map1 = { name = "Greenfield" },
	Map2 = { name = "Dustlands" },
	Map3 = { name = "Ironpass" },
}

local function getMap(mapName: string)
	if not generatedMaps[mapName] then
		local theme = MapThemes[mapName] or MapThemes.Map1
		local waypoints = generateRandomPath()
		local towerSlots = generateTowerSlots(waypoints)
		
		generatedMaps[mapName] = {
			name = theme.name,
			gridSize = Vector3.new(200, 0, 200),
			towerSlots = towerSlots,
			waypoints = waypoints,
		}
	end
	return generatedMaps[mapName]
end

local function regenerateMap(mapName: string)
	generatedMaps[mapName] = nil
	return getMap(mapName)
end

local function getMapNames(): { string }
	local names = {}
	for k in pairs(MapThemes) do table.insert(names, k) end
	return names
end

return {
	getMap         = getMap,
	getMapNames    = getMapNames,
	regenerateMap  = regenerateMap,
	generateRandomPath = generateRandomPath,
	generateTowerSlots = generateTowerSlots,
}
