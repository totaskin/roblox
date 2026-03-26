-- RuneHUD.luau
-- Client-side rune inventory display and turret rune application panel.
-- Follows the same module pattern as TurretHUD.luau.
-- Tasks 5.1–5.6

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)
local RuneCombinationData = require(game.ReplicatedStorage.Shared.RuneCombinationData)

local RuneHUD = {}

-- ── State ────────────────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local runeInventory: { [number]: number } = {} -- rune type id -> count
local selectedTurretId: string? = nil          -- currently selected turret for rune application
local currentTurretRunes: { number } = {}      -- runes on selected turret

-- UI references
local screenGui: ScreenGui = nil
local inventorySlots: { [number]: { frame: Frame, countLabel: TextLabel } } = {}
local runePanel: Frame = nil
local panelTurretLabel: TextLabel = nil
local panelCurrentRunesLabel: TextLabel = nil
local panelStatPreviewLabel: TextLabel = nil
local panelRuneButtons: { [number]: TextButton } = {}
local errorLabel: TextLabel = nil
local errorHideThread: thread? = nil

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

local function refreshInventoryDisplay()
	for i = 1, 10 do
		local slot = inventorySlots[i]
		if slot then
			local count = runeInventory[i] or 0
			slot.countLabel.Text = "x" .. count
		end
	end
end

local function formatStatPreview(runes: { number }): string
	if #runes == 0 then
		return "No runes applied"
	end
	local combined = RuneCombinationData.computeCombinedMultipliers(runes)
	return string.format(
		"DMG: %.2fx  RNG: %.2fx  SPD: %.2fx",
		combined.damage, combined.range, combined.fireRate
	)
end

local function refreshRunePanel()
	if not runePanel or not runePanel.Visible then return end

	-- Update current runes display
	if panelCurrentRunesLabel then
		if #currentTurretRunes == 0 then
			panelCurrentRunesLabel.Text = "Runes: None"
		else
			local names = {}
			for _, rId in ipairs(currentTurretRunes) do
				local res = ResourceData.Resources[rId]
				if res then
					table.insert(names, res.name)
				end
			end
			panelCurrentRunesLabel.Text = "Runes: " .. table.concat(names, ", ")
		end
	end

	-- Update stat preview
	if panelStatPreviewLabel then
		panelStatPreviewLabel.Text = formatStatPreview(currentTurretRunes)
	end

	-- Update rune buttons (greyed out if count is 0)
	for i = 1, 10 do
		local btn = panelRuneButtons[i]
		if btn then
			local count = runeInventory[i] or 0
			local countLbl = btn:FindFirstChild("CountLabel")
			if countLbl then
				countLbl.Text = "x" .. count
			end
			if count > 0 then
				local res = ResourceData.Resources[i]
				btn.BackgroundColor3 = res and res.color or Color3.fromRGB(80, 80, 80)
				btn.AutoButtonColor = true
			else
				btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
				btn.AutoButtonColor = false
			end
		end
	end
end

-- ── Build Inventory Bar (Task 5.1) ───────────────────────────────────────────

local function buildInventoryBar(parent: ScreenGui): Frame
	local bar = Instance.new("Frame")
	bar.Name = "RuneInventoryBar"
	bar.Size = UDim2.new(0.035, 0, 0.48, 0) -- 3.5% width, 48% height
	bar.Position = UDim2.new(1, -8, 0.5, 0)
	bar.AnchorPoint = Vector2.new(1, 0.5) -- Anchor to right edge, vertically centered
	bar.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0
	bar.Parent = parent

	-- Constrain min/max size
	local barSizeConstraint = Instance.new("UISizeConstraint")
	barSizeConstraint.MinSize = Vector2.new(40, 340)
	barSizeConstraint.MaxSize = Vector2.new(60, 480)
	barSizeConstraint.Parent = bar

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0.005, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = bar

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.01, 0)
	padding.PaddingBottom = UDim.new(0.01, 0)
	padding.Parent = bar

	for i = 1, 10 do
		local res = ResourceData.Resources[i]

		local slot = Instance.new("Frame")
		slot.Name = "RuneSlot_" .. i
		slot.Size = UDim2.new(0.85, 0, 0.09, 0) -- 85% of bar width, 9% of bar height
		slot.BackgroundColor3 = res.color
		slot.BackgroundTransparency = 0.2
		slot.BorderSizePixel = 0
		slot.Parent = bar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.15, 0)
		corner.Parent = slot

		-- Short 1-2 letter abbreviation instead of full name
		local abbrev = string.sub(res.name, 1, 2)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = abbrev
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Parent = slot

		local countLabel = Instance.new("TextLabel")
		countLabel.Name = "CountLabel"
		countLabel.Size = UDim2.new(1, 0, 0.4, 0)
		countLabel.Position = UDim2.new(0, 0, 0.58, 0)
		countLabel.BackgroundTransparency = 1
		countLabel.Text = "x0"
		countLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		countLabel.TextScaled = true
		countLabel.Font = Enum.Font.Gotham
		countLabel.Parent = slot

		inventorySlots[i] = { frame = slot, countLabel = countLabel }
	end

	-- Task 8.3: Shop button below inventory bar (accessible during gameplay) - responsive
	local shopBtn = Instance.new("TextButton")
	shopBtn.Name = "RuneShopBtn"
	shopBtn.Size = UDim2.new(0.035, 0, 0.045, 0) -- 3.5% width, 4.5% height
	shopBtn.Position = UDim2.new(1, -8, 0.5, 0)
	shopBtn.AnchorPoint = Vector2.new(1, -5.5) -- Position below the bar
	shopBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 160)
	shopBtn.BorderSizePixel = 0
	shopBtn.Text = "🔮"
	shopBtn.TextColor3 = Color3.new(1, 1, 1)
	shopBtn.TextScaled = true
	shopBtn.Font = Enum.Font.GothamBold
	shopBtn.Parent = parent

	-- Constrain shop button size
	local shopBtnSizeConstraint = Instance.new("UISizeConstraint")
	shopBtnSizeConstraint.MinSize = Vector2.new(40, 32)
	shopBtnSizeConstraint.MaxSize = Vector2.new(60, 50)
	shopBtnSizeConstraint.Parent = shopBtn

	local shopBtnCorner = Instance.new("UICorner")
	shopBtnCorner.CornerRadius = UDim.new(0.15, 0)
	shopBtnCorner.Parent = shopBtn

	shopBtn.MouseButton1Click:Connect(function()
		local RuneShopUI = require(script.Parent.RuneShopUI)
		RuneShopUI.show()
	end)

	return bar
end

-- ── Build Rune Application Panel (Task 5.2) ──────────────────────────────────

local function buildRunePanel(parent: ScreenGui): Frame
	local panel = Instance.new("Frame")
	panel.Name = "RunePanel"
	panel.Size = UDim2.new(0.18, 0, 0.6, 0) -- 18% width, 60% height
	panel.Position = UDim2.new(0, 10, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0, 0.5) -- Anchor to left edge, vertically centered
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent

	-- Constrain min/max size
	local panelSizeConstraint = Instance.new("UISizeConstraint")
	panelSizeConstraint.MinSize = Vector2.new(220, 400)
	panelSizeConstraint.MaxSize = Vector2.new(320, 600)
	panelSizeConstraint.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	-- Title label - responsive
	panelTurretLabel = Instance.new("TextLabel")
	panelTurretLabel.Name = "TurretLabel"
	panelTurretLabel.Size = UDim2.new(1, -10, 0.06, 0) -- 6% of panel height
	panelTurretLabel.Position = UDim2.new(0, 5, 0.01, 0)
	panelTurretLabel.BackgroundTransparency = 1
	panelTurretLabel.Text = "Apply Runes"
	panelTurretLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	panelTurretLabel.TextScaled = true
	panelTurretLabel.Font = Enum.Font.GothamBold
	panelTurretLabel.Parent = panel

	-- Current runes label - responsive
	panelCurrentRunesLabel = Instance.new("TextLabel")
	panelCurrentRunesLabel.Name = "CurrentRunesLabel"
	panelCurrentRunesLabel.Size = UDim2.new(1, -10, 0.05, 0) -- 5% of panel height
	panelCurrentRunesLabel.Position = UDim2.new(0, 5, 0.075, 0)
	panelCurrentRunesLabel.BackgroundTransparency = 1
	panelCurrentRunesLabel.Text = "Runes: None"
	panelCurrentRunesLabel.TextColor3 = Color3.fromRGB(200, 180, 255)
	panelCurrentRunesLabel.TextScaled = true
	panelCurrentRunesLabel.Font = Enum.Font.Gotham
	panelCurrentRunesLabel.Parent = panel

	-- Stat preview label - responsive
	panelStatPreviewLabel = Instance.new("TextLabel")
	panelStatPreviewLabel.Name = "StatPreviewLabel"
	panelStatPreviewLabel.Size = UDim2.new(1, -10, 0.05, 0) -- 5% of panel height
	panelStatPreviewLabel.Position = UDim2.new(0, 5, 0.125, 0)
	panelStatPreviewLabel.BackgroundTransparency = 1
	panelStatPreviewLabel.Text = "No runes applied"
	panelStatPreviewLabel.TextColor3 = Color3.fromRGB(130, 200, 255)
	panelStatPreviewLabel.TextScaled = true
	panelStatPreviewLabel.Font = Enum.Font.Gotham
	panelStatPreviewLabel.Parent = panel

	-- Rune buttons container - responsive
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "ButtonContainer"
	buttonContainer.Size = UDim2.new(1, -10, 0.77, 0) -- 77% of panel height
	buttonContainer.Position = UDim2.new(0, 5, 0.19, 0)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Parent = panel

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Vertical
	btnLayout.Padding = UDim.new(0.008, 0)
	btnLayout.Parent = buttonContainer

	for i = 1, 10 do
		local res = ResourceData.Resources[i]

		local btn = Instance.new("TextButton")
		btn.Name = "RuneBtn_" .. i
		btn.Size = UDim2.new(1, 0, 0.095, 0) -- ~9.5% of container height each
		btn.BackgroundColor3 = res.color
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = true
		btn.Parent = buttonContainer

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0.12, 0)
		btnCorner.Parent = btn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 6, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = res.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = btn

		local countLbl = Instance.new("TextLabel")
		countLbl.Name = "CountLabel"
		countLbl.Size = UDim2.new(0.3, 0, 1, 0)
		countLbl.Position = UDim2.new(0.7, 0, 0, 0)
		countLbl.BackgroundTransparency = 1
		countLbl.Text = "x0"
		countLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		countLbl.TextScaled = true
		countLbl.Font = Enum.Font.Gotham
		countLbl.TextXAlignment = Enum.TextXAlignment.Right
		countLbl.Parent = btn

		panelRuneButtons[i] = btn

		-- Task 5.3: Wire ApplyRune remote on button click
		btn.MouseButton1Click:Connect(function()
			if not selectedTurretId then return end
			local count = runeInventory[i] or 0
			if count <= 0 then return end

			local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
			if not Remotes then return end
			local ApplyRune = Remotes:FindFirstChild("ApplyRune")
			if ApplyRune then
				ApplyRune:FireServer(selectedTurretId, i)
			end
		end)
	end

	-- Close button - responsive
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0.12, 0, 0.06, 0) -- 12% width, 6% height of panel
	closeBtn.Position = UDim2.new(1, -4, 0, 4)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = panel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0.15, 0)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		RuneHUD.hideRunePanel()
	end)

	-- Error label (below panel) - responsive
	errorLabel = Instance.new("TextLabel")
	errorLabel.Name = "RuneErrorMsg"
	errorLabel.Size = UDim2.new(0.18, 0, 0.035, 0) -- 18% width, 3.5% height
	errorLabel.Position = UDim2.new(0, 10, 0.5, 0)
	errorLabel.AnchorPoint = Vector2.new(0, -9) -- Position below panel
	errorLabel.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	errorLabel.BackgroundTransparency = 0.2
	errorLabel.BorderSizePixel = 0
	errorLabel.Text = ""
	errorLabel.TextColor3 = Color3.new(1, 1, 1)
	errorLabel.TextScaled = true
	errorLabel.Font = Enum.Font.GothamBold
	errorLabel.Visible = false
	errorLabel.Parent = parent

	-- Constrain error label size
	local errSizeConstraint = Instance.new("UISizeConstraint")
	errSizeConstraint.MinSize = Vector2.new(220, 24)
	errSizeConstraint.MaxSize = Vector2.new(320, 36)
	errSizeConstraint.Parent = errorLabel

	local errCorner = Instance.new("UICorner")
	errCorner.CornerRadius = UDim.new(0.15, 0)
	errCorner.Parent = errorLabel

	return panel
end

-- ── Turret click detection (Task 5.2) ────────────────────────────────────────

local function getTurretInstanceFromRaycast(): (string?, Model?)
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500)
	if not result then return nil, nil end

	local hit = result.Instance
	local current = hit
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("TurretInstanceId") then
			return current:GetAttribute("TurretInstanceId"), current :: Model
		end
		current = current.Parent
	end
	return nil, nil
end

-- ── Public API ───────────────────────────────────────────────────────────────

function RuneHUD.showRunePanel(turretInstanceId: string, turretModel: Model?)
	selectedTurretId = turretInstanceId

	-- Read turret info from model attributes
	local turretName = "Turret"
	if turretModel then
		local typeId = turretModel:GetAttribute("TurretTypeId")
		if typeId then
			local TurretData = require(game.ReplicatedStorage.Shared.TurretData)
			local tData = TurretData.getTurretById(typeId)
			if tData then
				turretName = tData.name
			end
		end
	end

	-- Read current runes from model attribute or default to empty
	-- The server broadcasts TurretRunesUpdate which we track in currentTurretRunes
	-- For initial open, we request from model attributes if available
	if turretModel and turretModel:GetAttribute("TurretRunes") then
		-- Runes stored as comma-separated string attribute
		local runeStr = turretModel:GetAttribute("TurretRunes")
		currentTurretRunes = {}
		if runeStr and runeStr ~= "" then
			for id in string.gmatch(runeStr, "%d+") do
				table.insert(currentTurretRunes, tonumber(id))
			end
		end
	else
		currentTurretRunes = {}
	end

	if panelTurretLabel then
		panelTurretLabel.Text = turretName .. " — Runes"
	end

	if runePanel then
		runePanel.Visible = true
	end

	refreshRunePanel()
end

function RuneHUD.hideRunePanel()
	if runePanel then
		runePanel.Visible = false
	end
	selectedTurretId = nil
	currentTurretRunes = {}
end

function RuneHUD.setInventory(inventory: { [number]: number })
	runeInventory = inventory
	refreshInventoryDisplay()
	refreshRunePanel()
end

function RuneHUD.show()
	if screenGui then screenGui.Enabled = true end
	refreshInventoryDisplay()
end

function RuneHUD.hide()
	if screenGui then screenGui.Enabled = false end
	RuneHUD.hideRunePanel()
end

function RuneHUD.init()
	-- Initialize inventory to zeros
	for i = 1, 10 do
		runeInventory[i] = 0
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RuneHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Task 5.1: Build inventory bar
	buildInventoryBar(screenGui)

	-- Task 5.2: Build rune application panel
	runePanel = buildRunePanel(screenGui)

	-- Task 5.2: Click detection for turret selection
	mouse.Button1Down:Connect(function()
		local instanceId, turretModel = getTurretInstanceFromRaycast()
		if instanceId then
			RuneHUD.showRunePanel(instanceId, turretModel)
		end
	end)

	-- Escape closes rune panel
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			if runePanel and runePanel.Visible then
				RuneHUD.hideRunePanel()
			end
		end
	end)

	-- ── Wire remotes (Tasks 5.4, 5.5, 5.6) ──────────────────────────────
	task.spawn(function()
		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		if not Remotes then
			warn("[RuneHUD] Remotes folder not found")
			return
		end

		-- Task 5.4: ApplyRuneResult — show error on rejection
		local ApplyRuneResult = Remotes:WaitForChild("ApplyRuneResult", 10)
		if ApplyRuneResult then
			ApplyRuneResult.OnClientEvent:Connect(function(success: boolean, reason: string?)
				if not success then
					showError(reason or "Rune application failed")
				end
			end)
		end

		-- Task 5.5: RuneInventoryUpdate — update displayed inventory counts
		local RuneInventoryUpdate = Remotes:WaitForChild("RuneInventoryUpdate", 10)
		if RuneInventoryUpdate then
			RuneInventoryUpdate.OnClientEvent:Connect(function(inventory: { [number]: number })
				runeInventory = inventory
				refreshInventoryDisplay()
				refreshRunePanel()
			end)
		end

		-- Task 5.6: TurretRunesUpdate — update turret rune display and stat preview
		local TurretRunesUpdate = Remotes:WaitForChild("TurretRunesUpdate", 10)
		if TurretRunesUpdate then
			TurretRunesUpdate.OnClientEvent:Connect(function(turretInstanceId: string, runes: { number }, stats: { damage: number, range: number, fireRate: number }, _comboQuality: string?)
				-- If the panel is open for this turret, update the display
				if selectedTurretId == turretInstanceId then
					currentTurretRunes = runes
					refreshRunePanel()

					-- Also update the stat preview with actual server stats
					if panelStatPreviewLabel and stats then
						panelStatPreviewLabel.Text = string.format(
							"DMG: %.1f  RNG: %.1f  SPD: %.1f",
							stats.damage, stats.range, stats.fireRate
						)
					end
				end
			end)
		end

		print("[RuneHUD] Initialized and wired to remotes")
	end)
end

return RuneHUD
