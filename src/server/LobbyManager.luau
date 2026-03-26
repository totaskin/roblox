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
local RuneManager = require(script.Parent.RuneManager)
local EnemyPath = require(game.ReplicatedStorage.Shared.EnemyPath)

-- Pad-to-map assignment: Pad 1 → Greenfield, Pad 2 → Dustlands, Pad 3 → Random
local PAD_MAP_ASSIGNMENTS = {
	[1] = "Map1",
	[2] = "Map2",
	[3] = "RANDOM",
}

-- Sign labels displayed on each pad
local PAD_SIGN_LABELS = {
	[1] = "Greenfield",
	[2] = "Dustlands",
	[3] = "Random",
}

-- Difficulty settings per area (1=Easy, 2=Medium, 3=Hard)
-- enemyMult: multiplier for enemy health
-- rewardMult: multiplier for kill rewards
-- startCoins: starting session coins
local AREA_DIFFICULTY = {
	[1] = { name = "Easy",   enemyMult = 1.0, rewardMult = 1.0, startCoins = 150 },
	[2] = { name = "Medium", enemyMult = 1.5, rewardMult = 1.5, startCoins = 120 },
	[3] = { name = "Hard",   enemyMult = 2.5, rewardMult = 2.5, startCoins = 100 },
}

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
	BrickColor.new("Bright green"),
	BrickColor.new("Bright blue"),
	BrickColor.new("Bright red"),
}

local FLOOR_SIZE        = Vector3.new(20, 2, 20)
local WALL_SIZE         = Vector3.new(20, 6, 1)
local WALL_TRANSPARENCY = 0.7
local SPAWN_Y_OFFSET    = 1
local LOBBY_SPAWN       = CFrame.new(0, 2, 130)

-- Game map world offset (must match the offset passed to MapBuilder.build in GameManager)
local MAP_OFFSET = Vector3.new(0, 0, -10000)

-- Internal state
local areas: { AreaState } = {}
local remotes: Folder

-- Turret system state (Task 4.1)
local playerUnlocks: { [number]: { [number]: boolean } } = {}
local playerLoadouts: { [number]: { number } } = {}

-- Leaderboard display references (for updating)
local leaderboardGuis: { [string]: SurfaceGui } = {}

-- Update leaderboard display panels with current data from DataManager
local function updateLeaderboardDisplays()
	for difficulty, surfaceGui in pairs(leaderboardGuis) do
		local entries = DataManager.getLeaderboard(difficulty)
		local entriesFrame = surfaceGui:FindFirstChild("Entries")
		if not entriesFrame then continue end
		
		for i = 1, 10 do
			local entryLabel = entriesFrame:FindFirstChild("Entry_" .. i)
			if entryLabel then
				local entry = entries[i]
				if entry then
					entryLabel.Text = i .. ". " .. entry.displayName .. " - Round " .. entry.round
					-- Gold/silver/bronze colors for top 3
					if i == 1 then
						entryLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
					elseif i == 2 then
						entryLabel.TextColor3 = Color3.fromRGB(192, 192, 192)
					elseif i == 3 then
						entryLabel.TextColor3 = Color3.fromRGB(205, 127, 50)
					else
						entryLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
					end
				else
					entryLabel.Text = i .. ". ---"
					entryLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
				end
			end
		end
	end
end

local LobbyManager = {}

-- ---------------------------------------------------------------------------
-- buildPads: constructs the 3 physical area pads in the world.
-- ---------------------------------------------------------------------------
local function buildPads()
	-- Build a large vibrant lobby ground
	-- Build a tiled LEGO-style lobby ground (small parts so studs cover the whole surface)
	local TILE_SIZE = 8
	local groundY = 0.5
	for tx = -96, 96, TILE_SIZE do
		for tz = 42, 176, TILE_SIZE do
			local tile = Instance.new("Part")
			tile.Name = "LobbyTile"
			tile.Size = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
			tile.CFrame = CFrame.new(tx + TILE_SIZE / 2, groundY, tz + TILE_SIZE / 2)
			tile.Anchored = true
			tile.CanCollide = true
			tile.Material = Enum.Material.Plastic
			tile.Color = Color3.fromRGB(30, 200, 30)
			tile.TopSurface = Enum.SurfaceType.Studs
			tile.BottomSurface = Enum.SurfaceType.Smooth
			tile.Parent = Workspace
		end
	end

	-- Colorful floor accents — neon strips along the ground
	local stripColors = {
		Color3.fromRGB(40, 180, 40),
		Color3.fromRGB(50, 210, 50),
		Color3.fromRGB(35, 170, 35),
		Color3.fromRGB(45, 200, 45),
		Color3.fromRGB(55, 190, 55),
	}
	for si = 1, 5 do
		local strip = Instance.new("Part")
		strip.Name = "FloorStrip_" .. si
		strip.Size = Vector3.new(200, 0.1, 2)
		strip.Position = Vector3.new(0, 1.05, 50 + si * 18)
		strip.Anchored = true
		strip.CanCollide = false
		strip.Color = stripColors[si]
		strip.Material = Enum.Material.Plastic
		strip.Parent = Workspace
	end

	-- ── Vibrant Lobby Walls ──────────────────────────────────────────────
	local LOBBY_WALL_HEIGHT = 64
	local lobbyWalls = {
		{ pos = Vector3.new(0, LOBBY_WALL_HEIGHT / 2 + 1, 40),    size = Vector3.new(200, LOBBY_WALL_HEIGHT, 2), color = Color3.fromRGB(200, 120, 60) },  -- front — orange brick
		{ pos = Vector3.new(0, LOBBY_WALL_HEIGHT / 2 + 1, 180),   size = Vector3.new(200, LOBBY_WALL_HEIGHT, 2), color = Color3.fromRGB(200, 120, 60) },  -- back — orange brick
		{ pos = Vector3.new(-100, LOBBY_WALL_HEIGHT / 2 + 1, 110), size = Vector3.new(2, LOBBY_WALL_HEIGHT, 140), color = Color3.fromRGB(200, 120, 60) }, -- left — orange brick
		{ pos = Vector3.new(100, LOBBY_WALL_HEIGHT / 2 + 1, 110),  size = Vector3.new(2, LOBBY_WALL_HEIGHT, 140), color = Color3.fromRGB(200, 120, 60) }, -- right — orange brick
	}
	for wi, wallInfo in ipairs(lobbyWalls) do
		local bWall = Instance.new("Part")
		bWall.Name         = "LobbyWall_" .. wi
		bWall.Size         = wallInfo.size
		bWall.Position     = wallInfo.pos
		bWall.Anchored     = true
		bWall.CanCollide   = true
		bWall.Color        = wallInfo.color
		bWall.Material     = Enum.Material.Brick
		bWall.Transparency = 0.15
		bWall.Parent       = Workspace
	end

	-- Pastel neon accent strips — spread evenly up the tall walls
	local stripHeights = { 5, 15, 25, 35, 45, 55, 63 }
	local frontBackColors = {
		Color3.fromRGB(50, 130, 220), Color3.fromRGB(50, 130, 220),
		Color3.fromRGB(50, 130, 220), Color3.fromRGB(50, 130, 220),
		Color3.fromRGB(50, 130, 220), Color3.fromRGB(50, 130, 220),
		Color3.fromRGB(50, 130, 220),
	}
	local sideColors = {
		Color3.fromRGB(50, 130, 220), Color3.fromRGB(50, 130, 220),
		Color3.fromRGB(50, 130, 220), Color3.fromRGB(50, 130, 220),
		Color3.fromRGB(50, 130, 220), Color3.fromRGB(50, 130, 220),
		Color3.fromRGB(50, 130, 220),
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

	-- ── Weekly Leaderboards on Front Wall ─────────────────────────────────
	-- Three leaderboard panels on the front wall (Z=40), one per difficulty
	-- Positioned so players can see them while facing the pads
	local leaderboardConfigs = {
		{ difficulty = "Easy",   xPos = -55, color = Color3.fromRGB(100, 255, 100) },
		{ difficulty = "Medium", xPos = 0,   color = Color3.fromRGB(255, 200, 50) },
		{ difficulty = "Hard",   xPos = 55,  color = Color3.fromRGB(255, 80, 80) },
	}
	
	for _, config in ipairs(leaderboardConfigs) do
		-- Backing panel - placed just in front of the wall (wall is at Z=40, thickness 2)
		local panel = Instance.new("Part")
		panel.Name = "Leaderboard_" .. config.difficulty
		panel.Size = Vector3.new(40, 50, 0.5)
		panel.Position = Vector3.new(config.xPos, 35, 42)
		panel.Anchored = true
		panel.CanCollide = false
		panel.Color = Color3.fromRGB(20, 20, 30)
		panel.Material = Enum.Material.SmoothPlastic
		panel.Parent = Workspace
		
		-- Neon border frame
		local borderColor = config.color
		local borders = {
			{ size = Vector3.new(42, 1, 0.5), offset = Vector3.new(0, 25.5, -0.5) },  -- top
			{ size = Vector3.new(42, 1, 0.5), offset = Vector3.new(0, -25.5, -0.5) }, -- bottom
			{ size = Vector3.new(1, 50, 0.5), offset = Vector3.new(-20.5, 0, -0.5) }, -- left
			{ size = Vector3.new(1, 50, 0.5), offset = Vector3.new(20.5, 0, -0.5) },  -- right
		}
		for bi, bd in ipairs(borders) do
			local border = Instance.new("Part")
			border.Name = "LeaderboardBorder_" .. config.difficulty .. "_" .. bi
			border.Size = bd.size
			border.Position = panel.Position + bd.offset
			border.Anchored = true
			border.CanCollide = false
			border.Color = borderColor
			border.Material = Enum.Material.Neon
			border.Parent = Workspace
		end
		
		-- Title bar
		local titleBar = Instance.new("Part")
		titleBar.Name = "LeaderboardTitle_" .. config.difficulty
		titleBar.Size = Vector3.new(38, 8, 0.5)
		titleBar.Position = panel.Position + Vector3.new(0, 21, -0.5)
		titleBar.Anchored = true
		titleBar.CanCollide = false
		titleBar.Color = borderColor
		titleBar.Material = Enum.Material.Neon
		titleBar.Transparency = 0.3
		titleBar.Parent = Workspace
		
		-- SurfaceGui for the leaderboard content
		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = "LeaderboardGui_" .. config.difficulty
		surfaceGui.Face = Enum.NormalId.Back
		surfaceGui.CanvasSize = Vector2.new(800, 1000)
		surfaceGui.LightInfluence = 0
		surfaceGui.Brightness = 1.5
		surfaceGui.Parent = panel
		
		-- Title label
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, 0, 0.12, 0)
		titleLabel.Position = UDim2.new(0, 0, 0, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = "🏆 " .. config.difficulty .. " - Weekly Top 10"
		titleLabel.TextColor3 = borderColor
		titleLabel.TextScaled = true
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.Parent = surfaceGui
		
		-- Entries container
		local entriesFrame = Instance.new("Frame")
		entriesFrame.Name = "Entries"
		entriesFrame.Size = UDim2.new(1, 0, 0.85, 0)
		entriesFrame.Position = UDim2.new(0, 0, 0.14, 0)
		entriesFrame.BackgroundTransparency = 1
		entriesFrame.Parent = surfaceGui
		
		-- Create 10 entry slots
		for i = 1, 10 do
			local entryLabel = Instance.new("TextLabel")
			entryLabel.Name = "Entry_" .. i
			entryLabel.Size = UDim2.new(1, 0, 0.1, 0)
			entryLabel.Position = UDim2.new(0, 0, (i - 1) * 0.1, 0)
			entryLabel.BackgroundTransparency = 1
			entryLabel.Text = i .. ". ---"
			entryLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
			entryLabel.TextScaled = true
			entryLabel.Font = Enum.Font.Gotham
			entryLabel.TextXAlignment = Enum.TextXAlignment.Left
			entryLabel.Parent = entriesFrame
		end
		
		-- Store reference for updates
		leaderboardGuis[config.difficulty] = surfaceGui
	end
	
	-- "WEEKLY LEADERBOARDS" header above all three
	local headerPanel = Instance.new("Part")
	headerPanel.Name = "LeaderboardHeader"
	headerPanel.Size = Vector3.new(160, 10, 0.5)
	headerPanel.Position = Vector3.new(0, 62, 42)
	headerPanel.Anchored = true
	headerPanel.CanCollide = false
	headerPanel.Color = Color3.fromRGB(50, 50, 80)
	headerPanel.Material = Enum.Material.Neon
	headerPanel.Transparency = 0.5
	headerPanel.Parent = Workspace
	
	local headerGui = Instance.new("SurfaceGui")
	headerGui.Face = Enum.NormalId.Back
	headerGui.CanvasSize = Vector2.new(800, 50)
	headerGui.LightInfluence = 0
	headerGui.Brightness = 2
	headerGui.Parent = headerPanel
	
	local headerText = Instance.new("TextLabel")
	headerText.Size = UDim2.new(1, 0, 1, 0)
	headerText.BackgroundTransparency = 1
	headerText.Text = "⭐ WEEKLY LEADERBOARDS ⭐"
	headerText.TextColor3 = Color3.fromRGB(255, 220, 100)
	headerText.TextScaled = true
	headerText.Font = Enum.Font.FredokaOne
	headerText.Parent = headerGui

	-- Pastel corner pillars
	local cornerPillars = {
		{ pos = Vector3.new(-100, LOBBY_WALL_HEIGHT / 2 + 1, 40),  color = Color3.fromRGB(50, 130, 220) },
		{ pos = Vector3.new(100, LOBBY_WALL_HEIGHT / 2 + 1, 40),   color = Color3.fromRGB(50, 130, 220) },
		{ pos = Vector3.new(-100, LOBBY_WALL_HEIGHT / 2 + 1, 180), color = Color3.fromRGB(50, 130, 220) },
		{ pos = Vector3.new(100, LOBBY_WALL_HEIGHT / 2 + 1, 180),  color = Color3.fromRGB(50, 130, 220) },
	}
	for ci, cp in ipairs(cornerPillars) do
		local pillar = Instance.new("Part")
		pillar.Name = "LobbyCornerPillar_" .. ci
		pillar.Size = Vector3.new(3, LOBBY_WALL_HEIGHT + 2, 3)
		pillar.Position = cp.pos
		pillar.Anchored = true
		pillar.CanCollide = true
		pillar.Color = Color3.fromRGB(50, 130, 220)
		pillar.Material = Enum.Material.Brick
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
		{ size = Vector3.new(200, 1, 3), pos = Vector3.new(0, LOBBY_WALL_HEIGHT + 1.5, 40),  color = Color3.fromRGB(50, 130, 220) },
		{ size = Vector3.new(200, 1, 3), pos = Vector3.new(0, LOBBY_WALL_HEIGHT + 1.5, 180), color = Color3.fromRGB(50, 130, 220) },
		{ size = Vector3.new(3, 1, 140), pos = Vector3.new(-100, LOBBY_WALL_HEIGHT + 1.5, 110), color = Color3.fromRGB(50, 130, 220) },
		{ size = Vector3.new(3, 1, 140), pos = Vector3.new(100, LOBBY_WALL_HEIGHT + 1.5, 110),  color = Color3.fromRGB(50, 130, 220) },
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

		-- Build sign text with difficulty info
		local difficulty = AREA_DIFFICULTY[i]
		local mapLabel = PAD_SIGN_LABELS[i] or ("Area " .. i)
		local diffLabel = difficulty and difficulty.name or ""
		local rewardInfo = difficulty and string.format(" (%.0fx rewards)", difficulty.rewardMult) or ""

		local signLabel = Instance.new("TextLabel")
		signLabel.Name                   = "SignLabel"
		signLabel.Size                   = UDim2.new(1, 0, 0.6, 0)
		signLabel.BackgroundTransparency = 1
		signLabel.Text                   = mapLabel
		signLabel.TextColor3             = PAD_COLORS[i].Color
		signLabel.TextScaled             = true
		signLabel.Font                   = Enum.Font.Code
		signLabel.Parent                 = surfaceGui

		-- Difficulty sub-label
		local difficultyLabel = Instance.new("TextLabel")
		difficultyLabel.Name                   = "DifficultyLabel"
		difficultyLabel.Size                   = UDim2.new(1, 0, 0.4, 0)
		difficultyLabel.Position               = UDim2.new(0, 0, 0.6, 0)
		difficultyLabel.BackgroundTransparency = 1
		difficultyLabel.Text                   = diffLabel .. rewardInfo
		difficultyLabel.TextColor3             = Color3.fromRGB(255, 255, 200)
		difficultyLabel.TextScaled             = true
		difficultyLabel.Font                   = Enum.Font.Gotham
		difficultyLabel.Parent                 = surfaceGui

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

		-- ── Disco floor tiles on top of pad ──────────────────────────────────
		local TILE_SIZE = 4
		local tileY = pos.Y + 1 + FLOOR_SIZE.Y + 0.05 -- just above the floor surface
		local discoTiles: { Part } = {}
		local halfX = FLOOR_SIZE.X / 2
		local halfZ = FLOOR_SIZE.Z / 2

		for tx = -halfX + TILE_SIZE / 2, halfX - TILE_SIZE / 2, TILE_SIZE do
			for tz = -halfZ + TILE_SIZE / 2, halfZ - TILE_SIZE / 2, TILE_SIZE do
				local tile = Instance.new("Part")
				tile.Name = "DiscoTile"
				tile.Size = Vector3.new(TILE_SIZE - 0.3, 0.15, TILE_SIZE - 0.3)
				tile.Position = Vector3.new(pos.X + tx, tileY, pos.Z + tz)
				tile.Anchored = true
				tile.CanCollide = false
				tile.Material = Enum.Material.Neon
				tile.Color = PAD_COLORS[i].Color
				tile.Transparency = 0.85
				tile.Parent = Workspace
				table.insert(discoTiles, tile)
			end
		end

		-- Disco color palette
		local discoColors = {
			Color3.fromRGB(255, 50, 200),
			Color3.fromRGB(0, 220, 255),
			Color3.fromRGB(255, 220, 0),
			Color3.fromRGB(100, 255, 80),
			Color3.fromRGB(180, 60, 255),
			Color3.fromRGB(255, 100, 50),
			Color3.fromRGB(50, 130, 255),
			Color3.fromRGB(255, 50, 80),
		}

		-- Animate disco tiles: cycle colors when pad has occupants
		local areaRef = areas[i]
		task.spawn(function()
			local tick_counter = 0
			while true do
				task.wait(0.3)
				if #areaRef.occupants > 0 and areaRef.status ~= "IN_GAME" then
					tick_counter += 1
					for ti, tile in ipairs(discoTiles) do
						local colorIdx = ((ti + tick_counter) % #discoColors) + 1
						tile.Color = discoColors[colorIdx]
						tile.Transparency = 0.2
					end
				else
					-- Idle: dim tiles back to pad color
					for _, tile in ipairs(discoTiles) do
						tile.Color = PAD_COLORS[i].Color
						tile.Transparency = 0.85
					end
				end
			end
		end)
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
	priceLbl.Text = "R$ 100 — Double earnings permanently!"
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

	-- ── Double Damage Pass Display ────────────────────────────────────────
	-- A physical pedestal with a spinning sword and ProximityPrompt

	-- Pedestal (next to double money, offset in +X and +Z)
	local damagePedestal = Instance.new("Part")
	damagePedestal.Name = "ShopPedestal_DoubleDamage"
	damagePedestal.Size = Vector3.new(6, 4, 6)
	damagePedestal.Position = shopPos + Vector3.new(2, 3, -12)
	damagePedestal.Anchored = true
	damagePedestal.CanCollide = true
	damagePedestal.Color = Color3.fromRGB(40, 10, 10)
	damagePedestal.Material = Enum.Material.SmoothPlastic
	damagePedestal.Parent = Workspace

	local damagePedCorner = Instance.new("Part")
	damagePedCorner.Name = "DamagePedestalTop"
	damagePedCorner.Size = Vector3.new(7, 0.5, 7)
	damagePedCorner.Position = shopPos + Vector3.new(2, 5.25, -12)
	damagePedCorner.Anchored = true
	damagePedCorner.CanCollide = false
	damagePedCorner.Color = Color3.fromRGB(255, 80, 80)
	damagePedCorner.Material = Enum.Material.Neon
	damagePedCorner.Parent = Workspace

	-- Sword model on top (blade + handle)
	local swordBlade = Instance.new("Part")
	swordBlade.Name = "ShopSword_Blade"
	swordBlade.Size = Vector3.new(0.4, 4, 0.8)
	swordBlade.CFrame = CFrame.new(shopPos + Vector3.new(2, 9, -12))
	swordBlade.Anchored = true
	swordBlade.CanCollide = false
	swordBlade.Color = Color3.fromRGB(200, 200, 220)
	swordBlade.Material = Enum.Material.Metal
	swordBlade.Parent = Workspace

	local swordHandle = Instance.new("Part")
	swordHandle.Name = "ShopSword_Handle"
	swordHandle.Size = Vector3.new(0.3, 1.2, 0.3)
	swordHandle.CFrame = CFrame.new(shopPos + Vector3.new(2, 6.4, -12))
	swordHandle.Anchored = true
	swordHandle.CanCollide = false
	swordHandle.Color = Color3.fromRGB(80, 50, 30)
	swordHandle.Material = Enum.Material.Wood
	swordHandle.Parent = Workspace

	local swordGuard = Instance.new("Part")
	swordGuard.Name = "ShopSword_Guard"
	swordGuard.Size = Vector3.new(0.3, 0.3, 1.5)
	swordGuard.CFrame = CFrame.new(shopPos + Vector3.new(2, 7, -12))
	swordGuard.Anchored = true
	swordGuard.CanCollide = false
	swordGuard.Color = Color3.fromRGB(255, 200, 50)
	swordGuard.Material = Enum.Material.Metal
	swordGuard.Parent = Workspace

	-- Glow ring around sword
	local damageGlowRing = Instance.new("Part")
	damageGlowRing.Name = "SwordGlow"
	damageGlowRing.Shape = Enum.PartType.Ball
	damageGlowRing.Size = Vector3.new(5, 5, 5)
	damageGlowRing.Position = shopPos + Vector3.new(2, 8, -12)
	damageGlowRing.Anchored = true
	damageGlowRing.CanCollide = false
	damageGlowRing.Color = Color3.fromRGB(255, 100, 100)
	damageGlowRing.Material = Enum.Material.Neon
	damageGlowRing.Transparency = 0.7
	damageGlowRing.Parent = Workspace

	-- Info sign in front of pedestal (faces -X toward player)
	local damageInfoPanel = Instance.new("Part")
	damageInfoPanel.Name = "DoubleDamageInfo"
	damageInfoPanel.Size = Vector3.new(1, 4, 10)
	damageInfoPanel.Position = shopPos + Vector3.new(-5, 4, -12)
	damageInfoPanel.Anchored = true
	damageInfoPanel.CanCollide = false
	damageInfoPanel.Color = Color3.fromRGB(40, 10, 10)
	damageInfoPanel.Material = Enum.Material.SmoothPlastic
	damageInfoPanel.Parent = Workspace

	local damageInfoGui = Instance.new("SurfaceGui")
	damageInfoGui.Name = "DoubleDamageGui"
	damageInfoGui.Face = Enum.NormalId.Left
	damageInfoGui.CanvasSize = Vector2.new(400, 150)
	damageInfoGui.LightInfluence = 0
	damageInfoGui.Brightness = 1.5
	damageInfoGui.Parent = damageInfoPanel

	local damageTitleLbl = Instance.new("TextLabel")
	damageTitleLbl.Size = UDim2.new(1, 0, 0.5, 0)
	damageTitleLbl.BackgroundTransparency = 1
	damageTitleLbl.Text = "⚔️ 2X DAMAGE ⚔️"
	damageTitleLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
	damageTitleLbl.TextScaled = true
	damageTitleLbl.Font = Enum.Font.GothamBold
	damageTitleLbl.Parent = damageInfoGui

	local damagePriceLbl = Instance.new("TextLabel")
	damagePriceLbl.Size = UDim2.new(1, 0, 0.5, 0)
	damagePriceLbl.Position = UDim2.new(0, 0, 0.5, 0)
	damagePriceLbl.BackgroundTransparency = 1
	damagePriceLbl.Text = "R$ 100 — Double damage permanently!"
	damagePriceLbl.TextColor3 = Color3.fromRGB(200, 200, 220)
	damagePriceLbl.TextScaled = true
	damagePriceLbl.Font = Enum.Font.Gotham
	damagePriceLbl.Parent = damageInfoGui

	-- ProximityPrompt to trigger purchase
	local buyDamagePrompt = Instance.new("ProximityPrompt")
	buyDamagePrompt.Name = "BuyDoubleDamagePrompt"
	buyDamagePrompt.ActionText = "Buy 2X Damage (R$100)"
	buyDamagePrompt.ObjectText = "Double Damage Pass"
	buyDamagePrompt.HoldDuration = 0.5
	buyDamagePrompt.MaxActivationDistance = 12
	buyDamagePrompt.RequiresLineOfSight = false
	buyDamagePrompt.Parent = damagePedestal

	-- Spin the sword continuously
	task.spawn(function()
		while swordBlade and swordBlade.Parent do
			local t = tick() * 2
			local baseY = shopPos.Y + 8 + math.sin(t) * 0.5
			local basePos = Vector3.new(shopPos.X + 2, baseY, shopPos.Z - 12)
			-- Rotate sword around Y axis
			swordBlade.CFrame = CFrame.new(basePos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, t, 0)
			swordHandle.CFrame = CFrame.new(basePos + Vector3.new(0, -1.6, 0)) * CFrame.Angles(0, t, 0)
			swordGuard.CFrame = CFrame.new(basePos + Vector3.new(0, -1, 0)) * CFrame.Angles(0, t, 0)
			task.wait(0.03)
		end
	end)

	-- ── Turret Shop Table ────────────────────────────────────────────────
	-- A physical table with a spinning turret model and ProximityPrompt

	-- Table pedestal (offset in +Z from double damage)
	local turretTablePedestal = Instance.new("Part")
	turretTablePedestal.Name = "ShopPedestal_TurretShop"
	turretTablePedestal.Size = Vector3.new(6, 4, 6)
	turretTablePedestal.Position = shopPos + Vector3.new(2, 3, 12)
	turretTablePedestal.Anchored = true
	turretTablePedestal.CanCollide = true
	turretTablePedestal.Color = Color3.fromRGB(20, 30, 50)
	turretTablePedestal.Material = Enum.Material.SmoothPlastic
	turretTablePedestal.Parent = Workspace

	local turretTableTop = Instance.new("Part")
	turretTableTop.Name = "TurretTableTop"
	turretTableTop.Size = Vector3.new(7, 0.5, 7)
	turretTableTop.Position = shopPos + Vector3.new(2, 5.25, 12)
	turretTableTop.Anchored = true
	turretTableTop.CanCollide = false
	turretTableTop.Color = Color3.fromRGB(80, 180, 255)
	turretTableTop.Material = Enum.Material.Neon
	turretTableTop.Parent = Workspace

	-- Turret model on top (base + barrel)
	local turretBase = Instance.new("Part")
	turretBase.Name = "ShopTurret_Base"
	turretBase.Size = Vector3.new(2.5, 1.5, 2.5)
	turretBase.CFrame = CFrame.new(shopPos + Vector3.new(2, 6.5, 12))
	turretBase.Anchored = true
	turretBase.CanCollide = false
	turretBase.Color = Color3.fromRGB(60, 60, 80)
	turretBase.Material = Enum.Material.Metal
	turretBase.Parent = Workspace

	local turretBarrel = Instance.new("Part")
	turretBarrel.Name = "ShopTurret_Barrel"
	turretBarrel.Size = Vector3.new(0.6, 0.6, 3)
	turretBarrel.CFrame = CFrame.new(shopPos + Vector3.new(2, 7.5, 12))
	turretBarrel.Anchored = true
	turretBarrel.CanCollide = false
	turretBarrel.Color = Color3.fromRGB(100, 100, 120)
	turretBarrel.Material = Enum.Material.Metal
	turretBarrel.Parent = Workspace

	-- Glow ring around turret
	local turretGlowRing = Instance.new("Part")
	turretGlowRing.Name = "TurretGlow"
	turretGlowRing.Shape = Enum.PartType.Ball
	turretGlowRing.Size = Vector3.new(5, 5, 5)
	turretGlowRing.Position = shopPos + Vector3.new(2, 7, 12)
	turretGlowRing.Anchored = true
	turretGlowRing.CanCollide = false
	turretGlowRing.Color = Color3.fromRGB(80, 180, 255)
	turretGlowRing.Material = Enum.Material.Neon
	turretGlowRing.Transparency = 0.7
	turretGlowRing.Parent = Workspace

	-- Info sign in front of pedestal (faces -X toward player)
	local turretInfoPanel = Instance.new("Part")
	turretInfoPanel.Name = "TurretShopInfo"
	turretInfoPanel.Size = Vector3.new(1, 4, 10)
	turretInfoPanel.Position = shopPos + Vector3.new(-5, 4, 12)
	turretInfoPanel.Anchored = true
	turretInfoPanel.CanCollide = false
	turretInfoPanel.Color = Color3.fromRGB(20, 30, 50)
	turretInfoPanel.Material = Enum.Material.SmoothPlastic
	turretInfoPanel.Parent = Workspace

	local turretInfoGui = Instance.new("SurfaceGui")
	turretInfoGui.Name = "TurretShopGui"
	turretInfoGui.Face = Enum.NormalId.Left
	turretInfoGui.CanvasSize = Vector2.new(400, 150)
	turretInfoGui.LightInfluence = 0
	turretInfoGui.Brightness = 1.5
	turretInfoGui.Parent = turretInfoPanel

	local turretTitleLbl = Instance.new("TextLabel")
	turretTitleLbl.Size = UDim2.new(1, 0, 0.5, 0)
	turretTitleLbl.BackgroundTransparency = 1
	turretTitleLbl.Text = "🔫 TURRET SHOP 🔫"
	turretTitleLbl.TextColor3 = Color3.fromRGB(80, 200, 255)
	turretTitleLbl.TextScaled = true
	turretTitleLbl.Font = Enum.Font.GothamBold
	turretTitleLbl.Parent = turretInfoGui

	local turretDescLbl = Instance.new("TextLabel")
	turretDescLbl.Size = UDim2.new(1, 0, 0.5, 0)
	turretDescLbl.Position = UDim2.new(0, 0, 0.5, 0)
	turretDescLbl.BackgroundTransparency = 1
	turretDescLbl.Text = "Browse and buy turrets"
	turretDescLbl.TextColor3 = Color3.fromRGB(200, 200, 220)
	turretDescLbl.TextScaled = true
	turretDescLbl.Font = Enum.Font.Gotham
	turretDescLbl.Parent = turretInfoGui

	-- ProximityPrompt to open turret shop
	local turretShopPrompt = Instance.new("ProximityPrompt")
	turretShopPrompt.Name = "OpenTurretShopPrompt"
	turretShopPrompt.ActionText = "Browse Turrets"
	turretShopPrompt.ObjectText = "Turret Shop"
	turretShopPrompt.HoldDuration = 0
	turretShopPrompt.MaxActivationDistance = 12
	turretShopPrompt.RequiresLineOfSight = false
	turretShopPrompt.Parent = turretTablePedestal

	-- Spin the turret continuously
	task.spawn(function()
		while turretBase and turretBase.Parent do
			local t = tick() * 1.5
			local baseY = shopPos.Y + 6.5 + math.sin(t) * 0.3
			local basePos = Vector3.new(shopPos.X + 2, baseY, shopPos.Z + 12)
			-- Rotate turret around Y axis
			turretBase.CFrame = CFrame.new(basePos) * CFrame.Angles(0, t, 0)
			turretBarrel.CFrame = CFrame.new(basePos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, t, 0) * CFrame.new(0, 0, -1.5)
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

	-- ── Rune Collection Building (mirrored on left side, entrance faces +X toward player) ──
	local runePos = Vector3.new(-70, 0, 155)

	-- Floor platform
	local runeFloor = Instance.new("Part")
	runeFloor.Name = "RuneBuildingFloor"
	runeFloor.Size = Vector3.new(30, 1, 40)
	runeFloor.Position = runePos + Vector3.new(0, 1, 0)
	runeFloor.Anchored = true
	runeFloor.CanCollide = true
	runeFloor.Color = Color3.fromRGB(10, 5, 30)
	runeFloor.Material = Enum.Material.SmoothPlastic
	runeFloor.Parent = Workspace

	-- Neon border around floor
	local runeBorderParts = {
		{ size = Vector3.new(0.5, 0.3, 40), offset = Vector3.new(15, 1.6, 0) },
		{ size = Vector3.new(0.5, 0.3, 40), offset = Vector3.new(-15, 1.6, 0) },
		{ size = Vector3.new(30, 0.3, 0.5), offset = Vector3.new(0, 1.6, 20) },
		{ size = Vector3.new(30, 0.3, 0.5), offset = Vector3.new(0, 1.6, -20) },
	}
	local runeBorderColors = {
		Color3.fromRGB(180, 80, 255),
		Color3.fromRGB(100, 200, 255),
		Color3.fromRGB(255, 180, 50),
		Color3.fromRGB(80, 255, 180),
	}
	for bi, bd in ipairs(runeBorderParts) do
		local border = Instance.new("Part")
		border.Name = "RuneBorder_" .. bi
		border.Size = bd.size
		border.Position = runePos + bd.offset
		border.Anchored = true
		border.CanCollide = false
		border.Color = runeBorderColors[bi]
		border.Material = Enum.Material.Neon
		border.Parent = Workspace
	end

	-- Back wall (at -X side, away from player)
	local runeBackWall = Instance.new("Part")
	runeBackWall.Name = "RuneBackWall"
	runeBackWall.Size = Vector3.new(1, 14, 40)
	runeBackWall.Position = runePos + Vector3.new(-15, 8, 0)
	runeBackWall.Anchored = true
	runeBackWall.CanCollide = true
	runeBackWall.Color = Color3.fromRGB(60, 0, 120)
	runeBackWall.Material = Enum.Material.Neon
	runeBackWall.Parent = Workspace

	-- Side walls (at ±Z, entrance is at +X toward player)
	local runeSideColors = {
		Color3.fromRGB(120, 50, 200),
		Color3.fromRGB(80, 180, 255),
	}
	for si, side in ipairs({ -1, 1 }) do
		local sideWall = Instance.new("Part")
		sideWall.Name = "RuneSideWall_" .. (side == -1 and "L" or "R")
		sideWall.Size = Vector3.new(30, 14, 1)
		sideWall.Position = runePos + Vector3.new(0, 8, 20 * side)
		sideWall.Anchored = true
		sideWall.CanCollide = true
		sideWall.Color = runeSideColors[si]
		sideWall.Material = Enum.Material.Neon
		sideWall.Transparency = 0.15
		sideWall.Parent = Workspace

		local sideStrip = Instance.new("Part")
		sideStrip.Name = "RuneSideStrip_" .. (side == -1 and "L" or "R")
		sideStrip.Size = Vector3.new(0.5, 14, 0.5)
		sideStrip.Position = runePos + Vector3.new(15, 8, 20 * side)
		sideStrip.Anchored = true
		sideStrip.CanCollide = false
		sideStrip.Color = Color3.fromRGB(255, 180, 50)
		sideStrip.Material = Enum.Material.Neon
		sideStrip.Parent = Workspace
	end

	-- Roof
	local runeRoof = Instance.new("Part")
	runeRoof.Name = "RuneRoof"
	runeRoof.Size = Vector3.new(32, 1, 42)
	runeRoof.Position = runePos + Vector3.new(0, 15, 0)
	runeRoof.Anchored = true
	runeRoof.CanCollide = true
	runeRoof.Color = Color3.fromRGB(40, 0, 100)
	runeRoof.Material = Enum.Material.Neon
	runeRoof.Transparency = 0.3
	runeRoof.Parent = Workspace

	-- Neon roof trim
	local runeRoofTrimColors = {
		Color3.fromRGB(180, 80, 255),
		Color3.fromRGB(100, 200, 255),
		Color3.fromRGB(255, 180, 50),
		Color3.fromRGB(80, 255, 180),
	}
	local runeRoofTrims = {
		{ size = Vector3.new(0.5, 0.5, 42), offset = Vector3.new(16, 15.5, 0) },
		{ size = Vector3.new(0.5, 0.5, 42), offset = Vector3.new(-16, 15.5, 0) },
		{ size = Vector3.new(32, 0.5, 0.5), offset = Vector3.new(0, 15.5, 21) },
		{ size = Vector3.new(32, 0.5, 0.5), offset = Vector3.new(0, 15.5, -21) },
	}
	for ri, rt in ipairs(runeRoofTrims) do
		local trim = Instance.new("Part")
		trim.Name = "RuneRoofTrim_" .. ri
		trim.Size = rt.size
		trim.Position = runePos + rt.offset
		trim.Anchored = true
		trim.CanCollide = false
		trim.Color = runeRoofTrimColors[ri]
		trim.Material = Enum.Material.Neon
		trim.Parent = Workspace
	end

	-- "RUNES" sign above entrance (facing +X toward player)
	local runeSignBoard = Instance.new("Part")
	runeSignBoard.Name = "RuneSignBoard"
	runeSignBoard.Size = Vector3.new(2, 8, 26)
	runeSignBoard.Position = runePos + Vector3.new(16, 20, 0)
	runeSignBoard.Anchored = true
	runeSignBoard.CanCollide = false
	runeSignBoard.Color = Color3.fromRGB(180, 80, 255)
	runeSignBoard.Material = Enum.Material.SmoothPlastic
	runeSignBoard.Parent = Workspace

	local runeSignBorder = Instance.new("Part")
	runeSignBorder.Name = "RuneSignBorder"
	runeSignBorder.Size = Vector3.new(1.5, 9.5, 28)
	runeSignBorder.Position = runePos + Vector3.new(14.5, 20, 0)
	runeSignBorder.Anchored = true
	runeSignBorder.CanCollide = false
	runeSignBorder.Color = Color3.fromRGB(100, 200, 255)
	runeSignBorder.Material = Enum.Material.Neon
	runeSignBorder.Parent = Workspace

	local runeSignGlow = Instance.new("Part")
	runeSignGlow.Name = "RuneSignGlow"
	runeSignGlow.Size = Vector3.new(1, 11, 30)
	runeSignGlow.Position = runePos + Vector3.new(13.5, 20, 0)
	runeSignGlow.Anchored = true
	runeSignGlow.CanCollide = false
	runeSignGlow.Color = Color3.fromRGB(180, 80, 255)
	runeSignGlow.Material = Enum.Material.Neon
	runeSignGlow.Transparency = 0.4
	runeSignGlow.Parent = Workspace

	-- SurfaceGui on the +X face (Right) so it faces the player
	local runeSignGui = Instance.new("SurfaceGui")
	runeSignGui.Name = "RuneSignGui"
	runeSignGui.Face = Enum.NormalId.Right
	runeSignGui.CanvasSize = Vector2.new(500, 150)
	runeSignGui.LightInfluence = 0
	runeSignGui.Brightness = 2
	runeSignGui.Parent = runeSignBoard

	local runeSignText = Instance.new("TextLabel")
	runeSignText.Size = UDim2.new(1, 0, 1, 0)
	runeSignText.BackgroundTransparency = 1
	runeSignText.Text = "Runes"
	runeSignText.TextColor3 = Color3.fromRGB(220, 180, 255)
	runeSignText.TextScaled = true
	runeSignText.Font = Enum.Font.FredokaOne
	runeSignText.Parent = runeSignGui

	local runeSignStroke = Instance.new("UIStroke")
	runeSignStroke.Color = Color3.fromRGB(255, 255, 255)
	runeSignStroke.Thickness = 4
	runeSignStroke.Parent = runeSignText

	-- Decorative stars on each side of the sign
	for _, sz in ipairs({ -16, 16 }) do
		local star = Instance.new("Part")
		star.Name = "RuneSignStar"
		star.Shape = Enum.PartType.Ball
		star.Size = Vector3.new(3, 3, 3)
		star.Position = runePos + Vector3.new(15, 22, sz)
		star.Anchored = true
		star.CanCollide = false
		star.Color = Color3.fromRGB(180, 120, 255)
		star.Material = Enum.Material.Neon
		star.Parent = Workspace
	end

	-- Support posts holding the sign
	for _, sz in ipairs({ -10, 10 }) do
		local signPost = Instance.new("Part")
		signPost.Name = "RuneSignPost"
		signPost.Size = Vector3.new(1.5, 5, 1.5)
		signPost.Position = runePos + Vector3.new(15, 17, sz)
		signPost.Anchored = true
		signPost.CanCollide = false
		signPost.Color = Color3.fromRGB(100, 200, 255)
		signPost.Material = Enum.Material.Neon
		signPost.Parent = Workspace
	end

	-- Pedestal with floating rune crystal
	local runePedestal = Instance.new("Part")
	runePedestal.Name = "RunePedestal"
	runePedestal.Size = Vector3.new(6, 4, 6)
	runePedestal.Position = runePos + Vector3.new(-2, 3, 0)
	runePedestal.Anchored = true
	runePedestal.CanCollide = true
	runePedestal.Color = Color3.fromRGB(20, 10, 40)
	runePedestal.Material = Enum.Material.SmoothPlastic
	runePedestal.Parent = Workspace

	local pedTop = Instance.new("Part")
	pedTop.Name = "RunePedestalTop"
	pedTop.Size = Vector3.new(7, 0.5, 7)
	pedTop.Position = runePos + Vector3.new(-2, 5.25, 0)
	pedTop.Anchored = true
	pedTop.CanCollide = false
	pedTop.Color = Color3.fromRGB(180, 80, 255)
	pedTop.Material = Enum.Material.Neon
	pedTop.Parent = Workspace

	-- Floating crystal
	local crystal = Instance.new("Part")
	crystal.Name = "RuneCrystal"
	crystal.Shape = Enum.PartType.Ball
	crystal.Size = Vector3.new(3, 4, 3)
	crystal.CFrame = CFrame.new(runePos + Vector3.new(-2, 8, 0))
	crystal.Anchored = true
	crystal.CanCollide = false
	crystal.Color = Color3.fromRGB(180, 80, 255)
	crystal.Material = Enum.Material.Neon
	crystal.Parent = Workspace

	-- Glow ring around crystal
	local crystalGlow = Instance.new("Part")
	crystalGlow.Name = "RuneCrystalGlow"
	crystalGlow.Shape = Enum.PartType.Ball
	crystalGlow.Size = Vector3.new(6, 6, 6)
	crystalGlow.Position = runePos + Vector3.new(-2, 8, 0)
	crystalGlow.Anchored = true
	crystalGlow.CanCollide = false
	crystalGlow.Color = Color3.fromRGB(140, 60, 220)
	crystalGlow.Material = Enum.Material.Neon
	crystalGlow.Transparency = 0.7
	crystalGlow.Parent = Workspace

	-- Info sign in front of pedestal (faces +X toward player)
	local runeInfoPanel = Instance.new("Part")
	runeInfoPanel.Name = "RuneInfoPanel"
	runeInfoPanel.Size = Vector3.new(1, 4, 10)
	runeInfoPanel.Position = runePos + Vector3.new(5, 4, 0)
	runeInfoPanel.Anchored = true
	runeInfoPanel.CanCollide = false
	runeInfoPanel.Color = Color3.fromRGB(10, 5, 30)
	runeInfoPanel.Material = Enum.Material.SmoothPlastic
	runeInfoPanel.Parent = Workspace

	local runeInfoGui = Instance.new("SurfaceGui")
	runeInfoGui.Name = "RuneInfoGui"
	runeInfoGui.Face = Enum.NormalId.Right
	runeInfoGui.CanvasSize = Vector2.new(400, 150)
	runeInfoGui.LightInfluence = 0
	runeInfoGui.Brightness = 1.5
	runeInfoGui.Parent = runeInfoPanel

	local runeInfoTitle = Instance.new("TextLabel")
	runeInfoTitle.Size = UDim2.new(1, 0, 0.5, 0)
	runeInfoTitle.BackgroundTransparency = 1
	runeInfoTitle.Text = "✨ RUNE COLLECTION ✨"
	runeInfoTitle.TextColor3 = Color3.fromRGB(200, 160, 255)
	runeInfoTitle.TextScaled = true
	runeInfoTitle.Font = Enum.Font.GothamBold
	runeInfoTitle.Parent = runeInfoGui

	local runeInfoDesc = Instance.new("TextLabel")
	runeInfoDesc.Size = UDim2.new(1, 0, 0.5, 0)
	runeInfoDesc.Position = UDim2.new(0, 0, 0.5, 0)
	runeInfoDesc.BackgroundTransparency = 1
	runeInfoDesc.Text = "View your runes and effects"
	runeInfoDesc.TextColor3 = Color3.fromRGB(180, 180, 200)
	runeInfoDesc.TextScaled = true
	runeInfoDesc.Font = Enum.Font.Gotham
	runeInfoDesc.Parent = runeInfoGui

	-- ProximityPrompt to open rune viewer
	local runePrompt = Instance.new("ProximityPrompt")
	runePrompt.Name = "ViewRunesPrompt"
	runePrompt.ActionText = "View Runes"
	runePrompt.ObjectText = "Rune Collection"
	runePrompt.HoldDuration = 0
	runePrompt.MaxActivationDistance = 12
	runePrompt.RequiresLineOfSight = false
	runePrompt.Parent = runePedestal

	-- Spin the crystal continuously
	task.spawn(function()
		while crystal and crystal.Parent do
			local t = tick() * 1.5
			crystal.CFrame = CFrame.new(runePos + Vector3.new(-2, 8 + math.sin(t) * 0.5, 0))
				* CFrame.Angles(0, t, math.rad(15))
			-- Cycle crystal color through rune palette
			local runeColors = {
				Color3.fromRGB(255, 80, 20),   -- Ember
				Color3.fromRGB(100, 200, 255), -- Frost
				Color3.fromRGB(255, 240, 50),  -- Spark
				Color3.fromRGB(80, 200, 80),   -- Spore
				Color3.fromRGB(60, 20, 80),    -- Shadow
				Color3.fromRGB(255, 255, 180), -- Radiance
				Color3.fromRGB(140, 110, 80),  -- Stone
				Color3.fromRGB(180, 230, 255), -- Gale
				Color3.fromRGB(180, 80, 255),  -- Arcane
				Color3.fromRGB(10, 10, 30),    -- Void
			}
			local idx = math.floor(t * 0.5) % #runeColors + 1
			crystal.Color = runeColors[idx]
			task.wait(0.03)
		end
	end)

	-- Floating orbs for ambiance
	local runeOrbColors = {
		Color3.fromRGB(180, 80, 255),
		Color3.fromRGB(100, 200, 255),
		Color3.fromRGB(255, 180, 50),
		Color3.fromRGB(80, 255, 180),
		Color3.fromRGB(255, 80, 200),
		Color3.fromRGB(255, 240, 50),
	}
	for oi = 1, 6 do
		local orb = Instance.new("Part")
		orb.Name = "RuneOrb_" .. oi
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(1.5, 1.5, 1.5)
		local angle = (oi / 6) * math.pi * 2
		orb.Position = runePos + Vector3.new(math.cos(angle) * 14, 10 + math.sin(oi) * 2, math.sin(angle) * 10)
		orb.Anchored = true
		orb.CanCollide = false
		orb.Color = runeOrbColors[oi]
		orb.Material = Enum.Material.Neon
		orb.Parent = Workspace
	end

	-- Corner pillars
	local runePillarPositions = {
		Vector3.new(13, 0, 18), Vector3.new(13, 0, -18),
		Vector3.new(-13, 0, 18), Vector3.new(-13, 0, -18),
	}
	local runePillarColors = {
		Color3.fromRGB(180, 80, 255),
		Color3.fromRGB(100, 200, 255),
		Color3.fromRGB(255, 180, 50),
		Color3.fromRGB(80, 255, 180),
	}
	for pi, pp in ipairs(runePillarPositions) do
		local pillar = Instance.new("Part")
		pillar.Name = "RunePillar_" .. pi
		pillar.Size = Vector3.new(2, 12, 2)
		pillar.Position = runePos + pp + Vector3.new(0, 7, 0)
		pillar.Anchored = true
		pillar.CanCollide = true
		pillar.Color = Color3.fromRGB(15, 8, 35)
		pillar.Material = Enum.Material.SmoothPlastic
		pillar.Parent = Workspace

		local pillarTop = Instance.new("Part")
		pillarTop.Name = "RunePillarTop_" .. pi
		pillarTop.Shape = Enum.PartType.Ball
		pillarTop.Size = Vector3.new(3, 3, 3)
		pillarTop.Position = runePos + pp + Vector3.new(0, 14, 0)
		pillarTop.Anchored = true
		pillarTop.CanCollide = false
		pillarTop.Color = runePillarColors[pi]
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
-- resolveMapName: returns the map name for a given pad/area index.
-- Pads 1 and 2 have fixed assignments; pad 3 picks a random map.
-- ---------------------------------------------------------------------------
local function resolveMapName(areaIndex: number): string
	local assignment = PAD_MAP_ASSIGNMENTS[areaIndex]
	if assignment == "RANDOM" then
		local allMaps = EnemyPath.getMapNames()
		return allMaps[math.random(1, #allMaps)]
	end
	return assignment
end

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

	-- Resolve which map this pad should launch
	local mapName = resolveMapName(areaIndex)

	-- Announce the selected map to pad occupants (useful for pad 3 random reveal)
	for _, player in ipairs(area.occupants) do
		remotes.MapSelected:FireClient(player, mapName)
	end

	-- Send each player their server-authoritative loadout before teleporting
	for _, player in ipairs(area.occupants) do
		local userId = player.UserId
		remotes.SendLoadout:FireClient(player, playerLoadouts[userId])
	end

	-- Compute spawn position dynamically from the selected map's first waypoint
	local mapData = EnemyPath.getMap(mapName)
	local firstWaypoint = mapData.waypoints[1]
	local mapSpawn = CFrame.new(firstWaypoint.X + MAP_OFFSET.X, 3 + MAP_OFFSET.Y, firstWaypoint.Z + MAP_OFFSET.Z)

	-- Teleport occupants to the game map
	for idx, player in ipairs(area.occupants) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local offset = Vector3.new((idx - 1) * 4, 0, 0)
				root.CFrame = mapSpawn + offset
			end
		end
	end

	-- Create scoped GameManager instance (this also builds the map via MapBuilder)
	-- Task 4.4: Collect loadouts for all occupants and pass to GameManager
	local loadouts = {}
	for _, player in ipairs(area.occupants) do
		loadouts[player.UserId] = playerLoadouts[player.UserId]
	end
	-- Get difficulty settings for this area
	local difficulty = AREA_DIFFICULTY[areaIndex] or AREA_DIFFICULTY[1]
	local gm = GameManager.new(area.occupants, areaIndex, loadouts, mapName, difficulty)
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

	-- Submit leaderboard scores for all occupants
	local difficulty = AREA_DIFFICULTY[areaIndex]
	local difficultyName = difficulty and difficulty.name or "Easy"
	for _, player in ipairs(area.occupants) do
		DataManager.submitLeaderboardScore(player.UserId, player.DisplayName, difficultyName, roundReached)
		remotes.LobbyShowResults:FireClient(player, roundReached, areaIndex)
	end

	-- Refresh leaderboards after a short delay to include new scores
	task.delay(2, function()
		DataManager.refreshLeaderboards()
		updateLeaderboardDisplays()
	end)

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

	-- Immediately teleport THIS player back to lobby
	local char = player.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = LOBBY_SPAWN
		end
	end

	-- Send updated persistent coin balance + unlocks to this player
	local uid = player.UserId
	DataManager.savePlayer(uid)
	local coins = EconomyManager.getPersistentCoins(uid)
	local unlocksForPlayer = playerUnlocks[uid] or { [1] = true }
	local unlockArray = {}
	for id, val in pairs(unlocksForPlayer) do
		if val then table.insert(unlockArray, id) end
	end
	remotes.ShopUpdate:FireClient(player, unlockArray, coins)
	local runeInv = RuneManager.getInventory(uid)
	remotes.RuneInventoryUpdate:FireClient(player, runeInv)

	-- Remove this player from occupants
	for i, occ in ipairs(area.occupants) do
		if occ == player then
			table.remove(area.occupants, i)
			break
		end
	end

	-- Check if all occupants have now left (area should reset)
	if #area.occupants == 0 then
		-- Stop the game manager if it exists
		if area.gameManager then
			area.gameManager.stop()
		end

		-- Remove the game map visuals so the lobby stays clean
		local mapFolder = Workspace:FindFirstChild("GameMap_" .. areaIndex)
		if mapFolder then
			mapFolder:Destroy()
		end

		-- Reset area
		area.status              = "EMPTY"
		area.occupants           = {}
		area.countdownRemaining  = 0
		area.gameManager         = nil
		area.roundReached        = 0
		area.countdownGeneration += 1
		area.dismissedPlayers    = {}

		broadcastState()
	end
end

function LobbyManager.setPlayerUnlocks(userId: number, unlocks: { [number]: boolean })
	playerUnlocks[userId] = unlocks
end

function LobbyManager.getPlayerUnlocks(userId: number): { [number]: boolean }
	return playerUnlocks[userId] or { [1] = true }
end

function LobbyManager.setPlayerLoadout(userId: number, loadout: { number })
	playerLoadouts[userId] = loadout
end

function LobbyManager.getPlayerLoadout(userId: number): { number }
	return playerLoadouts[userId] or {}
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
		"SessionCoinsUpdate", "KillEarningsUpdate", "TurretGameOver", "TurretCostsUpdate",
		-- Game remotes (pre-created so clients don't infinite-yield)
		"WaveStarted", "WaveCleared", "Intermission", "GameOver",
		"EnemyKilled", "BossDrop", "BaseDamaged", "MoneyUpdate",
		"PlayerJoined", "TowerPlaced", "InventoryUpdate",
		"RequestInventory", "RequestState",
		"SetGameSpeed", "GameSpeedChanged",
		"PlayerColorsAssigned",
		-- Rune system remotes
		"ApplyRune", "ApplyRuneResult", "RuneInventoryUpdate", "TurretRunesUpdate",
		"OpenRuneViewer", "RuneDrop",
		-- Rune purchase remotes
		"PurchaseSuccess",
		-- Map selection remote
		"MapSelected",
		-- Turret shop remote
		"OpenTurretShop",
	}
	for _, name in ipairs(remoteNames) do
		if not remotes:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name   = name
			r.Parent = remotes
		end
	end

	buildPads()

	-- Initialize leaderboards: refresh data and update displays
	DataManager.refreshLeaderboards()
	task.delay(1, function()
		updateLeaderboardDisplays()
	end)

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
		RuneManager.removePlayer(userId) -- Clean up after data is saved
	end)

	-- Task 4.10: PlayerAdded — send current state to new player
	Players.PlayerAdded:Connect(function(player)
		task.wait() -- brief yield so remotes are ready

		local userId = player.UserId
		DataManager.loadPlayer(player)

		-- Send initial unlocks + persistent coin balance + saved loadout to the client
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
			-- Send saved loadout so client can restore it
			local savedLoadout = playerLoadouts[userId] or {}
			if #savedLoadout > 0 then
				remotes.SendLoadout:FireClient(player, savedLoadout)
			end
			-- Initialize rune inventory if not already done, then send to client
			if not RuneManager.getInventory(userId) or next(RuneManager.getInventory(userId)) == nil then
				RuneManager.initPlayer(userId)
			end
			remotes.RuneInventoryUpdate:FireClient(player, RuneManager.getInventory(userId))
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
		DataManager.markDirty(userId)
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
		elseif prompt.Name == "BuyDoubleDamagePrompt" then
			local passId = GamepassManager.getDoubleDamageGamepassId()
			if passId > 0 then
				MarketplaceService:PromptGamePassPurchase(triggerPlayer, passId)
			else
				warn("[LobbyManager] Double damage gamepass ID not set — update GamepassManager.luau")
			end
		elseif prompt.Name == "ViewRunesPrompt" then
			-- Send current rune inventory and fire open event to client
			local userId = triggerPlayer.UserId
			remotes.RuneInventoryUpdate:FireClient(triggerPlayer, RuneManager.getInventory(userId))
			remotes.OpenRuneViewer:FireClient(triggerPlayer)
		elseif prompt.Name == "OpenTurretShopPrompt" then
			-- Fire open turret shop event to client
			remotes.OpenTurretShop:FireClient(triggerPlayer)
		end
	end)

	print("[LobbyManager] Initialized")
end

return LobbyManager
