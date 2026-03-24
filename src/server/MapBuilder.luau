-- MapBuilder.luau
-- Builds the visual map: path tiles between waypoints, tower grid slots
-- Reads waypoints from Workspace.Map1 folder if present, else uses EnemyPath data

local EnemyPath = require(game.ReplicatedStorage.Shared.EnemyPath)

local MapBuilder = {}

local PATH_WIDTH  = 12  -- studs wide
local PATH_HEIGHT = 0.3
local SLOT_SIZE   = 4

local function buildPathBetween(parent: Folder, a: Vector3, b: Vector3, index: number)
	local mid    = (a + b) / 2 + Vector3.new(0, 0.5, 0)
	local length = (b - a).Magnitude
	local dir    = (b - a).Unit

	local tile = Instance.new("Part")
	tile.Name = "PathTile_" .. index
	tile.Size = Vector3.new(PATH_WIDTH, PATH_HEIGHT, length + PATH_WIDTH)
	tile.CFrame = CFrame.lookAt(mid, mid + dir)
	tile.Anchored = true
	tile.CanCollide = false
	tile.Material = Enum.Material.Sand
	tile.Color = Color3.fromRGB(160, 130, 90)
	tile.TopSurface = Enum.SurfaceType.Smooth
	tile.BottomSurface = Enum.SurfaceType.Smooth
	tile.Parent = parent
end

local function buildTowerSlots(parent: Folder, slots: { { number } }, yOffset: number?)
	local baseY = PATH_HEIGHT + 0.1 + (yOffset or 0)
	for i, slot in ipairs(slots) do
		local part = Instance.new("Part")
		part.Name = "TowerSlot_" .. slot[1] .. "_" .. slot[2]
		part.Size = Vector3.new(SLOT_SIZE, 0.2, SLOT_SIZE)
		part.Position = Vector3.new(slot[1], baseY, slot[2])
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(60, 160, 60)
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

function MapBuilder.build(mapName: string, worldOffset: Vector3?)
	mapName = mapName or "Map1"
	worldOffset = worldOffset or Vector3.new(0, 0, 0)
	local mapData = EnemyPath.getMap(mapName)
	local waypoints = getWaypoints(mapName)

	-- Apply offset to waypoints
	local offsetWaypoints = {}
	for _, wp in ipairs(waypoints) do
		table.insert(offsetWaypoints, wp + worldOffset)
	end

	-- Container folder
	local existing = workspace:FindFirstChild("MapVisuals")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "MapVisuals"
	folder.Parent = workspace

	-- Ground plane
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Size = Vector3.new(250, 1, 250)
	ground.Position = Vector3.new(0, -0.2, 0) + worldOffset
	ground.Anchored = true
	ground.Material = Enum.Material.Grass
	ground.Color = Color3.fromRGB(90, 130, 60)
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.BottomSurface = Enum.SurfaceType.Smooth
	ground.Parent = folder

	-- Path tiles
	for i = 1, #offsetWaypoints - 1 do
		buildPathBetween(folder, offsetWaypoints[i], offsetWaypoints[i + 1], i)
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

	-- Tower slots (offset)
	local offsetSlots = {}
	for _, slot in ipairs(mapData.towerSlots) do
		table.insert(offsetSlots, { slot[1] + worldOffset.X, slot[2] + worldOffset.Z })
	end
	buildTowerSlots(folder, offsetSlots, worldOffset.Y)

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
