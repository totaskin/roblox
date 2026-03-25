-- MapBuilder.luau
-- Builds the visual map: path tiles between waypoints, tower grid slots
-- Reads waypoints from Workspace.Map1 folder if present, else uses EnemyPath data

local EnemyPath = require(game.ReplicatedStorage.Shared.EnemyPath)

local MapBuilder = {}

local PATH_WIDTH  = 8   -- studs wide (reduced from 12)
local PATH_HEIGHT = 0.3
local SLOT_SIZE   = 4

-- Per-map visual theme configuration
local function getMapTheme(mapName: string)
	local themes = {
		Map1 = {
			groundMaterial = Enum.Material.Grass,
			groundColor = Color3.fromRGB(90, 130, 60),
			pathMaterial = Enum.Material.Sand,
			pathColor = Color3.fromRGB(160, 130, 90),
			elevationScale = 4,
		},
		Map2 = {
			groundMaterial = Enum.Material.Sand,
			groundColor = Color3.fromRGB(180, 160, 110),
			pathMaterial = Enum.Material.Sandstone,
			pathColor = Color3.fromRGB(140, 110, 70),
			elevationScale = 3,
		},
		Map3 = {
			groundMaterial = Enum.Material.Metal,
			groundColor = Color3.fromRGB(100, 100, 110),
			pathMaterial = Enum.Material.DiamondPlate,
			pathColor = Color3.fromRGB(80, 80, 90),
			elevationScale = 2,
		},
	}
	return themes[mapName] or themes.Map1
end

-- Returns the minimum distance from point p to the line segment from a to b
local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local ap = p - a
	local lenSq = ab:Dot(ab)
	if lenSq == 0 then
		return (p - a).Magnitude
	end
	local t = math.clamp(ap:Dot(ab) / lenSq, 0, 1)
	local closest = a + ab * t
	return (p - closest).Magnitude
end

-- Check if a point is within the path corridor (close to any path segment)
local function isInPathCorridor(point: Vector3, waypoints: { Vector3 }, margin: number): boolean
	for i = 1, #waypoints - 1 do
		local a = Vector3.new(waypoints[i].X, 0, waypoints[i].Z)
		local b = Vector3.new(waypoints[i + 1].X, 0, waypoints[i + 1].Z)
		local p = Vector3.new(point.X, 0, point.Z)
		if distanceToSegment(p, a, b) < margin then
			return true
		end
	end
	return false
end

local function buildPathBetween(parent: Folder, a: Vector3, b: Vector3, index: number, theme: any)
	local mid    = (a + b) / 2 + Vector3.new(0, 0.5, 0)
	local length = (b - a).Magnitude
	local dir    = (b - a).Unit

	local tile = Instance.new("Part")
	tile.Name = "PathTile_" .. index
	-- Don't add extra width to length - just use the actual segment length
	tile.Size = Vector3.new(PATH_WIDTH, PATH_HEIGHT, length)
	tile.CFrame = CFrame.lookAt(mid, mid + dir)
	tile.Anchored = true
	tile.CanCollide = false
	tile.Material = theme.pathMaterial
	tile.Color = theme.pathColor
	tile.TopSurface = Enum.SurfaceType.Smooth
	tile.BottomSurface = Enum.SurfaceType.Smooth
	tile.Parent = parent
end

-- Build a circular node at waypoint intersections to smooth corners
local function buildPathNode(parent: Folder, pos: Vector3, index: number, theme: any)
	local node = Instance.new("Part")
	node.Name = "PathNode_" .. index
	node.Shape = Enum.PartType.Cylinder
	node.Size = Vector3.new(PATH_HEIGHT, PATH_WIDTH, PATH_WIDTH)
	node.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	node.Anchored = true
	node.CanCollide = false
	node.Material = theme.pathMaterial
	node.Color = theme.pathColor
	node.TopSurface = Enum.SurfaceType.Smooth
	node.BottomSurface = Enum.SurfaceType.Smooth
	node.Parent = parent
end

local function buildTowerSlots(parent: Folder, slots: { { number } }, yOffset: number?, theme: any)
	local baseY = PATH_HEIGHT + 0.1 + (yOffset or 0)
	for _, slot in ipairs(slots) do
		local part = Instance.new("Part")
		part.Name = "TowerSlot_" .. slot[1] .. "_" .. slot[2]
		part.Size = Vector3.new(SLOT_SIZE, 0.2, SLOT_SIZE)
		part.Position = Vector3.new(slot[1], baseY, slot[2])
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Color = theme.pathColor
		part.Transparency = 0.5
		part.TopSurface = Enum.SurfaceType.Smooth
		part.Parent = parent
	end
end

local function getWaypoints(mapName: string): { Vector3 }
	-- Prefer parts placed in Workspace
	local mapFolder = workspace:FindFirstChild(mapName)
	if mapFolder then
		local points: { { index: number, pos: Vector3 } } = {}
		for _, part in ipairs(mapFolder:GetChildren()) do
			local index = tonumber(part.Name:match("Waypoint(%d+)"))
			if index then
				table.insert(points, { index = index, pos = part.Position })
			end
		end
		if #points > 0 then
			table.sort(points, function(a, b) return a.index < b.index end)
			local waypoints = {}
			for _, p in ipairs(points) do table.insert(waypoints, p.pos) end
			return waypoints
		end
	end
	return EnemyPath.getMap(mapName).waypoints
end

-- Build terrain as a 10x10 grid of tiles with noise-based elevation, skipping path corridor
local function buildTerrain(folder: Folder, mapName: string, worldOffset: Vector3, waypoints: { Vector3 })
	local theme = getMapTheme(mapName)
	local gridCount = 10
	local mapSize = 250
	local tileSize = mapSize / gridCount -- 25 studs per tile

	-- Solid ground plane underneath everything to prevent falling through gaps
	local groundPlane = Instance.new("Part")
	groundPlane.Name = "GroundPlane"
	groundPlane.Size = Vector3.new(mapSize + 20, 2, mapSize + 20)
	groundPlane.Position = Vector3.new(worldOffset.X, worldOffset.Y - 1.5, worldOffset.Z)
	groundPlane.Anchored = true
	groundPlane.CanCollide = true
	groundPlane.Material = theme.groundMaterial
	groundPlane.Color = theme.groundColor
	groundPlane.TopSurface = Enum.SurfaceType.Smooth
	groundPlane.BottomSurface = Enum.SurfaceType.Smooth
	groundPlane.Parent = folder

	for gx = 0, gridCount - 1 do
		for gz = 0, gridCount - 1 do
			local tileCenterX = -mapSize / 2 + tileSize / 2 + gx * tileSize + worldOffset.X
			local tileCenterZ = -mapSize / 2 + tileSize / 2 + gz * tileSize + worldOffset.Z
			local tileCenter = Vector3.new(tileCenterX, 0, tileCenterZ)

			-- Skip tiles that overlap the path corridor
			if isInPathCorridor(tileCenter, waypoints, PATH_WIDTH + tileSize / 2) then
				continue
			end

			-- Compute elevation using Perlin noise
			local noiseVal = math.noise(gx * 0.05, gz * 0.05) -- range roughly -0.5 to 0.5
			local yOffset = noiseVal * theme.elevationScale

			local tile = Instance.new("Part")
			tile.Name = "TerrainTile_" .. gx .. "_" .. gz
			tile.Size = Vector3.new(tileSize, 1, tileSize)
			tile.Position = Vector3.new(tileCenterX, -0.2 + yOffset + worldOffset.Y, tileCenterZ)
			tile.Anchored = true
			tile.Material = theme.groundMaterial
			tile.Color = theme.groundColor
			tile.TopSurface = Enum.SurfaceType.Smooth
			tile.BottomSurface = Enum.SurfaceType.Smooth
			tile.Parent = folder
		end
	end
end

-- Place themed decorative parts outside the path corridor
local function buildDecorations(folder: Folder, mapName: string, worldOffset: Vector3, waypoints: { Vector3 })
	local decorConfigs = {
		Map1 = { -- Greenfield: trees and bushes
			{
				name = "Tree",
				shape = "Cylinder",
				size = Vector3.new(3, 8, 3),
				color = Color3.fromRGB(60, 120, 40),
				material = Enum.Material.Grass,
				yOffset = 4,
			},
			{
				name = "Bush",
				shape = "Ball",
				size = Vector3.new(4, 3, 4),
				color = Color3.fromRGB(80, 140, 50),
				material = Enum.Material.Grass,
				yOffset = 1.5,
			},
		},
		Map2 = { -- Dustlands: cacti and rock formations
			{
				name = "Cactus",
				shape = "Cylinder",
				size = Vector3.new(2, 10, 2),
				color = Color3.fromRGB(100, 140, 60),
				material = Enum.Material.Sand,
				yOffset = 5,
			},
			{
				name = "Rock",
				shape = "Block",
				size = Vector3.new(5, 4, 5),
				color = Color3.fromRGB(150, 130, 100),
				material = Enum.Material.Sand,
				yOffset = 2,
			},
		},
		Map3 = { -- Ironpass: pipes and crates
			{
				name = "Pipe",
				shape = "Cylinder",
				size = Vector3.new(2, 6, 2),
				color = Color3.fromRGB(120, 120, 130),
				material = Enum.Material.Metal,
				yOffset = 3,
			},
			{
				name = "Crate",
				shape = "Block",
				size = Vector3.new(4, 4, 4),
				color = Color3.fromRGB(90, 85, 80),
				material = Enum.Material.Metal,
				yOffset = 2,
			},
		},
	}

	local configs = decorConfigs[mapName] or decorConfigs.Map1
	local mapHalfSize = 110
	local placed = 0
	local maxDecorations = 25
	local attempts = 0
	local maxAttempts = 200

	math.randomseed(tick())

	while placed < maxDecorations and attempts < maxAttempts do
		attempts += 1
		local x = math.random(-mapHalfSize, mapHalfSize) + worldOffset.X
		local z = math.random(-mapHalfSize, mapHalfSize) + worldOffset.Z
		local pos = Vector3.new(x, 0, z)

		-- Skip if in path corridor
		if isInPathCorridor(pos, waypoints, PATH_WIDTH + 6) then
			continue
		end

		local config = configs[math.random(1, #configs)]
		local part = Instance.new("Part")
		part.Name = config.name .. "_" .. placed
		part.Size = config.size
		part.Position = Vector3.new(x, config.yOffset + worldOffset.Y, z)
		part.Anchored = true
		part.CanCollide = false
		part.Material = config.material
		part.Color = config.color

		if config.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
			-- Rotate cylinder upright (Roblox cylinders are horizontal by default)
			part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, 0, math.rad(90))
		elseif config.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		end
		-- Block is default shape

		part.Parent = folder
		placed += 1
	end
end

function MapBuilder.build(mapName: string, worldOffset: Vector3?, areaId: number?)
	mapName = mapName or "Map1"
	worldOffset = worldOffset or Vector3.new(0, 0, 0)
	local mapData = EnemyPath.getMap(mapName)
	local waypoints = getWaypoints(mapName)
	local theme = getMapTheme(mapName)

	-- Apply offset to waypoints
	local offsetWaypoints = {}
	for _, wp in ipairs(waypoints) do
		table.insert(offsetWaypoints, wp + worldOffset)
	end

	-- Container folder with per-instance name
	local folderName = "MapVisuals_" .. (areaId or 1)
	local existing = workspace:FindFirstChild(folderName)
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = workspace

	-- Terrain grid with elevation variation (replaces single ground plane)
	buildTerrain(folder, mapName, worldOffset, offsetWaypoints)

	-- Path tiles between waypoints
	for i = 1, #offsetWaypoints - 1 do
		buildPathBetween(folder, offsetWaypoints[i], offsetWaypoints[i + 1], i, theme)
	end
	
	-- Path nodes at each waypoint to smooth corners
	for i = 1, #offsetWaypoints do
		buildPathNode(folder, offsetWaypoints[i], i, theme)
	end

	-- Start marker
	local startMarker = Instance.new("Part")
	startMarker.Name = "StartMarker"
	startMarker.Size = Vector3.new(PATH_WIDTH, 0.4, PATH_WIDTH)
	startMarker.Position = offsetWaypoints[1] + Vector3.new(0, 0.6, 0)
	startMarker.Anchored = true
	startMarker.Color = Color3.fromRGB(80, 200, 80)
	startMarker.Material = Enum.Material.Neon
	startMarker.Transparency = 0.3
	startMarker.Parent = folder

	-- End marker (base)
	local endMarker = Instance.new("Part")
	endMarker.Name = "BaseMarker"
	endMarker.Size = Vector3.new(PATH_WIDTH + 4, 0.5, PATH_WIDTH + 4)
	endMarker.Position = offsetWaypoints[#offsetWaypoints] + Vector3.new(0, 0.6, 0)
	endMarker.Anchored = true
	endMarker.Color = Color3.fromRGB(200, 80, 80)
	endMarker.Material = Enum.Material.Neon
	endMarker.Transparency = 0.3
	endMarker.Parent = folder

	-- Tower slots (offset) with theme colors
	local offsetSlots = {}
	for _, slot in ipairs(mapData.towerSlots) do
		table.insert(offsetSlots, { slot[1] + worldOffset.X, slot[2] + worldOffset.Z })
	end
	buildTowerSlots(folder, offsetSlots, worldOffset.Y, theme)

	-- Themed decorations
	buildDecorations(folder, mapName, worldOffset, offsetWaypoints)

	-- Invisible boundary walls around the game map
	local MAP_WALL_HEIGHT = 30
	local center = worldOffset
	local halfSize = 125 -- ground is 250x250
	local boundaryWalls = {
		{ pos = center + Vector3.new(0, MAP_WALL_HEIGHT / 2, -halfSize), size = Vector3.new(250, MAP_WALL_HEIGHT, 1) },
		{ pos = center + Vector3.new(0, MAP_WALL_HEIGHT / 2,  halfSize), size = Vector3.new(250, MAP_WALL_HEIGHT, 1) },
		{ pos = center + Vector3.new(-halfSize, MAP_WALL_HEIGHT / 2, 0), size = Vector3.new(1, MAP_WALL_HEIGHT, 250) },
		{ pos = center + Vector3.new( halfSize, MAP_WALL_HEIGHT / 2, 0), size = Vector3.new(1, MAP_WALL_HEIGHT, 250) },
	}
	for wi, wallInfo in ipairs(boundaryWalls) do
		local bWall = Instance.new("Part")
		bWall.Name         = "MapBoundary_" .. wi
		bWall.Size         = wallInfo.size
		bWall.Position     = wallInfo.pos
		bWall.Anchored     = true
		bWall.CanCollide   = true
		bWall.Transparency = 1
		bWall.Parent       = folder
	end

	print("[MapBuilder] Built map:", mapName, "| Waypoints:", #waypoints, "| Slots:", #mapData.towerSlots, "| Offset:", worldOffset)
end

return MapBuilder
