-- TowerPlacer.luau
-- Handles grid slot highlighting and tower placement input

local Players        = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyPath  = require(game.ReplicatedStorage.Shared.EnemyPath)
local TowerData  = require(game.ReplicatedStorage.Shared.TowerData)
local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)

local TowerPlacer = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse  = player:GetMouse()

-- State
local isPlacing       = false
local selectedSlot    = nil  -- { gridX, gridZ, worldPos }
local selectedResources: { number } = {}
local occupiedSlots: { [string]: boolean } = {}
local slotParts: { [string]: BasePart } = {}
local previewModel: Model? = nil
local currentMapName = "Map1"

local SLOT_HEIGHT = 0.6
local SLOT_SIZE   = 4

-- Slot key helper
local function slotKey(gx, gz): string
	return gx .. "_" .. gz
end

-- Build grid slot visuals for the current map
function TowerPlacer.buildGrid(mapName: string)
	currentMapName = mapName
	-- Clear old
	for _, p in pairs(slotParts) do p:Destroy() end
	slotParts = {}
	occupiedSlots = {}

	local mapData = EnemyPath.getMap(mapName)
	for _, slot in ipairs(mapData.towerSlots) do
		local gx, gz = slot[1], slot[2]
		local key = slotKey(gx, gz)

		local part = Instance.new("Part")
		part.Name = "TowerSlot_" .. key
		part.Size = Vector3.new(SLOT_SIZE, 0.2, SLOT_SIZE)
		part.Position = Vector3.new(gx, SLOT_HEIGHT, gz)
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.5
		part.Color = Color3.fromRGB(100, 200, 100)
		part.Material = Enum.Material.Neon
		part.Parent = workspace

		slotParts[key] = part
	end
end

-- Mark a slot as occupied (called after tower placed)
function TowerPlacer.markOccupied(gx: number, gz: number)
	local key = slotKey(gx, gz)
	occupiedSlots[key] = true
	local part = slotParts[key]
	if part then
		part.Color = Color3.fromRGB(180, 60, 60)
		part.Transparency = 0.7
	end
end

-- Build a preview ghost model
local function buildPreview(resourceIds: { number })
	if previewModel then previewModel:Destroy() end
	if #resourceIds == 0 then return end

	local stats = TowerData.resolveStats(resourceIds)

	local model = Instance.new("Model")
	model.Name = "TowerPreview"

	local base = Instance.new("Part")
	base.Size = Vector3.new(SLOT_SIZE, 0.5, SLOT_SIZE)
	base.Anchored = true
	base.CanCollide = false
	base.Transparency = 0.4
	base.Color = stats.cursed and Color3.fromRGB(80, 0, 80) or Color3.fromRGB(80, 80, 200)
	base.Parent = model

	local body = Instance.new("Part")
	body.Size = Vector3.new(2, 4, 2)
	body.Anchored = true
	body.CanCollide = false
	body.Transparency = 0.4

	-- Blend resource colors
	local r, g, b = 0, 0, 0
	for _, id in ipairs(resourceIds) do
		local res = ResourceData.Resources[id]
		if res then r += res.color.R; g += res.color.G; b += res.color.B end
	end
	local n = #resourceIds
	body.Color = Color3.new(r/n, g/n, b/n)
	body.Parent = model

	model.PrimaryPart = base
	model.Parent = workspace
	previewModel = model
end

-- Update preview position to hovered slot
local function updatePreview(worldPos: Vector3)
	if not previewModel then return end
	local base = previewModel.PrimaryPart
	if not base then return end
	base.Position = worldPos + Vector3.new(0, SLOT_HEIGHT + 0.3, 0)
	local body = previewModel:FindFirstChild("Part") or previewModel:FindFirstChildWhichIsA("Part")
	-- find body (second part)
	for _, p in ipairs(previewModel:GetChildren()) do
		if p:IsA("BasePart") and p ~= base then
			p.Position = worldPos + Vector3.new(0, SLOT_HEIGHT + 2.5, 0)
		end
	end
end

-- Radius within which clicking will select the nearest slot
local CLICK_RADIUS = 6

-- Find the nearest unoccupied slot to a world position
local function findNearestSlot(worldPos: Vector3): (string?, number?, number?, Vector3?)
	local nearestKey: string? = nil
	local nearestDist = math.huge
	local nearestGx: number? = nil
	local nearestGz: number? = nil
	local nearestPos: Vector3? = nil
	
	for key, part in pairs(slotParts) do
		if not occupiedSlots[key] then
			local slotPos = part.Position
			local dist = (Vector3.new(worldPos.X, 0, worldPos.Z) - Vector3.new(slotPos.X, 0, slotPos.Z)).Magnitude
			if dist < nearestDist and dist <= CLICK_RADIUS then
				nearestDist = dist
				nearestKey = key
				nearestPos = slotPos
				local parts = key:split("_")
				nearestGx = tonumber(parts[1])
				nearestGz = tonumber(parts[2])
			end
		end
	end
	
	return nearestKey, nearestGx, nearestGz, nearestPos
end

-- Raycast mouse to find hovered slot
local function getHoveredSlot(): (string?, number?, number?, Vector3?)
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500)
	if not result then return end

	local hit = result.Instance
	
	-- Direct hit on a tower slot
	if hit and hit.Name:sub(1, 10) == "TowerSlot_" then
		local key = hit.Name:sub(11)
		local parts = key:split("_")
		local gx = tonumber(parts[1])
		local gz = tonumber(parts[2])
		return key, gx, gz, hit.Position
	end
	
	-- Hit something else (ground, etc.) - find nearest slot within radius
	local hitPos = result.Position
	return findNearestSlot(hitPos)
end

-- Highlight hovered slot
local lastHovered: string? = nil
RunService.RenderStepped:Connect(function()
	if not isPlacing then return end

	local key, gx, gz, pos = getHoveredSlot()

	-- Reset last hovered
	if lastHovered and lastHovered ~= key then
		local p = slotParts[lastHovered]
		if p and not occupiedSlots[lastHovered] then
			p.Color = Color3.fromRGB(100, 200, 100)
			p.Transparency = 0.5
		end
	end

	if key and not occupiedSlots[key] then
		local p = slotParts[key]
		if p then
			p.Color = Color3.fromRGB(255, 255, 100)
			p.Transparency = 0.2
		end
		selectedSlot = { gridX = gx, gridZ = gz, worldPos = pos }
		if pos then updatePreview(pos) end
	else
		selectedSlot = nil
	end

	lastHovered = key
end)

-- Begin placement mode with chosen resources
function TowerPlacer.beginPlacement(resourceIds: { number })
	if #resourceIds < 1 or #resourceIds > 5 then return end
	selectedResources = resourceIds
	isPlacing = true
	buildPreview(resourceIds)
end

function TowerPlacer.cancelPlacement()
	isPlacing = false
	selectedSlot = nil
	selectedResources = {}
	if previewModel then previewModel:Destroy(); previewModel = nil end
end

-- Returns current placement state for UI
function TowerPlacer.isActive(): boolean
	return isPlacing
end

function TowerPlacer.getSelectedSlot()
	return selectedSlot
end

function TowerPlacer.getSelectedResources(): { number }
	return selectedResources
end

-- Click to confirm placement
mouse.Button1Down:Connect(function()
	if not isPlacing then return end
	if not selectedSlot then return end

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remotes.PlaceTower:FireServer(
		selectedSlot.gridX,
		selectedSlot.gridZ,
		selectedSlot.worldPos.X,
		selectedSlot.worldPos.Z,
		selectedResources
	)

	TowerPlacer.cancelPlacement()
end)

-- Right click or Escape cancels
mouse.Button2Down:Connect(function()
	if isPlacing then TowerPlacer.cancelPlacement() end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and isPlacing then
		TowerPlacer.cancelPlacement()
	end
end)

return TowerPlacer
