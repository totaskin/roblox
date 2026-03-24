-- LoadoutSelector.luau
-- Lobby loadout picker UI: select 1-3 turrets from unlocked set before entering a game.
-- Fires SetLoadout remote when loadout changes, listens to SetLoadoutResult and ShopUpdate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TurretData = require(game.ReplicatedStorage.Shared.TurretData)

local LoadoutSelector = {}

-- ── State ────────────────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local unlocks: { [number]: boolean } = { [1] = true } -- Scout unlocked by default
local loadout: { number } = {} -- up to 3 turret ids

-- UI references
local slotFrames: { Frame } = {}
local slotLabels: { TextLabel } = {}
local tileButtons: { [number]: TextButton } = {}
local tileHighlights: { [number]: Frame } = {}
local statusLabel: TextLabel = nil
local blockingOverlay: Frame = nil

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function isInLoadout(turretId: number): boolean
	for _, id in loadout do
		if id == turretId then return true end
	end
	return false
end

local function removeFromLoadout(turretId: number)
	for i, id in loadout do
		if id == turretId then
			table.remove(loadout, i)
			return
		end
	end
end

local function refreshSlots()
	for i = 1, 3 do
		local label = slotLabels[i]
		local frame = slotFrames[i]
		if not label or not frame then continue end

		local turretId = loadout[i]
		if turretId then
			local turret = TurretData.getTurretById(turretId)
			label.Text = turret and turret.name or ("ID " .. turretId)
			frame.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
		else
			label.Text = "Empty"
			frame.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
		end
	end
end

local function refreshTileHighlights()
	for turretId, highlight in tileHighlights do
		highlight.Visible = isInLoadout(turretId)
	end
end

local function refreshStatus()
	if not statusLabel then return end
	local count = #loadout
	if count == 0 then
		statusLabel.Text = "Select at least 1 turret"
		statusLabel.TextColor3 = Color3.fromRGB(255, 180, 80)
	elseif count < 3 then
		statusLabel.Text = count .. "/3 selected — ready!"
		statusLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
	else
		statusLabel.Text = "Loadout full (3/3)"
		statusLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
	end
end

local function refreshBlockingOverlay()
	if not blockingOverlay then return end
	-- Show warning only when no turrets selected at all
	blockingOverlay.Visible = #loadout < 1
end

local function fireSetLoadout()
	if #loadout < 1 then return end
	task.spawn(function()
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not Remotes then return end
		local SetLoadout = Remotes:FindFirstChild("SetLoadout")
		if SetLoadout then
			SetLoadout:FireServer(loadout)
		end
	end)
end

local function refreshAll()
	refreshSlots()
	refreshTileHighlights()
	refreshStatus()
	refreshBlockingOverlay()
end

-- Auto-select the single turret when only 1 is unlocked
local function tryAutoFill()
	local unlockedIds = {}
	for id, _ in unlocks do
		table.insert(unlockedIds, id)
	end

	if #unlockedIds == 1 and #loadout == 0 then
		loadout = { unlockedIds[1] }
		refreshAll()
		fireSetLoadout()
	end
end

local function onTurretTileClicked(turretId: number)
	if not unlocks[turretId] then return end

	if isInLoadout(turretId) then
		-- Deselect: remove from loadout
		removeFromLoadout(turretId)
	else
		-- Select: add to next empty slot (max 3)
		if #loadout >= 3 then return end
		table.insert(loadout, turretId)
	end

	refreshAll()
	fireSetLoadout()
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function buildUI(): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "LoadoutSelectorUI"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Main container (left side of screen)
	local container = Instance.new("Frame")
	container.Name = "LoadoutContainer"
	container.Size = UDim2.new(0, 280, 0, 420)
	container.Position = UDim2.new(0, 10, 0.5, -210)
	container.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.Parent = screen

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 8)
	containerCorner.Parent = container

	-- Header
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 30)
	header.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.Text = "Turret Loadout"
	header.TextColor3 = Color3.fromRGB(255, 220, 80)
	header.TextScaled = true
	header.Font = Enum.Font.GothamBold
	header.Parent = container

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 8)
	headerCorner.Parent = header

	-- 3 loadout slots at the top
	local slotsRow = Instance.new("Frame")
	slotsRow.Name = "SlotsRow"
	slotsRow.Size = UDim2.new(1, -10, 0, 40)
	slotsRow.Position = UDim2.new(0, 5, 0, 34)
	slotsRow.BackgroundTransparency = 1
	slotsRow.Parent = container

	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.FillDirection = Enum.FillDirection.Horizontal
	slotsLayout.Padding = UDim.new(0, 4)
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsLayout.Parent = slotsRow

	for i = 1, 3 do
		local slotFrame = Instance.new("Frame")
		slotFrame.Name = "Slot_" .. i
		slotFrame.Size = UDim2.new(0, 85, 0, 36)
		slotFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
		slotFrame.BorderSizePixel = 0
		slotFrame.Parent = slotsRow

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 4)
		slotCorner.Parent = slotFrame

		local slotLabel = Instance.new("TextLabel")
		slotLabel.Name = "SlotLabel"
		slotLabel.Size = UDim2.new(1, -4, 1, -4)
		slotLabel.Position = UDim2.new(0, 2, 0, 2)
		slotLabel.BackgroundTransparency = 1
		slotLabel.Text = "Empty"
		slotLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		slotLabel.TextScaled = true
		slotLabel.Font = Enum.Font.Gotham
		slotLabel.Parent = slotFrame

		slotFrames[i] = slotFrame
		slotLabels[i] = slotLabel
	end

	-- Status label
	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -10, 0, 20)
	statusLabel.Position = UDim2.new(0, 5, 0, 78)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Select 3 turrets"
	statusLabel.TextColor3 = Color3.fromRGB(255, 180, 80)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Parent = container

	-- Scrolling frame for turret tiles
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "TurretTiles"
	scrollFrame.Size = UDim2.new(1, -10, 1, -106)
	scrollFrame.Position = UDim2.new(0, 5, 0, 102)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = container

	local tilesLayout = Instance.new("UIListLayout")
	tilesLayout.Padding = UDim.new(0, 4)
	tilesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tilesLayout.Parent = scrollFrame

	-- Build a tile for each turret
	local allTurrets = TurretData.getAllTurrets()
	for idx, turret in allTurrets do
		local tile = Instance.new("TextButton")
		tile.Name = "Tile_" .. turret.id
		tile.Size = UDim2.new(1, -8, 0, 50)
		tile.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
		tile.BackgroundTransparency = 0.2
		tile.BorderSizePixel = 0
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.LayoutOrder = idx
		tile.Parent = scrollFrame

		local tileCorner = Instance.new("UICorner")
		tileCorner.CornerRadius = UDim.new(0, 6)
		tileCorner.Parent = tile

		-- Turret name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "TurretName"
		nameLabel.Size = UDim2.new(0.65, 0, 0, 20)
		nameLabel.Position = UDim2.new(0, 6, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = turret.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = tile

		-- Stats line
		local statsText = string.format("DMG:%d  RNG:%d  SPD:%.1f", turret.damage, turret.range, turret.fireRate)
		local statsLbl = Instance.new("TextLabel")
		statsLbl.Name = "Stats"
		statsLbl.Size = UDim2.new(1, -12, 0, 16)
		statsLbl.Position = UDim2.new(0, 6, 0, 26)
		statsLbl.BackgroundTransparency = 1
		statsLbl.Text = statsText
		statsLbl.TextColor3 = Color3.fromRGB(130, 200, 255)
		statsLbl.TextScaled = true
		statsLbl.Font = Enum.Font.Gotham
		statsLbl.TextXAlignment = Enum.TextXAlignment.Left
		statsLbl.Parent = tile

		-- Locked overlay label (shown when turret is locked)
		local lockedLabel = Instance.new("TextLabel")
		lockedLabel.Name = "LockedLabel"
		lockedLabel.Size = UDim2.new(0.3, 0, 0, 18)
		lockedLabel.Position = UDim2.new(0.68, 0, 0, 4)
		lockedLabel.BackgroundTransparency = 1
		lockedLabel.Text = "🔒"
		lockedLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		lockedLabel.TextScaled = true
		lockedLabel.Font = Enum.Font.Gotham
		lockedLabel.TextXAlignment = Enum.TextXAlignment.Right
		lockedLabel.Visible = not (unlocks[turret.id] == true)
		lockedLabel.Parent = tile

		-- Selection highlight border
		local highlight = Instance.new("Frame")
		highlight.Name = "Highlight"
		highlight.Size = UDim2.new(1, 0, 1, 0)
		highlight.BackgroundTransparency = 1
		highlight.BorderSizePixel = 0
		highlight.Visible = false
		highlight.Parent = tile

		local highlightStroke = Instance.new("UIStroke")
		highlightStroke.Color = Color3.fromRGB(80, 220, 80)
		highlightStroke.Thickness = 2
		highlightStroke.Parent = highlight

		local highlightCorner = Instance.new("UICorner")
		highlightCorner.CornerRadius = UDim.new(0, 6)
		highlightCorner.Parent = highlight

		tileButtons[turret.id] = tile
		tileHighlights[turret.id] = highlight

		tile.MouseButton1Click:Connect(function()
			onTurretTileClicked(turret.id)
		end)
	end

	-- Blocking overlay: a subtle banner shown when loadout is incomplete
	blockingOverlay = Instance.new("Frame")
	blockingOverlay.Name = "LoadoutBlockOverlay"
	blockingOverlay.Size = UDim2.new(0, 260, 0, 28)
	blockingOverlay.Position = UDim2.new(0, 10, 1, -40)
	blockingOverlay.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
	blockingOverlay.BackgroundTransparency = 0.2
	blockingOverlay.BorderSizePixel = 0
	blockingOverlay.Visible = true
	blockingOverlay.Parent = screen

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 6)
	overlayCorner.Parent = blockingOverlay

	local overlayLabel = Instance.new("TextLabel")
	overlayLabel.Size = UDim2.new(1, -8, 1, -4)
	overlayLabel.Position = UDim2.new(0, 4, 0, 2)
	overlayLabel.BackgroundTransparency = 1
	overlayLabel.Text = "⚠ Select at least 1 turret before starting"
	overlayLabel.TextColor3 = Color3.new(1, 1, 1)
	overlayLabel.TextScaled = true
	overlayLabel.Font = Enum.Font.GothamBold
	overlayLabel.Parent = blockingOverlay

	return screen
end

-- Refresh tile visibility based on current unlocks
local function refreshTileVisibility()
	for _, turret in TurretData.getAllTurrets() do
		local tile = tileButtons[turret.id]
		if not tile then continue end
		local isUnlocked = unlocks[turret.id] == true
		-- Dim locked tiles
		tile.BackgroundTransparency = isUnlocked and 0.2 or 0.6
		-- Update locked label
		local lockedLabel = tile:FindFirstChild("LockedLabel")
		if lockedLabel then
			lockedLabel.Visible = not isUnlocked
		end
	end
end

-- ── Public API ───────────────────────────────────────────────────────────────

local screenRef: ScreenGui = nil

function LoadoutSelector.show()
	if screenRef then screenRef.Enabled = true end
end

function LoadoutSelector.hide()
	if screenRef then screenRef.Enabled = false end
end

function LoadoutSelector.init()
	local screen = buildUI()
	screen.Parent = playerGui
	screenRef = screen

	-- Initial refresh
	refreshTileVisibility()
	tryAutoFill()
	refreshAll()

	-- Wire remotes
	task.spawn(function()
		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		if not Remotes then
			warn("[LoadoutSelector] Remotes folder not found")
			return
		end

		local SetLoadoutResult = Remotes:WaitForChild("SetLoadoutResult", 10)
		local ShopUpdate = Remotes:WaitForChild("ShopUpdate", 10)

		-- Listen for loadout confirmation
		if SetLoadoutResult then
			SetLoadoutResult.OnClientEvent:Connect(function(success: boolean, reason: string?)
				if success then
					if statusLabel then
						statusLabel.Text = "Loadout saved!"
						statusLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
					end
				else
					if statusLabel then
						statusLabel.Text = reason or "Loadout rejected"
						statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
					end
				end
			end)
		end

		-- Listen for shop updates (new turret purchased — unlocks sent as array of ids)
		if ShopUpdate then
			ShopUpdate.OnClientEvent:Connect(function(newUnlockArray: { number }, _newCoins: number)
				-- Convert array of turret ids back to dictionary for fast lookup
				local dict: { [number]: boolean } = {}
				for _, id in ipairs(newUnlockArray) do
					dict[id] = true
				end
				unlocks = dict
				refreshTileVisibility()

				-- Remove any loadout entries for turrets that are no longer unlocked
				local changed = false
				for i = #loadout, 1, -1 do
					if not unlocks[loadout[i]] then
						table.remove(loadout, i)
						changed = true
					end
				end

				-- Re-check auto-fill after unlock changes
				tryAutoFill()

				if changed then
					refreshAll()
				end
			end)
		end

		print("[LoadoutSelector] Loadout selector initialized")
	end)
end

return LoadoutSelector
