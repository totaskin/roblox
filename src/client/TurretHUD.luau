-- TurretHUD.luau
-- In-game turret HUD: loadout buttons, placement mode with ghost preview,
-- upgrade panel for placed turrets, and economy remote listeners.
-- Tasks 13.1–13.5

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local TurretData = require(game.ReplicatedStorage.Shared.TurretData)
local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)
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

-- Turret placement counts (for escalating costs, synced from server)
local turretPlacementCounts: { [number]: number } = {}

-- Loadout (populated via setLoadout before game starts)
local loadout: { number } = {}

-- Placement mode
local isPlacing: boolean = false
local activeTurretIndex: number = 0 -- 1-3, which loadout slot is active
local selectedSlot: { gridX: number, gridZ: number, worldPos: Vector3 }? = nil
local ghostModel: Model? = nil
local rangeCircle: Part? = nil
local lastHoveredKey: string? = nil

-- Player color state
local playerColorMap: { [number]: Color3 } = {}
local localPlayerColor: Color3? = nil

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
local selectedTurretRunes: { number } = {} -- runes currently on the turret (up to 3)

-- Rune slot UI references
local runeSlotButtons: { TextButton } = {}
local runePickerFrame: Frame = nil
local runePickerButtons: { [number]: TextButton } = {}
local editingRuneSlot: number? = nil -- which slot (1-3) is being edited

-- Rune inventory (synced from server)
local runeInventory: { [number]: number } = {}

-- Proximity range circle (shown when player is near a placed turret)
local turretRangeCircle: Part? = nil
local lastNearTurretModel: Model? = nil

-- Proximity rune slots UI (BillboardGui on turret)
local proximityRuneGui: BillboardGui? = nil
local proximityRuneSlots: { Frame } = {}
local proximityTurretId: string? = nil

-- Rune picker (screen-space, appears when clicking a proximity slot)
local runePickerVisible: boolean = false

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

-- Calculate escalating placement cost for a turret type
local function getPlacementCost(turretTypeId: number): number
	local turret = TurretData.getTurretById(turretTypeId)
	if not turret then return 0 end
	local baseCost = turret.placementCost
	local count = turretPlacementCounts[turretTypeId] or 0
	return math.floor(baseCost + (baseCost * 0.5 * count))
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
				local cost = getPlacementCost(turretId)
				costLbl.Text = "💰 " .. cost
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

	if localPlayerColor then
		body.Color = localPlayerColor
	end

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

	local cost = getPlacementCost(turretId)
	if sessionCoins < cost then
		showError("Not enough coins (need " .. cost .. ")")
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
	if runePickerFrame then
		runePickerFrame.Visible = false
	end
	editingRuneSlot = nil
	selectedTurretInstanceId = nil
	selectedTurretData = nil
	selectedTurretRunes = {}
end

local function refreshRuneSlots()
	for i = 1, 3 do
		local btn = runeSlotButtons[i]
		if not btn then continue end
		
		local runeId = selectedTurretRunes[i]
		local nameLbl = btn:FindFirstChild("RuneName")
		
		if runeId and runeId > 0 then
			local res = ResourceData.Resources[runeId]
			if res then
				btn.BackgroundColor3 = res.color
				if nameLbl then nameLbl.Text = string.sub(res.name, 1, 2) end
			end
		else
			btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
			if nameLbl then nameLbl.Text = "+" end
		end
		
		-- Highlight if being edited
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = (editingRuneSlot == i)
		end
	end
end

local function refreshRunePicker()
	if not runePickerFrame then return end
	
	for i = 1, 10 do
		local btn = runePickerButtons[i]
		if not btn then continue end
		
		local count = runeInventory[i] or 0
		local countLbl = btn:FindFirstChild("CountLabel")
		if countLbl then
			countLbl.Text = "x" .. count
		end
		
		-- Check if already used in another slot
		local alreadyUsed = false
		for slotIdx, runeId in ipairs(selectedTurretRunes) do
			if runeId == i and slotIdx ~= editingRuneSlot then
				alreadyUsed = true
				break
			end
		end
		
		local res = ResourceData.Resources[i]
		if count > 0 and not alreadyUsed then
			btn.BackgroundColor3 = res and res.color or Color3.fromRGB(80, 80, 80)
			btn.BackgroundTransparency = 0.1
		else
			btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			btn.BackgroundTransparency = 0.5
		end
	end
end

local function openRunePicker(slotIndex: number)
	editingRuneSlot = slotIndex
	refreshRuneSlots()
	refreshRunePicker()
	if runePickerFrame then
		runePickerFrame.Visible = true
	end
end

local function closeRunePicker()
	editingRuneSlot = nil
	if runePickerFrame then
		runePickerFrame.Visible = false
	end
	refreshRuneSlots()
end

local function onRuneSelected(runeTypeId: number)
	if not editingRuneSlot or not selectedTurretInstanceId then return end
	
	local count = runeInventory[runeTypeId] or 0
	if count <= 0 then return end
	
	-- Check not already in another slot
	for slotIdx, runeId in ipairs(selectedTurretRunes) do
		if runeId == runeTypeId and slotIdx ~= editingRuneSlot then
			return
		end
	end
	
	-- Fire ApplyRune to server
	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if Remotes then
		local ApplyRune = Remotes:FindFirstChild("ApplyRune")
		if ApplyRune then
			ApplyRune:FireServer(selectedTurretInstanceId, runeTypeId)
		end
	end
	
	closeRunePicker()
end

local function showUpgradePanel(instanceId: string, turretTypeId: number, level: number, stats: { damage: number, range: number, fireRate: number }, runes: { number }?)
	selectedTurretInstanceId = instanceId
	selectedTurretData = { turretTypeId = turretTypeId, level = level, stats = stats }
	selectedTurretRunes = runes or {}

	if not upgradePanel then return end
	upgradePanel.Visible = true
	closeRunePicker()

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
	
	refreshRuneSlots()
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

	-- Loadout buttons container (bottom center) - responsive sizing
	local loadoutBar = Instance.new("Frame")
	loadoutBar.Name = "LoadoutBar"
	loadoutBar.Size = UDim2.new(0.35, 0, 0.09, 0) -- 35% width, 9% height
	loadoutBar.Position = UDim2.new(0.5, 0, 1, -10) -- Centered, 10px from bottom
	loadoutBar.AnchorPoint = Vector2.new(0.5, 1) -- Anchor at bottom center
	loadoutBar.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	loadoutBar.BackgroundTransparency = 0.3
	loadoutBar.BorderSizePixel = 0
	loadoutBar.Parent = screen

	-- Constrain min/max size for very small or very large screens
	local barSizeConstraint = Instance.new("UISizeConstraint")
	barSizeConstraint.MinSize = Vector2.new(320, 60)
	barSizeConstraint.MaxSize = Vector2.new(900, 140)
	barSizeConstraint.Parent = loadoutBar

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.1, 0)
	barCorner.Parent = loadoutBar

	local barPadding = Instance.new("UIPadding")
	barPadding.PaddingLeft = UDim.new(0.02, 0)
	barPadding.PaddingRight = UDim.new(0.02, 0)
	barPadding.PaddingTop = UDim.new(0.1, 0)
	barPadding.PaddingBottom = UDim.new(0.1, 0)
	barPadding.Parent = loadoutBar

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.Padding = UDim.new(0.02, 0)
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Parent = loadoutBar

	-- 3 loadout turret buttons - responsive sizing
	for i = 1, 3 do
		local turretId = loadout[i]
		local turret = TurretData.getTurretById(turretId)

		local btn = Instance.new("TextButton")
		btn.Name = "Loadout_" .. i
		btn.Size = UDim2.new(0.3, 0, 1, 0) -- 30% of bar width, full height
		btn.BackgroundColor3 = Color3.fromRGB(40, 60, 100)
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.TextScaled = true
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = loadoutBar

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0.1, 0)
		btnCorner.Parent = btn

		-- Name label (top portion)
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "NameLabel"
		nameLbl.Size = UDim2.new(1, -4, 0.6, 0)
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
		costLbl.Size = UDim2.new(1, -4, 0.35, 0)
		costLbl.Position = UDim2.new(0, 2, 0.6, 0)
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
	upgradePanel.Size = UDim2.new(0, 240, 0, 140)
	upgradePanel.Position = UDim2.new(1, -250, 0.5, -70)
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

	-- Rune picker panel (appears when clicking a proximity rune slot)
	runePickerFrame = Instance.new("Frame")
	runePickerFrame.Name = "RunePicker"
	runePickerFrame.Size = UDim2.new(0, 200, 0, 340)
	runePickerFrame.Position = UDim2.new(0.5, -100, 0.5, -170)
	runePickerFrame.BackgroundColor3 = Color3.fromRGB(20, 15, 35)
	runePickerFrame.BackgroundTransparency = 0.05
	runePickerFrame.BorderSizePixel = 0
	runePickerFrame.Visible = false
	runePickerFrame.Parent = screen

	local pickerCorner = Instance.new("UICorner")
	pickerCorner.CornerRadius = UDim.new(0, 8)
	pickerCorner.Parent = runePickerFrame

	local pickerStroke = Instance.new("UIStroke")
	pickerStroke.Color = Color3.fromRGB(100, 80, 160)
	pickerStroke.Thickness = 2
	pickerStroke.Parent = runePickerFrame

	local pickerTitle = Instance.new("TextLabel")
	pickerTitle.Name = "Title"
	pickerTitle.Size = UDim2.new(1, 0, 0, 28)
	pickerTitle.BackgroundTransparency = 1
	pickerTitle.Text = "Choose Rune"
	pickerTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
	pickerTitle.TextScaled = true
	pickerTitle.Font = Enum.Font.GothamBold
	pickerTitle.Parent = runePickerFrame

	local pickerCloseBtn = Instance.new("TextButton")
	pickerCloseBtn.Name = "CloseBtn"
	pickerCloseBtn.Size = UDim2.new(0, 24, 0, 24)
	pickerCloseBtn.Position = UDim2.new(1, -26, 0, 2)
	pickerCloseBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	pickerCloseBtn.BorderSizePixel = 0
	pickerCloseBtn.Text = "X"
	pickerCloseBtn.TextColor3 = Color3.new(1, 1, 1)
	pickerCloseBtn.TextScaled = true
	pickerCloseBtn.Font = Enum.Font.GothamBold
	pickerCloseBtn.Parent = runePickerFrame

	local pickerCloseBtnCorner = Instance.new("UICorner")
	pickerCloseBtnCorner.CornerRadius = UDim.new(0, 4)
	pickerCloseBtnCorner.Parent = pickerCloseBtn

	pickerCloseBtn.MouseButton1Click:Connect(function()
		closeRunePicker()
	end)

	local pickerList = Instance.new("ScrollingFrame")
	pickerList.Name = "RuneList"
	pickerList.Size = UDim2.new(1, -10, 1, -34)
	pickerList.Position = UDim2.new(0, 5, 0, 30)
	pickerList.BackgroundTransparency = 1
	pickerList.BorderSizePixel = 0
	pickerList.ScrollBarThickness = 4
	pickerList.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
	pickerList.CanvasSize = UDim2.new(0, 0, 0, 0)
	pickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pickerList.Parent = runePickerFrame

	local pickerListLayout = Instance.new("UIListLayout")
	pickerListLayout.Padding = UDim.new(0, 4)
	pickerListLayout.Parent = pickerList

	for i = 1, 10 do
		local res = ResourceData.Resources[i]

		local runeBtn = Instance.new("TextButton")
		runeBtn.Name = "Rune_" .. i
		runeBtn.Size = UDim2.new(1, -4, 0, 28)
		runeBtn.BackgroundColor3 = res.color
		runeBtn.BackgroundTransparency = 0.1
		runeBtn.BorderSizePixel = 0
		runeBtn.Text = ""
		runeBtn.AutoButtonColor = true
		runeBtn.LayoutOrder = i
		runeBtn.Parent = pickerList

		local runeBtnCorner = Instance.new("UICorner")
		runeBtnCorner.CornerRadius = UDim.new(0, 4)
		runeBtnCorner.Parent = runeBtn

		local runeNameLbl = Instance.new("TextLabel")
		runeNameLbl.Name = "NameLabel"
		runeNameLbl.Size = UDim2.new(0.65, 0, 1, 0)
		runeNameLbl.Position = UDim2.new(0, 6, 0, 0)
		runeNameLbl.BackgroundTransparency = 1
		runeNameLbl.Text = res.name
		runeNameLbl.TextColor3 = Color3.new(1, 1, 1)
		runeNameLbl.TextScaled = true
		runeNameLbl.Font = Enum.Font.GothamBold
		runeNameLbl.TextXAlignment = Enum.TextXAlignment.Left
		runeNameLbl.Parent = runeBtn

		local runeCountLbl = Instance.new("TextLabel")
		runeCountLbl.Name = "CountLabel"
		runeCountLbl.Size = UDim2.new(0.3, 0, 1, 0)
		runeCountLbl.Position = UDim2.new(0.68, 0, 0, 0)
		runeCountLbl.BackgroundTransparency = 1
		runeCountLbl.Text = "x0"
		runeCountLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		runeCountLbl.TextScaled = true
		runeCountLbl.Font = Enum.Font.Gotham
		runeCountLbl.TextXAlignment = Enum.TextXAlignment.Right
		runeCountLbl.Parent = runeBtn

		runePickerButtons[i] = runeBtn

		runeBtn.MouseButton1Click:Connect(function()
			onRuneSelected(i)
		end)
	end

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

-- ── Proximity range circle and rune slots ─────────────────────────────────────

local PROXIMITY_RANGE = 14 -- how close the player needs to be to see the range circle

local function clearProximityRuneGui()
	if proximityRuneGui then
		proximityRuneGui:Destroy()
		proximityRuneGui = nil
	end
	proximityRuneSlots = {}
	proximityTurretId = nil
end

local function clearTurretRangeCircle()
	if turretRangeCircle then turretRangeCircle:Destroy(); turretRangeCircle = nil end
	clearProximityRuneGui()
	lastNearTurretModel = nil
end

local function createProximityRuneSlots(turretModel: Model)
	clearProximityRuneGui()
	
	local instanceId = turretModel:GetAttribute("TurretInstanceId")
	if not instanceId then return end
	proximityTurretId = instanceId
	
	-- Read current runes from model
	local runes = {}
	local runeStr = turretModel:GetAttribute("TurretRunes")
	if runeStr and runeStr ~= "" then
		for id in string.gmatch(runeStr, "%d+") do
			table.insert(runes, tonumber(id))
		end
	end
	
	-- Create BillboardGui attached to turret
	local base = turretModel:FindFirstChild("Base")
	if not base then return end
	
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ProximityRuneSlots"
	billboard.Size = UDim2.new(0, 180, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.Adornee = base
	billboard.AlwaysOnTop = true
	billboard.Active = true -- Enable mouse input
	billboard.Parent = playerGui
	proximityRuneGui = billboard
	
	-- Background
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = billboard
	
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 8)
	bgCorner.Parent = bg
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Text = "Rune Slots"
	title.TextColor3 = Color3.fromRGB(200, 180, 255)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Parent = bg
	
	-- Slots container
	local slotsContainer = Instance.new("Frame")
	slotsContainer.Name = "Slots"
	slotsContainer.Size = UDim2.new(1, -10, 0, 44)
	slotsContainer.Position = UDim2.new(0, 5, 0, 20)
	slotsContainer.BackgroundTransparency = 1
	slotsContainer.Parent = bg
	
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = slotsContainer
	
	-- Create 3 rune slots
	for i = 1, 3 do
		local runeId = runes[i]
		local res = runeId and ResourceData.Resources[runeId]
		
		local slot = Instance.new("TextButton")
		slot.Name = "Slot_" .. i
		slot.Size = UDim2.new(0, 44, 0, 44)
		slot.BackgroundColor3 = res and res.color or Color3.fromRGB(50, 50, 70)
		slot.BackgroundTransparency = res and 0.1 or 0.3
		slot.BorderSizePixel = 0
		slot.Text = ""
		slot.AutoButtonColor = true
		slot.Parent = slotsContainer
		
		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 8)
		slotCorner.Parent = slot
		
		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = Color3.fromRGB(100, 80, 160)
		slotStroke.Thickness = 2
		slotStroke.Parent = slot
		
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -4, 1, -4)
		label.Position = UDim2.new(0, 2, 0, 2)
		label.BackgroundTransparency = 1
		label.Text = res and string.sub(res.name, 1, 2) or "+"
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = slot
		
		proximityRuneSlots[i] = slot
		
		-- Click to open rune picker for this slot
		slot.MouseButton1Click:Connect(function()
			-- Check if slot already has a rune (can't replace for now)
			if runes[i] then
				showError("Slot already has a rune")
				return
			end
			-- Check if all 3 slots are full
			if #runes >= 3 then
				showError("All rune slots are full")
				return
			end
			-- Open the rune picker for this turret and slot
			selectedTurretInstanceId = instanceId
			editingRuneSlot = i
			selectedTurretRunes = runes
			if runePickerFrame then
				runePickerFrame.Visible = true
				refreshRunePicker()
			end
		end)
	end
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
	
	-- Also show the rune slots UI
	createProximityRuneSlots(turretModel)
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

		-- Animate orbiting runes on all turrets
		local currentTime = tick()
		for _, obj in workspace:GetChildren() do
			if obj:IsA("Model") and obj:GetAttribute("TurretInstanceId") then
				local base = obj:FindFirstChild("Base")
				if base then
					local basePos = base.Position
					local orbitRadius = 2.5
					local orbitHeight = 3.5
					local orbitSpeed = 0.8 -- radians per second
					
					for _, child in obj:GetChildren() do
						if child.Name:match("^RuneOrb_") then
							local slotIndex = tonumber(child.Name:match("RuneOrb_(%d+)"))
							if slotIndex then
								-- Calculate orbit position with time-based rotation
								local baseAngle = (slotIndex - 1) * (2 * math.pi / 3)
								local angle = baseAngle + currentTime * orbitSpeed
								local offsetX = math.cos(angle) * orbitRadius
								local offsetZ = math.sin(angle) * orbitRadius
								-- Add gentle bobbing
								local bob = math.sin(currentTime * 2 + slotIndex) * 0.3
								child.Position = basePos + Vector3.new(offsetX, orbitHeight + bob, offsetZ)
							end
						end
					end
				end
			end
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
		end
		-- Don't clear selectedSlot when moving away - keep last valid slot
		-- so clicking anywhere confirms placement at that position

		lastHoveredKey = key
	end)
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- Called when a completely new game starts (from lobby)
function TurretHUD.resetForNewGame()
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
	-- Reset placement counts for new game
	turretPlacementCounts = {}
	refreshLoadoutButtons()
end

function TurretHUD.show()
	if screenGui then screenGui.Enabled = true end
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
					
					-- Read runes from model attribute (comma-separated string)
					local runes = {}
					local runeStr = obj:GetAttribute("TurretRunes")
					if runeStr and runeStr ~= "" then
						for id in string.gmatch(runeStr, "%d+") do
							table.insert(runes, tonumber(id))
						end
					end
					
					showUpgradePanel(instanceId, typeId, level, {
						damage = dmg,
						range = rng,
						fireRate = spd,
					}, runes)
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

		-- PlayerColorsAssigned: receive color map from server
		local PlayerColorsAssigned = Remotes:WaitForChild("PlayerColorsAssigned", 10)
		if PlayerColorsAssigned then
			PlayerColorsAssigned.OnClientEvent:Connect(function(colorMap: { [number]: { R: number, G: number, B: number } })
				playerColorMap = {}
				for userId, components in pairs(colorMap) do
					playerColorMap[userId] = Color3.new(components.R, components.G, components.B)
				end
				localPlayerColor = playerColorMap[player.UserId]
			end)
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

		-- TurretCostsUpdate: sync escalating placement costs
		local TurretCostsUpdate = Remotes:WaitForChild("TurretCostsUpdate", 10)
		if TurretCostsUpdate then
			TurretCostsUpdate.OnClientEvent:Connect(function(counts: { [number]: number })
				-- Convert string keys to numbers (Roblox serialization quirk)
				local fixedCounts = {}
				for k, v in pairs(counts) do
					fixedCounts[tonumber(k)] = v
				end
				turretPlacementCounts = fixedCounts
				refreshLoadoutButtons()
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

		-- RuneInventoryUpdate: keep local rune inventory in sync
		local RuneInventoryUpdate = Remotes:WaitForChild("RuneInventoryUpdate", 10)
		if RuneInventoryUpdate then
			RuneInventoryUpdate.OnClientEvent:Connect(function(inventory: { [number]: number })
				runeInventory = inventory
				refreshRunePicker()
			end)
		end

		-- TurretRunesUpdate: update rune slots when runes are applied
		local TurretRunesUpdate = Remotes:WaitForChild("TurretRunesUpdate", 10)
		if TurretRunesUpdate then
			TurretRunesUpdate.OnClientEvent:Connect(function(turretInstanceId: string, runes: { number }, stats: { damage: number, range: number, fireRate: number })
				-- Update model attribute for future reads
				for _, obj in workspace:GetChildren() do
					if obj:IsA("Model") and obj:GetAttribute("TurretInstanceId") == turretInstanceId then
						local runeStr = table.concat(runes, ",")
						obj:SetAttribute("TurretRunes", runeStr)
						obj:SetAttribute("TurretDamage", stats.damage)
						obj:SetAttribute("TurretRange", stats.range)
						obj:SetAttribute("TurretFireRate", stats.fireRate)
						
						-- Refresh proximity rune slots if this turret is nearby
						if proximityTurretId == turretInstanceId and lastNearTurretModel then
							createProximityRuneSlots(lastNearTurretModel)
						end
						break
					end
				end

				-- If this turret's panel is open, update the display
				if selectedTurretInstanceId == turretInstanceId then
					selectedTurretRunes = runes
					if selectedTurretData then
						selectedTurretData.stats = stats
					end
					refreshRuneSlots()
					if upgradeStatsLabel then
						upgradeStatsLabel.Text = string.format(
							"DMG: %.1f  RNG: %.1f  SPD: %.1f",
							stats.damage, stats.range, stats.fireRate
						)
					end
				end
				
				-- Close the rune picker after successful application
				if runePickerFrame and runePickerFrame.Visible then
					runePickerFrame.Visible = false
					editingRuneSlot = nil
				end
			end)
		end

		print("[TurretHUD] HUD initialized and wired to remotes")
	end)
end

return TurretHUD
