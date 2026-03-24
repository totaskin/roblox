-- TurretHUD.luau
-- In-game turret HUD: loadout buttons, placement mode with ghost preview,
-- upgrade panel for placed turrets, and economy remote listeners.
-- Tasks 13.1–13.5

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local TurretData = require(game.ReplicatedStorage.Shared.TurretData)
local ProximityPromptService = game:GetService("ProximityPromptService")

local TurretHUD = {}

-- ── State ────────────────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

-- Economy
local sessionCoins: number = 100
local killEarnings: number = 0

-- Loadout (populated via setLoadout before game starts)
local loadout: { number } = {}

-- Placement mode
local isPlacing: boolean = false
local activeTurretIndex: number = 0 -- 1-3, which loadout slot is active
local selectedSlot: { gridX: number, gridZ: number, worldPos: Vector3 }? = nil
local ghostModel: Model? = nil
local rangeCircle: Part? = nil
local lastHoveredKey: string? = nil

-- Slot tracking (mirrors TowerPlacer occupied slots)
local slotParts: { [string]: BasePart } = {}
local occupiedSlots: { [string]: boolean } = {}

-- Upgrade panel state
local selectedTurretInstanceId: string? = nil
local selectedTurretData: {
	turretTypeId: number,
	level: number,
	stats: { damage: number, range: number, fireRate: number },
}? = nil

-- Proximity range circle (shown when player is near a placed turret)
local turretRangeCircle: Part? = nil
local lastNearTurretModel: Model? = nil

-- UI references
local screenGui: ScreenGui = nil
local coinLabel: TextLabel = nil
local loadoutButtons: { TextButton } = {}
local loadoutCostLabels: { TextLabel } = {}
local errorLabel: TextLabel = nil
local errorHideThread: thread? = nil
local upgradePanel: Frame = nil
local upgradeLevelLabel: TextLabel = nil
local upgradeStatsLabel: TextLabel = nil
local upgradeCostLabel: TextLabel = nil
local upgradeButton: TextButton = nil
local gameOverLabel: TextLabel = nil

-- Grid slot constants (match TowerPlacer)
local SLOT_HEIGHT = 0.6
local SLOT_SIZE = 4

local function slotKey(gx: number, gz: number): string
	return gx .. "_" .. gz
end

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function showError(text: string)
	if not errorLabel then return end
	errorLabel.Text = text
	errorLabel.Visible = true
	if errorHideThread then
		task.cancel(errorHideThread)
	end
	errorHideThread = task.delay(3, function()
		if errorLabel then
			errorLabel.Visible = false
		end
	end)
end

local function refreshCoinLabel()
	if coinLabel then
		coinLabel.Text = "💰 " .. sessionCoins
	end
end

local function refreshLoadoutButtons()
	for i = 1, 3 do
		local btn = loadoutButtons[i]
		local costLbl = loadoutCostLabels[i]
		if not btn then continue end

		local turretId = loadout[i]
		local turret = TurretData.getTurretById(turretId)

		local nameLbl = btn:FindFirstChild("NameLabel")
		if turret then
			if nameLbl then nameLbl.Text = turret.name end
			if costLbl then
				costLbl.Text = "💰 " .. turret.placementCost
			end
		else
			if nameLbl then nameLbl.Text = "Empty" end
			if costLbl then costLbl.Text = "" end
		end

		-- Highlight active turret
		if i == activeTurretIndex and isPlacing then
			btn.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
		else
			btn.BackgroundColor3 = Color3.fromRGB(40, 60, 100)
		end
	end
end

-- ── Ghost preview ────────────────────────────────────────────────────────────

local function clearGhost()
	if ghostModel then ghostModel:Destroy(); ghostModel = nil end
	if rangeCircle then rangeCircle:Destroy(); rangeCircle = nil end
end

local function buildGhost(turretId: number)
	clearGhost()
	local turret = TurretData.getTurretById(turretId)
	if not turret then return end

	-- Ghost turret model (simple semi-transparent parts)
	local model = Instance.new("Model")
	model.Name = "TurretGhost"

	local base = Instance.new("Part")
	base.Size = Vector3.new(SLOT_SIZE, 0.5, SLOT_SIZE)
	base.Anchored = true
	base.CanCollide = false
	base.Transparency = 0.5
	base.Color = Color3.fromRGB(60, 120, 200)
	base.Material = Enum.Material.Neon
	base.Parent = model

	local body = Instance.new("Part")
	body.Size = Vector3.new(2, 3, 2)
	body.Anchored = true
	body.CanCollide = false
	body.Transparency = 0.5
	body.Color = Color3.fromRGB(80, 160, 255)
	body.Material = Enum.Material.Neon
	body.Parent = model

	model.PrimaryPart = base
	model.Parent = workspace
	ghostModel = model

	-- Range circle (flat cylinder)
	local circle = Instance.new("Part")
	circle.Name = "RangeCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.1, turret.range * 2, turret.range * 2)
	circle.Anchored = true
	circle.CanCollide = false
	circle.Transparency = 0.7
	circle.Color = Color3.fromRGB(100, 200, 255)
	circle.Material = Enum.Material.Neon
	circle.Orientation = Vector3.new(0, 0, 90)
	circle.Parent = workspace
	rangeCircle = circle
end

local function updateGhostPosition(worldPos: Vector3)
	if ghostModel and ghostModel.PrimaryPart then
		ghostModel.PrimaryPart.Position = worldPos + Vector3.new(0, SLOT_HEIGHT + 0.3, 0)
		for _, p in ghostModel:GetChildren() do
			if p:IsA("BasePart") and p ~= ghostModel.PrimaryPart then
				p.Position = worldPos + Vector3.new(0, SLOT_HEIGHT + 2, 0)
			end
		end
	end
	if rangeCircle then
		rangeCircle.Position = worldPos + Vector3.new(0, SLOT_HEIGHT + 0.2, 0)
	end
end

-- ── Placement mode ────────────────────────────────────────────────────────────

local function enterPlacementMode(slotIndex: number)
	local turretId = loadout[slotIndex]
	if not turretId then return end

	local turret = TurretData.getTurretById(turretId)
	if not turret then return end

	if sessionCoins < turret.placementCost then
		showError("Not enough coins (need " .. turret.placementCost .. ")")
		return
	end

	isPlacing = true
	activeTurretIndex = slotIndex
	buildGhost(turretId)
	refreshLoadoutButtons()
end

local function cancelPlacement()
	isPlacing = false
	activeTurretIndex = 0
	selectedSlot = nil
	clearGhost()
	refreshLoadoutButtons()
end

local function getHoveredSlot(): (string?, number?, number?, Vector3?)
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	-- Exclude ghost model and range circle from raycast so we hit the grid slot underneath
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if ghostModel then table.insert(filterList, ghostModel) end
	if rangeCircle then table.insert(filterList, rangeCircle) end
	params.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, params)
	if not result then return nil, nil, nil, nil end

	local hit = result.Instance
	if hit and hit.Name:sub(1, 10) == "TowerSlot_" then
		local key = hit.Name:sub(11)
		local parts = key:split("_")
		local gx = tonumber(parts[1])
		local gz = tonumber(parts[2])
		return key, gx, gz, hit.Position
	end
	return nil, nil, nil, nil
end

-- Detect if a click hit a placed turret model (for upgrade panel)
local function getTurretInstanceFromRaycast(): (string?, BasePart?)
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500)
	if not result then return nil, nil end

	local hit = result.Instance
	-- Walk up parents to find a model tagged as a turret
	local current = hit
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("TurretInstanceId") then
			return current:GetAttribute("TurretInstanceId"), hit
		end
		current = current.Parent
	end
	return nil, nil
end

-- ── Upgrade panel ────────────────────────────────────────────────────────────

local function hideUpgradePanel()
	if upgradePanel then
		upgradePanel.Visible = false
	end
	selectedTurretInstanceId = nil
	selectedTurretData = nil
end

local function showUpgradePanel(instanceId: string, turretTypeId: number, level: number, stats: { damage: number, range: number, fireRate: number })
	selectedTurretInstanceId = instanceId
	selectedTurretData = { turretTypeId = turretTypeId, level = level, stats = stats }

	if not upgradePanel then return end
	upgradePanel.Visible = true

	local turret = TurretData.getTurretById(turretTypeId)
	local turretName = turret and turret.name or ("Turret #" .. turretTypeId)

	if upgradeLevelLabel then
		upgradeLevelLabel.Text = turretName .. " — Lv " .. level
	end

	if upgradeStatsLabel then
		upgradeStatsLabel.Text = string.format(
			"DMG: %.1f  RNG: %.1f  SPD: %.1f",
			stats.damage, stats.range, stats.fireRate
		)
	end

	local targetLevel = level + 1
	local cost = turret and (turret.placementCost * math.pow(2, targetLevel - 1)) or 0
	if upgradeCostLabel then upgradeCostLabel.Text = "Upgrade: 💰 " .. cost end
	if upgradeButton then
		upgradeButton.Text = "Upgrade to Lv " .. targetLevel
		upgradeButton.BackgroundColor3 = sessionCoins >= cost
			and Color3.fromRGB(50, 160, 80)
			or Color3.fromRGB(80, 80, 80)
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function buildUI(): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "TurretHUD"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Session coin display (top area)
	coinLabel = Instance.new("TextLabel")
	coinLabel.Name = "SessionCoins"
	coinLabel.Size = UDim2.new(0, 180, 0, 36)
	coinLabel.Position = UDim2.new(0.5, -90, 0, 55)
	coinLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	coinLabel.BackgroundTransparency = 0.3
	coinLabel.BorderSizePixel = 0
	coinLabel.Text = "💰 " .. sessionCoins
	coinLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
	coinLabel.TextScaled = true
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.Parent = screen

	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(0, 6)
	coinCorner.Parent = coinLabel

	-- Loadout buttons container (bottom center)
	local loadoutBar = Instance.new("Frame")
	loadoutBar.Name = "LoadoutBar"
	loadoutBar.Size = UDim2.new(0, 420, 0, 70)
	loadoutBar.Position = UDim2.new(0.5, -210, 1, -155)
	loadoutBar.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	loadoutBar.BackgroundTransparency = 0.3
	loadoutBar.BorderSizePixel = 0
	loadoutBar.Parent = screen

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = loadoutBar

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.Padding = UDim.new(0, 8)
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Parent = loadoutBar

	-- 3 loadout turret buttons
	for i = 1, 3 do
		local turretId = loadout[i]
		local turret = TurretData.getTurretById(turretId)

		local btn = Instance.new("TextButton")
		btn.Name = "Loadout_" .. i
		btn.Size = UDim2.new(0, 125, 0, 56)
		btn.BackgroundColor3 = Color3.fromRGB(40, 60, 100)
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.TextScaled = true
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = loadoutBar

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		-- Name label (top portion)
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "NameLabel"
		nameLbl.Size = UDim2.new(1, -4, 0, 32)
		nameLbl.Position = UDim2.new(0, 2, 0, 2)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = turret and turret.name or "Empty"
		nameLbl.TextColor3 = Color3.new(1, 1, 1)
		nameLbl.TextScaled = true
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.Parent = btn

		-- Cost sublabel (bottom portion)
		local costLbl = Instance.new("TextLabel")
		costLbl.Name = "Cost"
		costLbl.Size = UDim2.new(1, -4, 0, 16)
		costLbl.Position = UDim2.new(0, 2, 0, 36)
		costLbl.BackgroundTransparency = 1
		costLbl.Text = turret and ("💰 " .. turret.placementCost) or ""
		costLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
		costLbl.TextScaled = true
		costLbl.Font = Enum.Font.Gotham
		costLbl.Parent = btn

		loadoutButtons[i] = btn
		loadoutCostLabels[i] = costLbl

		-- Click handler: enter/switch placement mode
		btn.MouseButton1Click:Connect(function()
			if isPlacing and activeTurretIndex == i then
				-- Clicking same button cancels placement
				cancelPlacement()
			else
				-- Cancel any existing placement, then enter for this slot
				if isPlacing then cancelPlacement() end
				hideUpgradePanel()
				enterPlacementMode(i)
			end
		end)
	end

	-- Error message label (above loadout bar)
	errorLabel = Instance.new("TextLabel")
	errorLabel.Name = "ErrorMsg"
	errorLabel.Size = UDim2.new(0, 400, 0, 28)
	errorLabel.Position = UDim2.new(0.5, -200, 1, -190)
	errorLabel.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	errorLabel.BackgroundTransparency = 0.2
	errorLabel.BorderSizePixel = 0
	errorLabel.Text = ""
	errorLabel.TextColor3 = Color3.new(1, 1, 1)
	errorLabel.TextScaled = true
	errorLabel.Font = Enum.Font.GothamBold
	errorLabel.Visible = false
	errorLabel.Parent = screen

	local errCorner = Instance.new("UICorner")
	errCorner.CornerRadius = UDim.new(0, 6)
	errCorner.Parent = errorLabel

	-- Upgrade panel (right side, hidden by default)
	upgradePanel = Instance.new("Frame")
	upgradePanel.Name = "UpgradePanel"
	upgradePanel.Size = UDim2.new(0, 240, 0, 160)
	upgradePanel.Position = UDim2.new(1, -250, 0.5, -80)
	upgradePanel.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	upgradePanel.BackgroundTransparency = 0.1
	upgradePanel.BorderSizePixel = 0
	upgradePanel.Visible = false
	upgradePanel.Parent = screen

	local upCorner = Instance.new("UICorner")
	upCorner.CornerRadius = UDim.new(0, 8)
	upCorner.Parent = upgradePanel

	upgradeLevelLabel = Instance.new("TextLabel")
	upgradeLevelLabel.Name = "LevelLabel"
	upgradeLevelLabel.Size = UDim2.new(1, -10, 0, 28)
	upgradeLevelLabel.Position = UDim2.new(0, 5, 0, 5)
	upgradeLevelLabel.BackgroundTransparency = 1
	upgradeLevelLabel.Text = "Turret — Lv 1"
	upgradeLevelLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	upgradeLevelLabel.TextScaled = true
	upgradeLevelLabel.Font = Enum.Font.GothamBold
	upgradeLevelLabel.Parent = upgradePanel

	upgradeStatsLabel = Instance.new("TextLabel")
	upgradeStatsLabel.Name = "StatsLabel"
	upgradeStatsLabel.Size = UDim2.new(1, -10, 0, 22)
	upgradeStatsLabel.Position = UDim2.new(0, 5, 0, 36)
	upgradeStatsLabel.BackgroundTransparency = 1
	upgradeStatsLabel.Text = "DMG: 0  RNG: 0  SPD: 0"
	upgradeStatsLabel.TextColor3 = Color3.fromRGB(130, 200, 255)
	upgradeStatsLabel.TextScaled = true
	upgradeStatsLabel.Font = Enum.Font.Gotham
	upgradeStatsLabel.Parent = upgradePanel

	upgradeCostLabel = Instance.new("TextLabel")
	upgradeCostLabel.Name = "CostLabel"
	upgradeCostLabel.Size = UDim2.new(1, -10, 0, 22)
	upgradeCostLabel.Position = UDim2.new(0, 5, 0, 62)
	upgradeCostLabel.BackgroundTransparency = 1
	upgradeCostLabel.Text = ""
	upgradeCostLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	upgradeCostLabel.TextScaled = true
	upgradeCostLabel.Font = Enum.Font.Gotham
	upgradeCostLabel.Parent = upgradePanel

	upgradeButton = Instance.new("TextButton")
	upgradeButton.Name = "UpgradeBtn"
	upgradeButton.Size = UDim2.new(1, -20, 0, 34)
	upgradeButton.Position = UDim2.new(0, 10, 0, 90)
	upgradeButton.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
	upgradeButton.BorderSizePixel = 0
	upgradeButton.Text = "Upgrade"
	upgradeButton.TextColor3 = Color3.new(1, 1, 1)
	upgradeButton.TextScaled = true
	upgradeButton.Font = Enum.Font.GothamBold
	upgradeButton.Parent = upgradePanel

	local upBtnCorner = Instance.new("UICorner")
	upBtnCorner.CornerRadius = UDim.new(0, 6)
	upBtnCorner.Parent = upgradeButton

	-- Close button for upgrade panel
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -32, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = upgradePanel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		hideUpgradePanel()
	end)

	-- Game over toast (small, non-blocking — the LobbyClient results screen handles the main overlay)
	gameOverLabel = Instance.new("TextLabel")
	gameOverLabel.Name = "GameOverToast"
	gameOverLabel.Size = UDim2.new(0, 400, 0, 50)
	gameOverLabel.Position = UDim2.new(0.5, -200, 0, 100)
	gameOverLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	gameOverLabel.BackgroundTransparency = 0.2
	gameOverLabel.BorderSizePixel = 0
	gameOverLabel.Text = ""
	gameOverLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	gameOverLabel.TextScaled = true
	gameOverLabel.Font = Enum.Font.GothamBold
	gameOverLabel.TextWrapped = true
	gameOverLabel.Visible = false
	gameOverLabel.Parent = screen

	local goCorner = Instance.new("UICorner")
	goCorner.CornerRadius = UDim.new(0, 10)
	goCorner.Parent = gameOverLabel

	return screen
end

-- ── Proximity range circle ────────────────────────────────────────────────────

local PROXIMITY_RANGE = 14 -- how close the player needs to be to see the range circle

local function clearTurretRangeCircle()
	if turretRangeCircle then turretRangeCircle:Destroy(); turretRangeCircle = nil end
	lastNearTurretModel = nil
end

local function showTurretRangeCircle(turretModel: Model, range: number)
	if lastNearTurretModel == turretModel and turretRangeCircle then return end
	clearTurretRangeCircle()
	lastNearTurretModel = turretModel

	local base = turretModel:FindFirstChild("Base")
	if not base then return end

	local circle = Instance.new("Part")
	circle.Name = "TurretRangeCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.1, range * 2, range * 2)
	circle.Anchored = true
	circle.CanCollide = false
	circle.Transparency = 0.75
	circle.Color = Color3.fromRGB(100, 200, 255)
	circle.Material = Enum.Material.Neon
	circle.CFrame = CFrame.new(base.Position + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	circle.Parent = workspace
	turretRangeCircle = circle
end

-- ── RenderStepped: placement hover logic ─────────────────────────────────────

local renderConnection: RBXScriptConnection? = nil

local function startRenderLoop()
	if renderConnection then return end
	renderConnection = RunService.RenderStepped:Connect(function()
		-- Proximity range circle: check if player is near any placed turret
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and not isPlacing then
			local playerPos = rootPart.Position
			local closestModel: Model? = nil
			local closestRange: number = 0
			local closestDist: number = math.huge

			for _, obj in workspace:GetChildren() do
				if obj:IsA("Model") and obj:GetAttribute("TurretInstanceId") and obj:GetAttribute("TurretInstanceId") ~= "" then
					local base = obj:FindFirstChild("Base")
					if base then
						local dist = (base.Position - playerPos).Magnitude
						if dist < PROXIMITY_RANGE and dist < closestDist then
							closestDist = dist
							closestModel = obj
							closestRange = obj:GetAttribute("TurretRange") or 16
						end
					end
				end
			end

			if closestModel then
				showTurretRangeCircle(closestModel, closestRange)
			else
				clearTurretRangeCircle()
			end
		elseif isPlacing then
			clearTurretRangeCircle()
		end

		if not isPlacing then return end

		local key, gx, gz, pos = getHoveredSlot()

		-- Reset last hovered slot color
		if lastHoveredKey and lastHoveredKey ~= key then
			local p = slotParts[lastHoveredKey]
			if p and not occupiedSlots[lastHoveredKey] then
				p.Color = Color3.fromRGB(100, 200, 100)
				p.Transparency = 0.5
			end
		end

		if key and not occupiedSlots[key] then
			local p = slotParts[key]
			if p then
				p.Color = Color3.fromRGB(100, 255, 200)
				p.Transparency = 0.2
			end
			selectedSlot = { gridX = gx, gridZ = gz, worldPos = pos }
			if pos then updateGhostPosition(pos) end
		else
			selectedSlot = nil
		end

		lastHoveredKey = key
	end)
end

-- ── Public API ───────────────────────────────────────────────────────────────

function TurretHUD.show()
	if screenGui then screenGui.Enabled = true end
	-- Clear game over toast from previous game
	if gameOverLabel then
		gameOverLabel.Visible = false
		gameOverLabel.Text = ""
	end
	-- Reset occupied slots from previous game so turrets can be placed again
	occupiedSlots = {}
	for _, part in pairs(slotParts) do
		part.Color = Color3.fromRGB(100, 200, 100)
		part.Transparency = 0.5
	end
	refreshLoadoutButtons()
end

function TurretHUD.setLoadout(newLoadout: { number })
	loadout = newLoadout
	refreshLoadoutButtons()
end

function TurretHUD.hide()
	if screenGui then screenGui.Enabled = false end
	cancelPlacement()
	hideUpgradePanel()
	clearTurretRangeCircle()
end

function TurretHUD.init()
	screenGui = buildUI()
	screenGui.Enabled = false -- hidden until game starts
	screenGui.Parent = playerGui

	-- Discover existing slot parts in workspace (built by TowerPlacer.buildGrid)
	for _, obj in workspace:GetChildren() do
		if obj:IsA("BasePart") and obj.Name:sub(1, 10) == "TowerSlot_" then
			local key = obj.Name:sub(11)
			slotParts[key] = obj
		end
	end

	-- Watch for new slot parts added later
	workspace.ChildAdded:Connect(function(obj)
		if obj:IsA("BasePart") and obj.Name:sub(1, 10) == "TowerSlot_" then
			local key = obj.Name:sub(11)
			slotParts[key] = obj
		end
	end)

	startRenderLoop()
	refreshCoinLabel()
	refreshLoadoutButtons()

	-- ── Mouse click: confirm placement or select placed turret ───────────
	mouse.Button1Down:Connect(function()
		if isPlacing then
			-- Confirm turret placement
			if not selectedSlot then return end
			local turretId = loadout[activeTurretIndex]
			if not turretId then return end

			local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if not Remotes then return end
			local PlaceTurret = Remotes:FindFirstChild("PlaceTurret")
			if PlaceTurret then
				PlaceTurret:FireServer(
					turretId,
					selectedSlot.gridX,
					selectedSlot.gridZ,
					selectedSlot.worldPos.X,
					selectedSlot.worldPos.Z
				)
			end
			cancelPlacement()
			return
		end

		-- Not placing: check if clicked a placed turret for upgrade panel
		local instanceId = getTurretInstanceFromRaycast()
		if instanceId then
			-- Find the turret model to read attributes
			for _, obj in workspace:GetChildren() do
				if obj:IsA("Model") and obj:GetAttribute("TurretInstanceId") == instanceId then
					local typeId = obj:GetAttribute("TurretTypeId") or 1
					local level = obj:GetAttribute("TurretLevel") or 1
					local dmg = obj:GetAttribute("TurretDamage") or 0
					local rng = obj:GetAttribute("TurretRange") or 0
					local spd = obj:GetAttribute("TurretFireRate") or 0
					showUpgradePanel(instanceId, typeId, level, {
						damage = dmg,
						range = rng,
						fireRate = spd,
					})
					break
				end
			end
		end
	end)

	-- Right click / Escape cancels placement
	mouse.Button2Down:Connect(function()
		if isPlacing then cancelPlacement() end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			if isPlacing then
				cancelPlacement()
			elseif upgradePanel and upgradePanel.Visible then
				hideUpgradePanel()
			end
		end
	end)

	-- ── Wire upgrade button ──────────────────────────────────────────────
	if upgradeButton then
		upgradeButton.MouseButton1Click:Connect(function()
			if not selectedTurretInstanceId then return end
			if not selectedTurretData then return end

			local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if not Remotes then return end
			local UpgradeTurret = Remotes:FindFirstChild("UpgradeTurret")
			if UpgradeTurret then
				UpgradeTurret:FireServer(selectedTurretInstanceId)
			end
		end)
	end

	-- ── ProximityPrompt: upgrade turret when player walks near it ─────
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggerPlayer)
		if triggerPlayer ~= player then return end
		if prompt.Name ~= "UpgradePrompt" then return end

		-- Walk up to find the turret model
		local model = prompt.Parent and prompt.Parent.Parent
		if not model or not model:IsA("Model") then return end

		local instanceId = model:GetAttribute("TurretInstanceId")
		if not instanceId or instanceId == "" then return end

		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not Remotes then return end
		local UpgradeTurret = Remotes:FindFirstChild("UpgradeTurret")
		if UpgradeTurret then
			UpgradeTurret:FireServer(instanceId)
		end
	end)

	-- ── Wire remotes ─────────────────────────────────────────────────────
	task.spawn(function()
		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		if not Remotes then
			warn("[TurretHUD] Remotes folder not found")
			return
		end

		-- Task 13.3: PlaceTurretResult
		local PlaceTurretResult = Remotes:WaitForChild("PlaceTurretResult", 10)
		if PlaceTurretResult then
			PlaceTurretResult.OnClientEvent:Connect(function(success: boolean, reason: string?)
				if not success then
					showError(reason or "Placement failed")
				end
			end)
		end

		-- Task 13.3: TurretPlaced (broadcast to all clients)
		local TurretPlaced = Remotes:WaitForChild("TurretPlaced", 10)
		if TurretPlaced then
			TurretPlaced.OnClientEvent:Connect(function(turretTypeId: number, gridX: number, gridZ: number, worldX: number, worldZ: number, instanceId: string)
				-- Mark slot as occupied
				local key = slotKey(gridX, gridZ)
				occupiedSlots[key] = true
				local slotPart = slotParts[key]
				if slotPart then
					slotPart.Color = Color3.fromRGB(180, 60, 60)
					slotPart.Transparency = 0.7
				end
			end)
		end

		-- Task 13.4: UpgradeTurretResult
		local UpgradeTurretResult = Remotes:WaitForChild("UpgradeTurretResult", 10)
		if UpgradeTurretResult then
			UpgradeTurretResult.OnClientEvent:Connect(function(success: boolean, reason: string?)
				if not success then
					showError(reason or "Upgrade failed")
				end
			end)
		end

		-- Task 13.4: TurretUpgraded (broadcast to all clients)
		local TurretUpgraded = Remotes:WaitForChild("TurretUpgraded", 10)
		if TurretUpgraded then
			TurretUpgraded.OnClientEvent:Connect(function(instanceId: string, newLevel: number, newStats: { damage: number, range: number, fireRate: number })
				-- Update model attributes
				for _, obj in workspace:GetChildren() do
					if obj:IsA("Model") and obj:GetAttribute("TurretInstanceId") == instanceId then
						obj:SetAttribute("TurretLevel", newLevel)
						obj:SetAttribute("TurretDamage", newStats.damage)
						obj:SetAttribute("TurretRange", newStats.range)
						obj:SetAttribute("TurretFireRate", newStats.fireRate)
						break
					end
				end

				-- Refresh upgrade panel if this turret is currently selected
				if selectedTurretInstanceId == instanceId then
					local typeId = selectedTurretData and selectedTurretData.turretTypeId or 1
					showUpgradePanel(instanceId, typeId, newLevel, newStats)
				end
			end)
		end

		-- Task 13.5: SessionCoinsUpdate
		local SessionCoinsUpdate = Remotes:WaitForChild("SessionCoinsUpdate", 10)
		if SessionCoinsUpdate then
			SessionCoinsUpdate.OnClientEvent:Connect(function(amount: number)
				sessionCoins = amount
				refreshCoinLabel()
			end)
		end

		-- Task 13.5: KillEarningsUpdate
		local KillEarningsUpdate = Remotes:WaitForChild("KillEarningsUpdate", 10)
		if KillEarningsUpdate then
			KillEarningsUpdate.OnClientEvent:Connect(function(amount: number)
				killEarnings = amount
			end)
		end

		-- Task 13.5: TurretGameOver
		local TurretGameOver = Remotes:WaitForChild("TurretGameOver", 10)
		if TurretGameOver then
			TurretGameOver.OnClientEvent:Connect(function(killEarningsBanked: number, newPersistentBalance: number)
				-- Show toast with banking info (stays visible until results screen dismisses it)
				if gameOverLabel then
					gameOverLabel.Text = "Banked: 💰 " .. killEarningsBanked .. "  |  Balance: 💰 " .. newPersistentBalance
					gameOverLabel.Visible = true
				end

				-- Clean up placement state
				cancelPlacement()
				hideUpgradePanel()
			end)
		end

		print("[TurretHUD] HUD initialized and wired to remotes")
	end)
end

return TurretHUD
