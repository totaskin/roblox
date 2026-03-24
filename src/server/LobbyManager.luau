-- LobbyManager.luau
-- Manages the 3 lobby area pads, occupancy, countdown, and game launch.
-- Tasks 3.x: pad construction and AreaState initialisation.
-- Tasks 4.x: touch events, countdown, game launch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")

local GameManager = require(script.Parent.GameManager)
local EconomyManager = require(script.Parent.EconomyManager)
local GamepassManager = require(script.Parent.GamepassManager)
local TurretData = require(game.ReplicatedStorage.Shared.TurretData)
local DataManager = require(script.Parent.DataManager)

-- AreaState type (per design.md)
type AreaState = {
	index: number,
	status: "EMPTY" | "WAITING" | "IN_GAME" | "RESULTS",
	occupants: { Player },
	countdownRemaining: number,
	gameManager: any?,
	roundReached: number,
	padFloor: BasePart,
	spawnCFrame: CFrame,
	countdownGeneration: number,
	dismissedPlayers: { [Player]: boolean },
}

-- Pad configuration
local PAD_POSITIONS = {
	Vector3.new(-40, 0, 110),
	Vector3.new(0,   0, 110),
	Vector3.new(40,  0, 110),
}

local PAD_COLORS = {
	BrickColor.new("Bright red"),
	BrickColor.new("Bright blue"),
	BrickColor.new("Bright green"),
}

local FLOOR_SIZE        = Vector3.new(20, 2, 20)
local WALL_SIZE         = Vector3.new(20, 6, 1)
local WALL_TRANSPARENCY = 0.7
local SPAWN_Y_OFFSET    = 1
local LOBBY_SPAWN       = CFrame.new(0, 2, 130)

-- Game map world offset (must match the offset passed to MapBuilder.build in GameManager)
local MAP_OFFSET = Vector3.new(0, 0, -10000)
-- Game map spawn position (near the start of the enemy path on Map1, offset applied)
local MAP_SPAWN = CFrame.new(-90 + MAP_OFFSET.X, 3 + MAP_OFFSET.Y, -80 + MAP_OFFSET.Z)

-- Internal state
local areas: { AreaState } = {}
local remotes: Folder

-- Turret system state (Task 4.1)
local playerUnlocks: { [number]: { [number]: boolean } } = {}
local playerLoadouts: { [number]: { number } } = {}

local LobbyManager = {}

-- ---------------------------------------------------------------------------
-- buildPads: constructs the 3 physical area pads in the world.
-- ---------------------------------------------------------------------------
local function buildPads()
	-- Build a large vibrant lobby ground
	local lobbyGround = Instance.new("Part")
	lobbyGround.Name       = "LobbyGround"
	lobbyGround.Size       = Vector3.new(200, 1, 140)
	lobbyGround.CFrame     = CFrame.new(0, 0.5, 110)
	lobbyGround.Anchored   = true
	lobbyGround.CanCollide = true
	lobbyGround.Material   = Enum.Material.SmoothPlastic
	lobbyGround.Color      = Color3.fromRGB(240, 235, 250)
	lobbyGround.TopSurface = Enum.SurfaceType.Smooth
	lobbyGround.Parent     = Workspace

	-- Colorful floor accents — neon strips along the ground
	local stripColors = {
		Color3.fromRGB(255, 180, 210),
		Color3.fromRGB(180, 220, 255),
		Color3.fromRGB(255, 240, 180),
		Color3.fromRGB(190, 255, 210),
		Color3.fromRGB(220, 190, 255),
	}
	for si = 1, 5 do
		local strip = Instance.new("Part")
		strip.Name = "FloorStrip_" .. si
		strip.Size = Vector3.new(200, 0.1, 2)
		strip.Position = Vector3.new(0, 1.05, 50 + si * 18)
		strip.Anchored = true
		strip.CanCollide = false
		strip.Color = stripColors[si]
		strip.Material = Enum.Material.Neon
		strip.Parent = Workspace
	end

	-- ── Vibrant Lobby Walls ──────────────────────────────────────────────
	local LOBBY_WALL_HEIGHT = 64
	local lobbyWalls = {
		{ pos = Vector3.new(0, LOBBY_WALL_HEIGHT / 2 + 1, 40),    size = Vector3.new(200, LOBBY_WALL_HEIGHT, 2), color = Color3.fromRGB(255, 200, 220) },  -- front — pastel pink
		{ pos = Vector3.new(0, LOBBY_WALL_HEIGHT / 2 + 1, 180),   size = Vector3.new(200, LOBBY_WALL_HEIGHT, 2), color = Color3.fromRGB(200, 220, 255) },  -- back — pastel blue
		{ pos = Vector3.new(-100, LOBBY_WALL_HEIGHT / 2 + 1, 110), size = Vector3.new(2, LOBBY_WALL_HEIGHT, 140), color = Color3.fromRGB(210, 255, 220) }, -- left — pastel mint
		{ pos = Vector3.new(100, LOBBY_WALL_HEIGHT / 2 + 1, 110),  size = Vector3.new(2, LOBBY_WALL_HEIGHT, 140), color = Color3.fromRGB(255, 230, 200) }, -- right — pastel peach
	}
	for wi, wallInfo in ipairs(lobbyWalls) do
		local bWall = Instance.new("Part")
		bWall.Name         = "LobbyWall_" .. wi
		bWall.Size         = wallInfo.size
		bWall.Position     = wallInfo.pos
		bWall.Anchored     = true
		bWall.CanCollide   = true
		bWall.Color        = wallInfo.color
		bWall.Material     = Enum.Material.SmoothPlastic
		bWall.Transparency = 0
		bWall.Parent       = Workspace
	end

	-- Pastel neon accent strips — spread evenly up the tall walls
	local stripHeights = { 5, 15, 25, 35, 45, 55, 63 }
	local frontBackColors = {
		Color3.fromRGB(255, 180, 220), Color3.fromRGB(180, 220, 255),
		Color3.fromRGB(255, 240, 180), Color3.fromRGB(190, 255, 200),
		Color3.fromRGB(220, 190, 255), Color3.fromRGB(255, 210, 190),
		Color3.fromRGB(200, 240, 255),
	}
	local sideColors = {
		Color3.fromRGB(220, 190, 255), Color3.fromRGB(180, 230, 255),
		Color3.fromRGB(255, 210, 180), Color3.fromRGB(255, 190, 210),
		Color3.fromRGB(190, 255, 220), Color3.fromRGB(255, 230, 200),
		Color3.fromRGB(210, 200, 255),
	}
	local wallStripData = {}
	for i, h in ipairs(stripHeights) do
		-- front
		table.insert(wallStripData, { size = Vector3.new(200, 0.4, 0.3), pos = Vector3.new(0, h, 39), color = frontBackColors[i] })
		-- back
		table.insert(wallStripData, { size = Vector3.new(200, 0.4, 0.3), pos = Vector3.new(0, h, 181), color = frontBackColors[i] })
		-- left
		table.insert(wallStripData, { size = Vector3.new(0.3, 0.4, 140), pos = Vector3.new(-101, h, 110), color = sideColors[i] })
		-- right
		table.insert(wallStripData, { size = Vector3.new(0.3, 0.4, 140), pos = Vector3.new(101, h, 110), color = sideColors[i] })
	end
	for si, sd in ipairs(wallStripData) do
		local wStrip = Instance.new("Part")
		wStrip.Name = "LobbyWallStrip_" .. si
		wStrip.Size = sd.size
		wStrip.Position = sd.pos
		wStrip.Anchored = true
		wStrip.CanCollide = false
		wStrip.Color = sd.color
		wStrip.Material = Enum.Material.Neon
		wStrip.Parent = Workspace
	end

	-- Pastel corner pillars
	local cornerPillars = {
		{ pos = Vector3.new(-100, LOBBY_WALL_HEIGHT / 2 + 1, 40),  color = Color3.fromRGB(255, 180, 210) },
		{ pos = Vector3.new(100, LOBBY_WALL_HEIGHT / 2 + 1, 40),   color = Color3.fromRGB(180, 210, 255) },
		{ pos = Vector3.new(-100, LOBBY_WALL_HEIGHT / 2 + 1, 180), color = Color3.fromRGB(255, 240, 180) },
		{ pos = Vector3.new(100, LOBBY_WALL_HEIGHT / 2 + 1, 180),  color = Color3.fromRGB(190, 255, 210) },
	}
	for ci, cp in ipairs(cornerPillars) do
		local pillar = Instance.new("Part")
		pillar.Name = "LobbyCornerPillar_" .. ci
		pillar.Size = Vector3.new(3, LOBBY_WALL_HEIGHT + 2, 3)
		pillar.Position = cp.pos
		pillar.Anchored = true
		pillar.CanCollide = true
		pillar.Color = Color3.fromRGB(240, 230, 250)
		pillar.Material = Enum.Material.SmoothPlastic
		pillar.Parent = Workspace

		-- Neon glow strip running up the pillar
		local pillarGlow = Instance.new("Part")
		pillarGlow.Name = "LobbyCornerGlow_" .. ci
		pillarGlow.Size = Vector3.new(0.6, LOBBY_WALL_HEIGHT + 2, 0.6)
		pillarGlow.Position = cp.pos
		pillarGlow.Anchored = true
		pillarGlow.CanCollide = false
		pillarGlow.Color = cp.color
		pillarGlow.Material = Enum.Material.Neon
		pillarGlow.Parent = Workspace

		-- Glowing orb on top
		local topOrb = Instance.new("Part")
		topOrb.Name = "LobbyCornerOrb_" .. ci
		topOrb.Shape = Enum.PartType.Ball
		topOrb.Size = Vector3.new(4, 4, 4)
		topOrb.Position = cp.pos + Vector3.new(0, LOBBY_WALL_HEIGHT / 2 + 2, 0)
		topOrb.Anchored = true
		topOrb.CanCollide = false
		topOrb.Color = cp.color
		topOrb.Material = Enum.Material.Neon
		topOrb.Parent = Workspace
	end

	-- Pastel top trim / crown molding
	local topTrims = {
		{ size = Vector3.new(200, 1, 3), pos = Vector3.new(0, LOBBY_WALL_HEIGHT + 1.5, 40),  color = Color3.fromRGB(220, 190, 255) },
		{ size = Vector3.new(200, 1, 3), pos = Vector3.new(0, LOBBY_WALL_HEIGHT + 1.5, 180), color = Color3.fromRGB(220, 190, 255) },
		{ size = Vector3.new(3, 1, 140), pos = Vector3.new(-100, LOBBY_WALL_HEIGHT + 1.5, 110), color = Color3.fromRGB(200, 180, 240) },
		{ size = Vector3.new(3, 1, 140), pos = Vector3.new(100, LOBBY_WALL_HEIGHT + 1.5, 110),  color = Color3.fromRGB(200, 180, 240) },
	}
	for ti, td in ipairs(topTrims) do
		local trim = Instance.new("Part")
		trim.Name = "LobbyTopTrim_" .. ti
		trim.Size = td.size
		trim.Position = td.pos
		trim.Anchored = true
		trim.CanCollide = false
		trim.Color = td.color
		trim.Material = Enum.Material.Neon
		trim.Transparency = 0.3
		trim.Parent = Workspace
	end

	-- ── Ceiling ──────────────────────────────────────────────────────────
	local ceilingY = LOBBY_WALL_HEIGHT + 2
	-- Main ceiling panel — soft pastel lavender
	local ceiling = Instance.new("Part")
	ceiling.Name = "LobbyCeiling"
	ceiling.Size = Vector3.new(200, 2, 140)
	ceiling.Position = Vector3.new(0, ceilingY, 110)
	ceiling.Anchored = true
	ceiling.CanCollide = true
	ceiling.Color = Color3.fromRGB(230, 220, 245)
	ceiling.Material = Enum.Material.SmoothPlastic
	ceiling.Parent = Workspace

	-- Recessed neon light panels in the ceiling (pastel glow strips)
	local ceilingLightColors = {
		Color3.fromRGB(255, 200, 220),
		Color3.fromRGB(200, 230, 255),
		Color3.fromRGB(255, 245, 200),
		Color3.fromRGB(210, 255, 220),
		Color3.fromRGB(230, 210, 255),
	}
	for li = 1, 5 do
		local light = Instance.new("Part")
		light.Name = "CeilingLight_" .. li
		light.Size = Vector3.new(120, 0.5, 4)
		light.Position = Vector3.new(0, ceilingY - 1.2, 55 + li * 20)
		light.Anchored = true
		light.CanCollide = false
		light.Color = ceilingLightColors[li]
		light.Material = Enum.Material.Neon
		light.Transparency = 0.1
		light.Parent = Workspace
	end

	-- Circular neon chandelier rings
	local chandelierColors = {
		Color3.fromRGB(255, 190, 220),
		Color3.fromRGB(190, 220, 255),
		Color3.fromRGB(220, 200, 255),
	}
	for ri = 1, 3 do
		local ringX = -50 + (ri - 1) * 50
		-- Outer ring
		local ring = Instance.new("Part")
		ring.Name = "CeilingRing_" .. ri
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(1, 16, 16)
		ring.CFrame = CFrame.new(ringX, ceilingY - 4, 110) * CFrame.Angles(0, 0, math.rad(90))
		ring.Anchored = true
		ring.CanCollide = false
		ring.Color = chandelierColors[ri]
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.3
		ring.Parent = Workspace

		-- Inner glowing core
		local core = Instance.new("Part")
		core.Name = "CeilingCore_" .. ri
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(5, 5, 5)
		core.Position = Vector3.new(ringX, ceilingY - 4, 110)
		core.Anchored = true
		core.CanCollide = false
		core.Color = chandelierColors[ri]
		core.Material = Enum.Material.Neon
		core.Transparency = 0.1
		core.Parent = Workspace

		-- SpotLight shining down from each chandelier
		local spot = Instance.new("SpotLight")
		spot.Name = "ChandelierSpot_" .. ri
		spot.Brightness = 0.6
		spot.Range = 40
		spot.Angle = 70
		spot.Color = Color3.fromRGB(255, 250, 240)
		spot.Face = Enum.NormalId.Bottom
		spot.Parent = core
	end

	-- ── Lighting: ceiling light strip PointLights ────────────────────────
	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name:match("^CeilingLight_") then
			local pl = Instance.new("PointLight")
			pl.Name = "StripLight"
			pl.Brightness = 0.4
			pl.Range = 35
			pl.Color = Color3.fromRGB(255, 250, 245)
			pl.Parent = child
		end
	end

	-- ── Lighting: warm fill lights around the lobby ──────────────────────
	local fillPositions = {
		Vector3.new(-60, 30, 70),
		Vector3.new(60, 30, 70),
		Vector3.new(-60, 30, 150),
		Vector3.new(60, 30, 150),
		Vector3.new(0, 45, 110),
	}
	for fi, fp in ipairs(fillPositions) do
		local fillPart = Instance.new("Part")
		fillPart.Name = "LobbyFillLight_" .. fi
		fillPart.Shape = Enum.PartType.Ball
		fillPart.Size = Vector3.new(2, 2, 2)
		fillPart.Position = fp
		fillPart.Anchored = true
		fillPart.CanCollide = false
		fillPart.Color = Color3.fromRGB(255, 245, 230)
		fillPart.Material = Enum.Material.Neon
		fillPart.Transparency = 0.95
		fillPart.Parent = Workspace

		local pl = Instance.new("PointLight")
		pl.Name = "FillLight"
		pl.Brightness = 0.5
		pl.Range = 45
		pl.Color = Color3.fromRGB(255, 248, 240)
		pl.Parent = fillPart
	end

	-- ── Lighting: ground-level uplights along walls for indirect bounce ──
	local uplightPositions = {
		Vector3.new(-90, 2, 70),  Vector3.new(-90, 2, 110), Vector3.new(-90, 2, 150),
		Vector3.new(90, 2, 70),   Vector3.new(90, 2, 110),  Vector3.new(90, 2, 150),
		Vector3.new(-40, 2, 42),  Vector3.new(0, 2, 42),    Vector3.new(40, 2, 42),
		Vector3.new(-40, 2, 178), Vector3.new(0, 2, 178),   Vector3.new(40, 2, 178),
	}
	for ui, up in ipairs(uplightPositions) do
		local upPart = Instance.new("Part")
		upPart.Name = "LobbyUplight_" .. ui
		upPart.Size = Vector3.new(3, 1, 3)
		upPart.Position = up
		upPart.Anchored = true
		upPart.CanCollide = false
		upPart.Color = Color3.fromRGB(255, 240, 220)
		upPart.Material = Enum.Material.Neon
		upPart.Transparency = 0.7
		upPart.Parent = Workspace

		local sl = Instance.new("SpotLight")
		sl.Name = "Uplight"
		sl.Brightness = 0.5
		sl.Range = 35
		sl.Angle = 90
		sl.Color = Color3.fromRGB(255, 245, 235)
		sl.Face = Enum.NormalId.Top
		sl.Parent = upPart
	end

	-- ── Floor grid lights — even illumination across the ground ──────────
	for gx = -80, 80, 40 do
		for gz = 50, 170, 30 do
			local floorLight = Instance.new("Part")
			floorLight.Name = "FloorGridLight"
			floorLight.Size = Vector3.new(1, 0.2, 1)
			floorLight.Position = Vector3.new(gx, 1.15, gz)
			floorLight.Anchored = true
			floorLight.CanCollide = false
			floorLight.Transparency = 1
			floorLight.Parent = Workspace

			local pl = Instance.new("PointLight")
			pl.Brightness = 0.8
			pl.Range = 30
			pl.Color = Color3.fromRGB(255, 250, 245)
			pl.Parent = floorLight
		end
	end

	for i, pos in ipairs(PAD_POSITIONS) do
		-- Floor part — raised above ground so Touched fires reliably
		local floor = Instance.new("Part")
		floor.Name        = "AreaFloor_" .. i
		floor.Size        = FLOOR_SIZE
		floor.CFrame      = CFrame.new(pos + Vector3.new(0, 1 + FLOOR_SIZE.Y / 2, 0))
		floor.Anchored    = true
		floor.CanCollide  = true
		floor.BrickColor  = PAD_COLORS[i]
		floor.Material    = Enum.Material.SmoothPlastic
		floor.Parent      = Workspace

		-- 4 walls: North, South, East, West (non-collidable so players walk through)
		local wallY = pos.Y + 1 + FLOOR_SIZE.Y + WALL_SIZE.Y / 2

		local wallOffsets = {
			{ cframe = CFrame.new(pos.X,                    wallY, pos.Z - FLOOR_SIZE.Z / 2), size = WALL_SIZE },
			{ cframe = CFrame.new(pos.X,                    wallY, pos.Z + FLOOR_SIZE.Z / 2), size = WALL_SIZE },
			{ cframe = CFrame.new(pos.X - FLOOR_SIZE.X / 2, wallY, pos.Z),                   size = Vector3.new(1, WALL_SIZE.Y, FLOOR_SIZE.Z) },
			{ cframe = CFrame.new(pos.X + FLOOR_SIZE.X / 2, wallY, pos.Z),                   size = Vector3.new(1, WALL_SIZE.Y, FLOOR_SIZE.Z) },
		}

		for wi, wallData in ipairs(wallOffsets) do
			local wall = Instance.new("Part")
			wall.Name         = "AreaWall_" .. i .. "_" .. wi
			wall.Size         = wallData.size
			wall.CFrame       = wallData.cframe
			wall.Anchored     = true
			wall.CanCollide   = false
			wall.Transparency = WALL_TRANSPARENCY
			wall.BrickColor   = PAD_COLORS[i]
			wall.Material     = Enum.Material.SmoothPlastic
			wall.Parent       = Workspace
		end

		-- Electric sign board: a physical post + neon panel with SurfaceGui
		local signHeight = 8
		local signWidth  = 10
		local signDepth  = 0.5

		-- Post (thin cylinder-like part)
		local post = Instance.new("Part")
		post.Name       = "AreaSignPost_" .. i
		post.Size       = Vector3.new(0.6, signHeight, 0.6)
		post.CFrame     = CFrame.new(pos.X, 1 + signHeight / 2, pos.Z - FLOOR_SIZE.Z / 2 - 2)
		post.Anchored   = true
		post.CanCollide = false
		post.Color      = Color3.fromRGB(40, 40, 40)
		post.Material   = Enum.Material.Metal
		post.Parent     = Workspace

		-- Sign panel (neon board)
		local panel = Instance.new("Part")
		panel.Name       = "AreaSignPanel_" .. i
		panel.Size       = Vector3.new(signWidth, 4, signDepth)
		panel.CFrame     = CFrame.new(pos.X, 1 + signHeight + 2, pos.Z - FLOOR_SIZE.Z / 2 - 2)
		panel.Anchored   = true
		panel.CanCollide = false
		panel.Color      = Color3.fromRGB(10, 10, 15)
		panel.Material   = Enum.Material.Neon
		panel.Parent     = Workspace

		-- SurfaceGui on the front face of the sign panel
		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name                 = "AreaSignGui_" .. i
		surfaceGui.Face                 = Enum.NormalId.Back -- faces toward Z+ (toward the player)
		surfaceGui.CanvasSize           = Vector2.new(400, 160)
		surfaceGui.LightInfluence       = 0
		surfaceGui.Brightness           = 1.5
		surfaceGui.Parent               = panel

		local signLabel = Instance.new("TextLabel")
		signLabel.Name                   = "SignLabel"
		signLabel.Size                   = UDim2.new(1, 0, 1, 0)
		signLabel.BackgroundTransparency = 1
		signLabel.Text                   = "Area " .. i
		signLabel.TextColor3             = PAD_COLORS[i].Color
		signLabel.TextScaled             = true
		signLabel.Font                   = Enum.Font.Code
		signLabel.Parent                 = surfaceGui

		-- Spawn CFrame slightly above pad centre
		local spawnCFrame = CFrame.new(pos + Vector3.new(0, 1 + FLOOR_SIZE.Y + SPAWN_Y_OFFSET, 0))

		areas[i] = {
			index               = i,
			status              = "EMPTY",
			occupants           = {},
			countdownRemaining  = 0,
			gameManager         = nil,
			roundReached        = 0,
			padFloor            = floor,
			spawnCFrame         = spawnCFrame,
			countdownGeneration = 0,
			dismissedPlayers    = {},
		}
	end

	-- ── Vibrant Robux Shop Building (rotated 90°, entrance faces -X toward player) ──
	local shopPos = Vector3.new(70, 0, 155)

	-- Shop floor platform (swapped X↔Z for 90° rotation: 30 wide, 40 deep)
	local shopFloor = Instance.new("Part")
	shopFloor.Name = "ShopFloor"
	shopFloor.Size = Vector3.new(30, 1, 40)
	shopFloor.Position = shopPos + Vector3.new(0, 1, 0)
	shopFloor.Anchored = true
	shopFloor.CanCollide = true
	shopFloor.Color = Color3.fromRGB(20, 10, 40)
	shopFloor.Material = Enum.Material.SmoothPlastic
	shopFloor.Parent = Workspace

	-- Neon border around shop floor (rotated)
	local borderParts = {
		{ size = Vector3.new(0.5, 0.3, 40), offset = Vector3.new(15, 1.6, 0) },
		{ size = Vector3.new(0.5, 0.3, 40), offset = Vector3.new(-15, 1.6, 0) },
		{ size = Vector3.new(30, 0.3, 0.5), offset = Vector3.new(0, 1.6, 20) },
		{ size = Vector3.new(30, 0.3, 0.5), offset = Vector3.new(0, 1.6, -20) },
	}
	local borderColors = {
		Color3.fromRGB(255, 50, 200),
		Color3.fromRGB(0, 220, 255),
		Color3.fromRGB(255, 220, 0),
		Color3.fromRGB(100, 255, 80),
	}
	for bi, bd in ipairs(borderParts) do
		local border = Instance.new("Part")
		border.Name = "ShopBorder_" .. bi
		border.Size = bd.size
		border.Position = shopPos + bd.offset
		border.Anchored = true
		border.CanCollide = false
		border.Color = borderColors[bi]
		border.Material = Enum.Material.Neon
		border.Parent = Workspace
	end

	-- Back wall (now at +X side, away from player)
	local backWall = Instance.new("Part")
	backWall.Name = "ShopBackWall"
	backWall.Size = Vector3.new(1, 14, 40)
	backWall.Position = shopPos + Vector3.new(15, 8, 0)
	backWall.Anchored = true
	backWall.CanCollide = true
	backWall.Color = Color3.fromRGB(120, 0, 200)
	backWall.Material = Enum.Material.Neon
	backWall.Parent = Workspace

	-- Side walls (now at ±Z, entrance is at -X toward player)
	local sideWallColors = {
		Color3.fromRGB(0, 180, 255),   -- front-left = cyan
		Color3.fromRGB(255, 50, 150),  -- front-right = pink
	}
	for si, side in ipairs({ -1, 1 }) do
		local sideWall = Instance.new("Part")
		sideWall.Name = "ShopSideWall_" .. (side == -1 and "L" or "R")
		sideWall.Size = Vector3.new(30, 14, 1)
		sideWall.Position = shopPos + Vector3.new(0, 8, 20 * side)
		sideWall.Anchored = true
		sideWall.CanCollide = true
		sideWall.Color = sideWallColors[si]
		sideWall.Material = Enum.Material.Neon
		sideWall.Transparency = 0.15
		sideWall.Parent = Workspace

		-- Neon strip on side wall edge (at entrance side, -X)
		local sideStrip = Instance.new("Part")
		sideStrip.Name = "ShopSideStrip_" .. (side == -1 and "L" or "R")
		sideStrip.Size = Vector3.new(0.5, 14, 0.5)
		sideStrip.Position = shopPos + Vector3.new(-15, 8, 20 * side)
		sideStrip.Anchored = true
		sideStrip.CanCollide = false
		sideStrip.Color = Color3.fromRGB(255, 220, 0)
		sideStrip.Material = Enum.Material.Neon
		sideStrip.Parent = Workspace
	end

	-- Roof (swapped dimensions for rotation)
	local roof = Instance.new("Part")
	roof.Name = "ShopRoof"
	roof.Size = Vector3.new(32, 1, 42)
	roof.Position = shopPos + Vector3.new(0, 15, 0)
	roof.Anchored = true
	roof.CanCollide = true
	roof.Color = Color3.fromRGB(80, 0, 160)
	roof.Material = Enum.Material.Neon
	roof.Transparency = 0.3
	roof.Parent = Workspace

	-- Neon roof trim (rotated)
	local roofTrimColors = {
		Color3.fromRGB(255, 80, 200),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(255, 200, 0),
		Color3.fromRGB(100, 255, 50),
	}
	local roofTrims = {
		{ size = Vector3.new(0.5, 0.5, 42), offset = Vector3.new(16, 15.5, 0) },
		{ size = Vector3.new(0.5, 0.5, 42), offset = Vector3.new(-16, 15.5, 0) },
		{ size = Vector3.new(32, 0.5, 0.5), offset = Vector3.new(0, 15.5, 21) },
		{ size = Vector3.new(32, 0.5, 0.5), offset = Vector3.new(0, 15.5, -21) },
	}
	for ri, rt in ipairs(roofTrims) do
		local trim = Instance.new("Part")
		trim.Name = "ShopRoofTrim_" .. ri
		trim.Size = rt.size
		trim.Position = shopPos + rt.offset
		trim.Anchored = true
		trim.CanCollide = false
		trim.Color = roofTrimColors[ri]
		trim.Material = Enum.Material.Neon
		trim.Parent = Workspace
	end

	-- Cartoon-style "SHOP" sign above entrance (facing -X toward player)
	-- Chunky colorful backing board (outermost, faces player at -X)
	local signBoard = Instance.new("Part")
	signBoard.Name = "ShopSignBoard"
	signBoard.Size = Vector3.new(2, 8, 26)
	signBoard.Position = shopPos + Vector3.new(-16, 20, 0)
	signBoard.Anchored = true
	signBoard.CanCollide = false
	signBoard.Color = Color3.fromRGB(255, 220, 0)
	signBoard.Material = Enum.Material.SmoothPlastic
	signBoard.Parent = Workspace

	-- Rounded border frame (behind the board)
	local signBorder = Instance.new("Part")
	signBorder.Name = "ShopSignBorder"
	signBorder.Size = Vector3.new(1.5, 9.5, 28)
	signBorder.Position = shopPos + Vector3.new(-14.5, 20, 0)
	signBorder.Anchored = true
	signBorder.CanCollide = false
	signBorder.Color = Color3.fromRGB(255, 80, 200)
	signBorder.Material = Enum.Material.Neon
	signBorder.Parent = Workspace

	-- Outer glow frame (furthest back)
	local signGlow = Instance.new("Part")
	signGlow.Name = "ShopSignGlow"
	signGlow.Size = Vector3.new(1, 11, 30)
	signGlow.Position = shopPos + Vector3.new(-13.5, 20, 0)
	signGlow.Anchored = true
	signGlow.CanCollide = false
	signGlow.Color = Color3.fromRGB(0, 200, 255)
	signGlow.Material = Enum.Material.Neon
	signGlow.Transparency = 0.4
	signGlow.Parent = Workspace

	-- SurfaceGui on the -X face (Left) so it faces the player
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "ShopSignGui"
	signGui.Face = Enum.NormalId.Left
	signGui.CanvasSize = Vector2.new(500, 150)
	signGui.LightInfluence = 0
	signGui.Brightness = 2
	signGui.Parent = signBoard

	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.new(1, 0, 1, 0)
	signText.BackgroundTransparency = 1
	signText.Text = "Shop"
	signText.TextColor3 = Color3.fromRGB(180, 30, 120)
	signText.TextScaled = true
	signText.Font = Enum.Font.FredokaOne
	signText.Parent = signGui

	-- Text stroke for cartoon outline effect
	local signStroke = Instance.new("UIStroke")
	signStroke.Color = Color3.fromRGB(255, 255, 255)
	signStroke.Thickness = 4
	signStroke.Parent = signText

	-- Decorative stars on each side of the sign (along Z axis now)
	for _, sz in ipairs({ -16, 16 }) do
		local star = Instance.new("Part")
		star.Name = "ShopSignStar"
		star.Shape = Enum.PartType.Ball
		star.Size = Vector3.new(3, 3, 3)
		star.Position = shopPos + Vector3.new(-15, 22, sz)
		star.Anchored = true
		star.CanCollide = false
		star.Color = Color3.fromRGB(255, 255, 100)
		star.Material = Enum.Material.Neon
		star.Parent = Workspace
	end

	-- Support posts holding the sign up from the roof (along Z axis)
	for _, sz in ipairs({ -10, 10 }) do
		local signPost = Instance.new("Part")
		signPost.Name = "ShopSignPost"
		signPost.Size = Vector3.new(1.5, 5, 1.5)
		signPost.Position = shopPos + Vector3.new(-15, 17, sz)
		signPost.Anchored = true
		signPost.CanCollide = false
		signPost.Color = Color3.fromRGB(100, 255, 80)
		signPost.Material = Enum.Material.Neon
		signPost.Parent = Workspace
	end

	-- Floating neon orbs for ambiance
	local orbColors = {
		Color3.fromRGB(255, 80, 200),
		Color3.fromRGB(0, 220, 255),
		Color3.fromRGB(255, 200, 0),
		Color3.fromRGB(100, 255, 80),
		Color3.fromRGB(180, 60, 255),
		Color3.fromRGB(255, 100, 50),
	}
	for oi = 1, 6 do
		local orb = Instance.new("Part")
		orb.Name = "ShopOrb_" .. oi
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(1.5, 1.5, 1.5)
		local angle = (oi / 6) * math.pi * 2
		orb.Position = shopPos + Vector3.new(math.cos(angle) * 14, 10 + math.sin(oi) * 2, math.sin(angle) * 10)
		orb.Anchored = true
		orb.CanCollide = false
		orb.Color = orbColors[oi]
		orb.Material = Enum.Material.Neon
		orb.Parent = Workspace
	end

	-- ── Double Money Pass Display ────────────────────────────────────────
	-- A physical pedestal with a spinning coin and ProximityPrompt

	-- Pedestal (shifted toward center of shop, offset in +X)
	local pedestal = Instance.new("Part")
	pedestal.Name = "ShopPedestal_DoubleMoney"
	pedestal.Size = Vector3.new(6, 4, 6)
	pedestal.Position = shopPos + Vector3.new(2, 3, 0)
	pedestal.Anchored = true
	pedestal.CanCollide = true
	pedestal.Color = Color3.fromRGB(40, 20, 80)
	pedestal.Material = Enum.Material.SmoothPlastic
	pedestal.Parent = Workspace

	local pedCorner = Instance.new("Part")
	pedCorner.Name = "PedestalTop"
	pedCorner.Size = Vector3.new(7, 0.5, 7)
	pedCorner.Position = shopPos + Vector3.new(2, 5.25, 0)
	pedCorner.Anchored = true
	pedCorner.CanCollide = false
	pedCorner.Color = Color3.fromRGB(255, 200, 0)
	pedCorner.Material = Enum.Material.Neon
	pedCorner.Parent = Workspace

	-- Giant spinning coin on top
	local coin = Instance.new("Part")
	coin.Name = "ShopCoin_DoubleMoney"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.8, 4, 4)
	coin.CFrame = CFrame.new(shopPos + Vector3.new(2, 8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	coin.Anchored = true
	coin.CanCollide = false
	coin.Color = Color3.fromRGB(255, 215, 0)
	coin.Material = Enum.Material.Neon
	coin.Parent = Workspace

	-- Glow ring around coin
	local glowRing = Instance.new("Part")
	glowRing.Name = "CoinGlow"
	glowRing.Shape = Enum.PartType.Ball
	glowRing.Size = Vector3.new(6, 6, 6)
	glowRing.Position = shopPos + Vector3.new(2, 8, 0)
	glowRing.Anchored = true
	glowRing.CanCollide = false
	glowRing.Color = Color3.fromRGB(255, 220, 50)
	glowRing.Material = Enum.Material.Neon
	glowRing.Transparency = 0.7
	glowRing.Parent = Workspace

	-- Info sign in front of pedestal (faces -X toward player, clearly visible)
	local infoPanel = Instance.new("Part")
	infoPanel.Name = "DoubleMoneyInfo"
	infoPanel.Size = Vector3.new(1, 4, 10)
	infoPanel.Position = shopPos + Vector3.new(-5, 4, 0)
	infoPanel.Anchored = true
	infoPanel.CanCollide = false
	infoPanel.Color = Color3.fromRGB(20, 10, 40)
	infoPanel.Material = Enum.Material.SmoothPlastic
	infoPanel.Parent = Workspace

	local infoGui = Instance.new("SurfaceGui")
	infoGui.Name = "DoubleMoneyGui"
	infoGui.Face = Enum.NormalId.Left
	infoGui.CanvasSize = Vector2.new(400, 150)
	infoGui.LightInfluence = 0
	infoGui.Brightness = 1.5
	infoGui.Parent = infoPanel

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 0.5, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "💰 2X MONEY 💰"
	titleLbl.TextColor3 = Color3.fromRGB(255, 220, 50)
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Parent = infoGui

	local priceLbl = Instance.new("TextLabel")
	priceLbl.Size = UDim2.new(1, 0, 0.5, 0)
	priceLbl.Position = UDim2.new(0, 0, 0.5, 0)
	priceLbl.BackgroundTransparency = 1
	priceLbl.Text = "R$ 100 — Double earnings today!"
	priceLbl.TextColor3 = Color3.fromRGB(200, 200, 220)
	priceLbl.TextScaled = true
	priceLbl.Font = Enum.Font.Gotham
	priceLbl.Parent = infoGui

	-- ProximityPrompt to trigger purchase
	local buyPrompt = Instance.new("ProximityPrompt")
	buyPrompt.Name = "BuyDoubleMoneyPrompt"
	buyPrompt.ActionText = "Buy 2X Money (R$100)"
	buyPrompt.ObjectText = "Double Money Pass"
	buyPrompt.HoldDuration = 0.5
	buyPrompt.MaxActivationDistance = 12
	buyPrompt.RequiresLineOfSight = false
	buyPrompt.Parent = pedestal

	-- Spin the coin continuously
	task.spawn(function()
		while coin and coin.Parent do
			local t = tick() * 2
			coin.CFrame = CFrame.new(shopPos + Vector3.new(2, 8 + math.sin(t) * 0.5, 0))
				* CFrame.Angles(0, t, math.rad(90))
			task.wait(0.03)
		end
	end)

	-- ── Decorative pillars with neon tops (rotated corners) ──────────────
	local pillarPositions = {
		Vector3.new(-13, 0, 18), Vector3.new(-13, 0, -18),
		Vector3.new(13, 0, 18), Vector3.new(13, 0, -18),
	}
	local pillarColors = {
		Color3.fromRGB(255, 50, 150),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(255, 200, 0),
		Color3.fromRGB(100, 255, 80),
	}
	for pi, pp in ipairs(pillarPositions) do
		local pillar = Instance.new("Part")
		pillar.Name = "ShopPillar_" .. pi
		pillar.Size = Vector3.new(2, 12, 2)
		pillar.Position = shopPos + pp + Vector3.new(0, 7, 0)
		pillar.Anchored = true
		pillar.CanCollide = true
		pillar.Color = Color3.fromRGB(30, 20, 50)
		pillar.Material = Enum.Material.SmoothPlastic
		pillar.Parent = Workspace

		local pillarTop = Instance.new("Part")
		pillarTop.Name = "ShopPillarTop_" .. pi
		pillarTop.Shape = Enum.PartType.Ball
		pillarTop.Size = Vector3.new(3, 3, 3)
		pillarTop.Position = shopPos + pp + Vector3.new(0, 14, 0)
		pillarTop.Anchored = true
		pillarTop.CanCollide = false
		pillarTop.Color = pillarColors[pi]
		pillarTop.Material = Enum.Material.Neon
		pillarTop.Parent = Workspace
	end
end

-- ---------------------------------------------------------------------------
-- Task 4.8: broadcastState — fires LobbyState to all clients
-- ---------------------------------------------------------------------------
local function broadcastState()
	local snapshots = {}
	for _, area in ipairs(areas) do
		table.insert(snapshots, {
			index         = area.index,
			status        = area.status,
			occupantCount = #area.occupants,
			countdown     = area.countdownRemaining,
		})
	end
	remotes.LobbyState:FireAllClients(snapshots)
end

-- Forward declaration so launchGame can reference onGameOver
local onGameOver

-- ---------------------------------------------------------------------------
-- Task 4.5: launchGame — transitions area to IN_GAME and starts GameManager
-- ---------------------------------------------------------------------------
local function launchGame(areaIndex: number)
	local area = areas[areaIndex]
	if area.status ~= "WAITING" then return end

	-- Validate all players have at least 1 turret in their loadout before launching
	for _, player in ipairs(area.occupants) do
		local userId = player.UserId
		local loadout = playerLoadouts[userId]
		if not loadout or #loadout < 1 then
			return
		end
	end

	area.status = "IN_GAME"

	-- Send each player their server-authoritative loadout before teleporting
	for _, player in ipairs(area.occupants) do
		local userId = player.UserId
		remotes.SendLoadout:FireClient(player, playerLoadouts[userId])
	end

	-- Teleport occupants to the game map
	for idx, player in ipairs(area.occupants) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local offset = Vector3.new((idx - 1) * 4, 0, 0)
				root.CFrame = MAP_SPAWN + offset
			end
		end
	end

	-- Create scoped GameManager instance (this also builds the map via MapBuilder)
	-- Task 4.4: Collect loadouts for all occupants and pass to GameManager
	local loadouts = {}
	for _, player in ipairs(area.occupants) do
		loadouts[player.UserId] = playerLoadouts[player.UserId]
	end
	local gm = GameManager.new(area.occupants, areaIndex, loadouts)
	gm.init()
	gm.onGameOver(function(roundReached)
		onGameOver(areaIndex, roundReached)
	end)
	gm.start()
	area.gameManager = gm

	broadcastState()
end

-- ---------------------------------------------------------------------------
-- Task 4.6: onGameOver — transitions area to RESULTS
-- ---------------------------------------------------------------------------
onGameOver = function(areaIndex: number, roundReached: number)
	local area = areas[areaIndex]
	area.status       = "RESULTS"
	area.roundReached = roundReached

	for _, player in ipairs(area.occupants) do
		remotes.LobbyShowResults:FireClient(player, roundReached, areaIndex)
	end

	broadcastState()
end

-- ---------------------------------------------------------------------------
-- Task 4.4: startCountdown — spawns a per-area countdown coroutine
-- ---------------------------------------------------------------------------
local function startCountdown(areaIndex: number)
	local area = areas[areaIndex]
	area.countdownRemaining = 10
	area.countdownGeneration += 1
	local generation = area.countdownGeneration

	task.spawn(function()
		while true do
			task.wait(1)

			-- Stale countdown check (cancelled by a newer generation or status change)
			if area.countdownGeneration ~= generation then break end
			if area.status ~= "WAITING" then break end

			area.countdownRemaining -= 1

			-- Broadcast tick to occupants
			for _, player in ipairs(area.occupants) do
				remotes.LobbyCountdown:FireClient(player, areaIndex, area.countdownRemaining)
			end

			broadcastState()

			if area.countdownRemaining <= 0 then
				if area.status == "WAITING" then
					launchGame(areaIndex)
				end
				break
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Task 4.2: handleJoin
-- ---------------------------------------------------------------------------
local function handleJoin(player: Player, areaIndex: number)
	local area = areas[areaIndex]

	-- Guard: in-game or results
	if area.status == "IN_GAME" or area.status == "RESULTS" then
		remotes.LobbyJoinResult:FireClient(player, false, "Game in progress")
		return
	end

	-- Guard: area full
	if #area.occupants >= 2 then
		remotes.LobbyJoinResult:FireClient(player, false, "Area is full")
		return
	end

	-- Guard: player already in any area (idempotent)
	for _, a in ipairs(areas) do
		for _, occ in ipairs(a.occupants) do
			if occ == player then
				return
			end
		end
	end

	-- Add player
	table.insert(area.occupants, player)
	remotes.LobbyJoinResult:FireClient(player, true)

	if #area.occupants == 1 then
		-- First player: start countdown
		area.status = "WAITING"
		startCountdown(areaIndex)
	elseif #area.occupants == 2 then
		-- Second player: launch immediately
		launchGame(areaIndex)
		return -- broadcastState called inside launchGame
	end

	broadcastState()
end

-- ---------------------------------------------------------------------------
-- Task 4.3: handleLeave
-- ---------------------------------------------------------------------------
local function handleLeave(player: Player, areaIndex: number)
	local area = areas[areaIndex]

	-- If in-game or results, don't remove — the game/results flow manages occupants
	if area.status == "IN_GAME" or area.status == "RESULTS" then
		return
	end

	-- Remove player from occupants
	local found = false
	for i, occ in ipairs(area.occupants) do
		if occ == player then
			table.remove(area.occupants, i)
			found = true
			break
		end
	end

	if not found then return end

	-- If area is now empty and was WAITING, cancel countdown and reset
	if #area.occupants == 0 and area.status == "WAITING" then
		area.countdownGeneration += 1 -- invalidates the running coroutine
		area.status             = "EMPTY"
		area.countdownRemaining = 0
	end

	broadcastState()
end

-- ---------------------------------------------------------------------------
-- Task 4.7: onPlayerDismissed
-- ---------------------------------------------------------------------------
local function onPlayerDismissed(player: Player, areaIndex: number)
	local area = areas[areaIndex]
	area.dismissedPlayers[player] = true

	-- Check if all occupants have dismissed
	local allDismissed = true
	for _, occ in ipairs(area.occupants) do
		if not area.dismissedPlayers[occ] then
			allDismissed = false
			break
		end
	end

	if not allDismissed then return end

	-- Teleport all occupants back to lobby spawn
	for _, occ in ipairs(area.occupants) do
		local char = occ.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = LOBBY_SPAWN
			end
		end
	end

	-- Send updated persistent coin balance + unlocks to each player so the shop reflects banked earnings
	for _, occ in ipairs(area.occupants) do
		local uid = occ.UserId
		local coins = EconomyManager.getPersistentCoins(uid)
		local unlocksForPlayer = playerUnlocks[uid] or { [1] = true }
		-- Send unlocks as flat array to avoid Roblox sparse-table serialization issues
		local unlockArray = {}
		for id, val in pairs(unlocksForPlayer) do
			if val then table.insert(unlockArray, id) end
		end
		remotes.ShopUpdate:FireClient(occ, unlockArray, coins)
	end

	-- Stop the game manager if it exists
	if area.gameManager then
		area.gameManager.stop()
	end

	-- Remove the game map visuals so the lobby stays clean
	local mapVisuals = Workspace:FindFirstChild("MapVisuals")
	if mapVisuals then
		mapVisuals:Destroy()
	end

	-- Reset area
	area.status              = "EMPTY"
	area.occupants           = {}
	area.countdownRemaining  = 0
	area.gameManager         = nil
	area.roundReached        = 0
	area.dismissedPlayers    = {}
	area.countdownGeneration += 1

	broadcastState()
end

function LobbyManager.setPlayerUnlocks(userId: number, unlocks: { [number]: boolean })
	playerUnlocks[userId] = unlocks
end

function LobbyManager.getPlayerUnlocks(userId: number): { [number]: boolean }
	return playerUnlocks[userId] or { [1] = true }
end

-- ---------------------------------------------------------------------------
-- LobbyManager.init
-- ---------------------------------------------------------------------------
function LobbyManager.init()
	DataManager.init()

	-- Ensure Remotes folder exists and create lobby remotes
	remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name   = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local remoteNames = {
		"LobbyState", "LobbyCountdown", "LobbyJoinResult",
		"LobbyReturnToLobby", "LobbyShowResults",
		-- Turret system remotes (Task 4.5)
		"BuyTurret", "BuyTurretResult", "SetLoadout", "SetLoadoutResult",
		"ShopUpdate", "SendLoadout", "PlaceTurret", "PlaceTurretResult", "TurretPlaced",
		"UpgradeTurret", "UpgradeTurretResult", "TurretUpgraded",
		"SessionCoinsUpdate", "KillEarningsUpdate", "TurretGameOver",
	}
	for _, name in ipairs(remoteNames) do
		if not remotes:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name   = name
			r.Parent = remotes
		end
	end

	buildPads()

	-- Create a SpawnLocation at the lobby so players don't drop from the sky
	-- Face toward the pads (negative Z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name       = "LobbySpawn"
	spawn.Size       = Vector3.new(12, 1, 12)
	spawn.CFrame     = CFrame.lookAt(Vector3.new(0, 1, 140), Vector3.new(0, 1, 110))
	spawn.Anchored   = true
	spawn.CanCollide = true
	spawn.Transparency = 1
	spawn.Parent     = Workspace

	-- Task 4.11: Wire Touched / TouchEnded on each pad floor
	-- Use per-pad part tracking to debounce: only join on first touch, only leave
	-- when ALL of a character's parts have stopped touching.
	for i, area in ipairs(areas) do
		local floor = area.padFloor
		-- touchingParts[player] = { [BasePart] = true }
		local touchingParts: { [Player]: { [BasePart]: boolean } } = {}

		floor.Touched:Connect(function(part)
			local character = part.Parent
			if not character then return end
			if not character:FindFirstChildOfClass("Humanoid") then return end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then return end

			if not touchingParts[player] then
				touchingParts[player] = {}
			end
			local isFirstTouch = next(touchingParts[player]) == nil
			touchingParts[player][part] = true

			if isFirstTouch then
				handleJoin(player, i)
			end
		end)

		floor.TouchEnded:Connect(function(part)
			local character = part.Parent
			if not character then return end
			if not character:FindFirstChildOfClass("Humanoid") then return end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then return end

			if touchingParts[player] then
				touchingParts[player][part] = nil
				if next(touchingParts[player]) == nil then
					touchingParts[player] = nil
					handleLeave(player, i)
				end
			end
		end)
	end

	-- Task 4.9: PlayerRemoving — remove from any area they occupy
	Players.PlayerRemoving:Connect(function(player)
		for _, area in ipairs(areas) do
			for _, occ in ipairs(area.occupants) do
				if occ == player then
					handleLeave(player, area.index)
					break
				end
			end
		end

		local userId = player.UserId
		DataManager.savePlayer(userId)
		DataManager.removePlayer(userId)
	end)

	-- Task 4.10: PlayerAdded — send current state to new player
	Players.PlayerAdded:Connect(function(player)
		task.wait() -- brief yield so remotes are ready

		local userId = player.UserId
		DataManager.loadPlayer(player)
		playerLoadouts[userId] = {}

		-- Send initial unlocks + persistent coin balance to the client
		-- Small delay to ensure client UI has wired up ShopUpdate listener
		task.delay(2, function()
			local unlocksForPlayer = playerUnlocks[userId] or { [1] = true }
			-- Send unlocks as flat array to avoid Roblox sparse-table serialization issues
			local unlockArray = {}
			for id, val in pairs(unlocksForPlayer) do
				if val then table.insert(unlockArray, id) end
			end
			local coins = EconomyManager.getPersistentCoins(userId)
			remotes.ShopUpdate:FireClient(player, unlockArray, coins)
		end)

		broadcastState()
		-- Also fire directly to the new player
		local snapshots = {}
		for _, area in ipairs(areas) do
			table.insert(snapshots, {
				index         = area.index,
				status        = area.status,
				occupantCount = #area.occupants,
				countdown     = area.countdownRemaining,
			})
		end
		remotes.LobbyState:FireClient(player, snapshots)
	end)

	-- Task 4.12: LobbyReturnToLobby remote
	remotes.LobbyReturnToLobby.OnServerEvent:Connect(function(player, areaIndex)
		-- Find the actual area the player is in (in case client sends wrong index)
		local actualArea = nil
		for _, area in ipairs(areas) do
			for _, occ in ipairs(area.occupants) do
				if occ == player then
					actualArea = area.index
					break
				end
			end
			if actualArea then break end
		end
		if actualArea then
			onPlayerDismissed(player, actualArea)
		elseif areaIndex then
			onPlayerDismissed(player, areaIndex)
		end
	end)

	-- Task 4.2: BuyTurret remote handler
	remotes.BuyTurret.OnServerEvent:Connect(function(player, turretTypeId)
		local userId = player.UserId
		local unlocks = playerUnlocks[userId]
		if not unlocks then return end

		-- Validate turret type exists
		local turretType = TurretData.getTurretById(turretTypeId)
		if not turretType then
			remotes.BuyTurretResult:FireClient(player, false, "Invalid turret type")
			return
		end

		-- Validate not already unlocked
		if unlocks[turretTypeId] then
			remotes.BuyTurretResult:FireClient(player, false, "Already unlocked")
			return
		end

		-- Validate and deduct persistent coins
		local success = EconomyManager.spendPersistentCoins(userId, turretType.shopPrice)
		if not success then
			remotes.BuyTurretResult:FireClient(player, false, "Not enough persistent coins")
			return
		end

		-- Unlock the turret
		unlocks[turretTypeId] = true
		DataManager.markDirty(userId)
		remotes.BuyTurretResult:FireClient(player, true)
		-- Send unlocks as a flat array of ids to avoid Roblox sparse-table serialization issues
		local unlockArray = {}
		for id, val in pairs(unlocks) do
			if val then table.insert(unlockArray, id) end
		end
		remotes.ShopUpdate:FireClient(player, unlockArray, EconomyManager.getPersistentCoins(userId))
	end)

	-- Task 4.3: SetLoadout remote handler
	remotes.SetLoadout.OnServerEvent:Connect(function(player, turretIds)
		local userId = player.UserId
		local unlocks = playerUnlocks[userId]
		if not unlocks then return end

		-- Validate 1-3 turret ids
		if type(turretIds) ~= "table" or #turretIds < 1 or #turretIds > 3 then
			remotes.SetLoadoutResult:FireClient(player, false, "Select 1 to 3 turrets")
			return
		end

		-- Validate all turret ids are unlocked
		for _, id in ipairs(turretIds) do
			if not unlocks[id] then
				remotes.SetLoadoutResult:FireClient(player, false, "Turret not unlocked")
				return
			end
		end

		-- Store loadout (1-3 entries)
		playerLoadouts[userId] = turretIds
		remotes.SetLoadoutResult:FireClient(player, true)
	end)

	-- Wire shop ProximityPrompt for double money gamepass
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggerPlayer)
		if prompt.Name == "BuyDoubleMoneyPrompt" then
			local passId = GamepassManager.getGamepassId()
			if passId > 0 then
				MarketplaceService:PromptGamePassPurchase(triggerPlayer, passId)
			else
				warn("[LobbyManager] Double money gamepass ID not set — update GamepassManager.luau")
			end
		end
	end)

	print("[LobbyManager] Initialized")
end

return LobbyManager
