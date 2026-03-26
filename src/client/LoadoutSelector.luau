-- LoadoutSelector.luau
-- Combined lobby UI: centered loadout slots + turret picker overlay + shop toggle button.
-- Click a loadout slot to open a picker of unlocked turrets. Loadout is saved to server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TurretData = require(game.ReplicatedStorage.Shared.TurretData)

local LoadoutSelector = {}

-- ── State ────────────────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local unlocks: { [number]: boolean } = { [1] = true }
local loadout: { number } = {}
local persistentCoins: number = 0

-- Which slot (1-3) is currently being edited, nil = picker closed
local editingSlot: number? = nil

-- UI references
local screenRef: ScreenGui = nil
local slotButtons: { TextButton } = {}
local pickerFrame: Frame = nil
local pickerTiles: { [number]: Frame } = {}
local statusLabel: TextLabel = nil
local shopButtonRef: TextButton = nil

-- Reference to TurretShopUI for toggling
local TurretShopUI = nil

-- ── Helpers ──────────────────────────────────────────────────────────────────

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

local function refreshSlots()
	for i = 1, 3 do
		local btn = slotButtons[i]
		if not btn then continue end
		local nameLabel = btn:FindFirstChild("SlotName")
		local turretId = loadout[i]
		if turretId then
			local turret = TurretData.getTurretById(turretId)
			if nameLabel then nameLabel.Text = turret and turret.name or ("ID " .. turretId) end
			btn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
		else
			if nameLabel then nameLabel.Text = "+" end
			btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
		end
		-- Highlight the slot being edited
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = (editingSlot == i)
		end
	end
end

local function refreshStatus()
	if not statusLabel then return end
	local count = #loadout
	if count == 0 then
		statusLabel.Text = "Tap a slot to add a turret"
		statusLabel.TextColor3 = Color3.fromRGB(255, 180, 80)
	else
		statusLabel.Text = count .. "/3 selected"
		statusLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
	end
end

local function closePicker()
	editingSlot = nil
	if pickerFrame then pickerFrame.Visible = false end
	refreshSlots()
end

local function refreshPickerTiles()
	if not pickerFrame then return end
	for _, turret in TurretData.getAllTurrets() do
		local tile = pickerTiles[turret.id]
		if not tile then continue end
		local isUnlocked = unlocks[turret.id] == true
		-- Check if already in loadout (in a different slot)
		local alreadyUsed = false
		for slotIdx, id in loadout do
			if id == turret.id and slotIdx ~= editingSlot then
				alreadyUsed = true
				break
			end
		end

		local canAfford = persistentCoins >= turret.shopPrice

		if isUnlocked and not alreadyUsed then
			tile.BackgroundTransparency = 0.15
			tile.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
		elseif isUnlocked and alreadyUsed then
			tile.BackgroundTransparency = 0.65
			tile.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
		elseif not isUnlocked and canAfford then
			-- Locked but affordable: show with a green-ish tint
			tile.BackgroundTransparency = 0.3
			tile.BackgroundColor3 = Color3.fromRGB(30, 50, 35)
		else
			-- Locked and can't afford: greyed out
			tile.BackgroundTransparency = 0.7
			tile.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		end

		local lockedLbl = tile:FindFirstChild("LockedLabel")
		if lockedLbl then
			if not isUnlocked then
				local priceText = canAfford and ("💰 " .. turret.shopPrice) or ("🔒 " .. turret.shopPrice)
				lockedLbl.Text = priceText
				lockedLbl.TextColor3 = canAfford and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(150, 150, 150)
				lockedLbl.Visible = true
			else
				lockedLbl.Visible = false
			end
		end
		local usedLbl = tile:FindFirstChild("UsedLabel")
		if usedLbl then
			usedLbl.Visible = isUnlocked and alreadyUsed
		end
	end
end

local function openPicker(slotIndex: number)
	editingSlot = slotIndex
	refreshPickerTiles()
	if pickerFrame then pickerFrame.Visible = true end
	refreshSlots()
end

local function onPickerTurretSelected(turretId: number)
	if not editingSlot then return end

	-- If locked, try to buy it
	if not unlocks[turretId] then
		local turret = TurretData.getTurretById(turretId)
		if not turret or persistentCoins < turret.shopPrice then return end
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if Remotes then
			local BuyTurret = Remotes:FindFirstChild("BuyTurret")
			if BuyTurret then
				BuyTurret:FireServer(turretId)
			end
		end
		return -- wait for ShopUpdate to refresh unlocks
	end

	-- Check not already in another slot
	for slotIdx, id in loadout do
		if id == turretId and slotIdx ~= editingSlot then return end
	end

	-- Place into the editing slot
	if editingSlot <= #loadout then
		loadout[editingSlot] = turretId
	else
		-- Fill gaps if needed
		while #loadout < editingSlot - 1 do
			table.insert(loadout, 0)
		end
		if editingSlot <= #loadout then
			loadout[editingSlot] = turretId
		else
			table.insert(loadout, turretId)
		end
	end

	-- Remove any 0 placeholders
	local cleaned = {}
	for _, id in loadout do
		if id ~= 0 then table.insert(cleaned, id) end
	end
	loadout = cleaned

	closePicker()
	refreshSlots()
	refreshStatus()
	fireSetLoadout()
end

local function onSlotClicked(slotIndex: number)
	if editingSlot == slotIndex then
		-- Clicking same slot closes picker
		closePicker()
		return
	end
	-- If slot has a turret, clicking it opens picker to replace; long-term could clear
	openPicker(slotIndex)
end

local function onSlotRightClicked(slotIndex: number)
	-- Right click / clear: remove turret from this slot
	if slotIndex <= #loadout then
		table.remove(loadout, slotIndex)
		closePicker()
		refreshSlots()
		refreshStatus()
		fireSetLoadout()
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function buildUI(): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "LoadoutSelectorUI"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- ── Shop toggle button (top-right corner) ────────────────────────────
	shopButtonRef = Instance.new("TextButton")
	shopButtonRef.Name = "ShopToggleBtn"
	shopButtonRef.Size = UDim2.new(0, 150, 0, 44)
	shopButtonRef.Position = UDim2.new(1, -160, 0, 56)
	shopButtonRef.BackgroundColor3 = Color3.fromRGB(50, 30, 100)
	shopButtonRef.BorderSizePixel = 0
	shopButtonRef.Text = "Turrets"
	shopButtonRef.TextColor3 = Color3.fromRGB(255, 220, 80)
	shopButtonRef.TextScaled = true
	shopButtonRef.Font = Enum.Font.GothamMedium
	shopButtonRef.Parent = screen

	local shopBtnCorner = Instance.new("UICorner")
	shopBtnCorner.CornerRadius = UDim.new(0, 8)
	shopBtnCorner.Parent = shopButtonRef

	local shopBtnStroke = Instance.new("UIStroke")
	shopBtnStroke.Color = Color3.fromRGB(255, 200, 50)
	shopBtnStroke.Thickness = 2
	shopBtnStroke.Parent = shopButtonRef

	shopButtonRef.MouseButton1Click:Connect(function()
		if not TurretShopUI then
			TurretShopUI = require(script.Parent.TurretShopUI)
		end
		-- Toggle shop visibility
		local shopGui = playerGui:FindFirstChild("TurretShopUI")
		if shopGui then
			shopGui.Enabled = not shopGui.Enabled
		end
	end)

	-- ── Loadout bar (bottom center) ──────────────────────────────────────
	local loadoutBar = Instance.new("Frame")
	loadoutBar.Name = "LoadoutBar"
	loadoutBar.Size = UDim2.new(0, 340, 0, 90)
	loadoutBar.Position = UDim2.new(0.5, -170, 1, -100)
	loadoutBar.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	loadoutBar.BackgroundTransparency = 0.15
	loadoutBar.BorderSizePixel = 0
	loadoutBar.Parent = screen

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 10)
	barCorner.Parent = loadoutBar

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 18)
	titleLabel.Position = UDim2.new(0, 0, 0, 2)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Loadout"
	titleLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = loadoutBar

	-- Slots row
	local slotsRow = Instance.new("Frame")
	slotsRow.Name = "SlotsRow"
	slotsRow.Size = UDim2.new(1, -20, 0, 48)
	slotsRow.Position = UDim2.new(0, 10, 0, 22)
	slotsRow.BackgroundTransparency = 1
	slotsRow.Parent = loadoutBar

	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.FillDirection = Enum.FillDirection.Horizontal
	slotsLayout.Padding = UDim.new(0, 8)
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsLayout.Parent = slotsRow

	for i = 1, 3 do
		local slotBtn = Instance.new("TextButton")
		slotBtn.Name = "Slot_" .. i
		slotBtn.Size = UDim2.new(0, 100, 0, 48)
		slotBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
		slotBtn.BorderSizePixel = 0
		slotBtn.Text = ""
		slotBtn.AutoButtonColor = true
		slotBtn.Parent = slotsRow

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 6)
		slotCorner.Parent = slotBtn

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = Color3.fromRGB(255, 220, 80)
		slotStroke.Thickness = 2
		slotStroke.Enabled = false
		slotStroke.Parent = slotBtn

		local slotName = Instance.new("TextLabel")
		slotName.Name = "SlotName"
		slotName.Size = UDim2.new(1, -6, 1, -6)
		slotName.Position = UDim2.new(0, 3, 0, 3)
		slotName.BackgroundTransparency = 1
		slotName.Text = "+"
		slotName.TextColor3 = Color3.fromRGB(200, 200, 200)
		slotName.TextScaled = true
		slotName.Font = Enum.Font.GothamBold
		slotName.Parent = slotBtn

		slotButtons[i] = slotBtn

		slotBtn.MouseButton1Click:Connect(function()
			onSlotClicked(i)
		end)
		slotBtn.MouseButton2Click:Connect(function()
			onSlotRightClicked(i)
		end)
	end

	-- Status label
	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, 0, 0, 16)
	statusLabel.Position = UDim2.new(0, 0, 1, -18)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Tap a slot to add a turret"
	statusLabel.TextColor3 = Color3.fromRGB(255, 180, 80)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Parent = loadoutBar

	-- ── Picker overlay (appears above loadout bar when editing a slot) ───
	pickerFrame = Instance.new("Frame")
	pickerFrame.Name = "TurretPicker"
	pickerFrame.Size = UDim2.new(0, 360, 0, 280)
	pickerFrame.Position = UDim2.new(0.5, -180, 1, -390)
	pickerFrame.BackgroundColor3 = Color3.fromRGB(20, 15, 40)
	pickerFrame.BackgroundTransparency = 0.08
	pickerFrame.BorderSizePixel = 0
	pickerFrame.Visible = false
	pickerFrame.Parent = screen

	local pickerCorner = Instance.new("UICorner")
	pickerCorner.CornerRadius = UDim.new(0, 10)
	pickerCorner.Parent = pickerFrame

	local pickerStroke = Instance.new("UIStroke")
	pickerStroke.Color = Color3.fromRGB(100, 80, 160)
	pickerStroke.Thickness = 2
	pickerStroke.Parent = pickerFrame

	-- Picker header
	local pickerHeader = Instance.new("TextLabel")
	pickerHeader.Name = "PickerHeader"
	pickerHeader.Size = UDim2.new(1, 0, 0, 28)
	pickerHeader.BackgroundTransparency = 1
	pickerHeader.Text = "Choose a Turret"
	pickerHeader.TextColor3 = Color3.fromRGB(255, 220, 80)
	pickerHeader.TextScaled = true
	pickerHeader.Font = Enum.Font.GothamBold
	pickerHeader.Parent = pickerFrame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -30, 0, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = pickerFrame

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		closePicker()
	end)

	-- Scrolling list of turrets
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "TurretList"
	scrollFrame.Size = UDim2.new(1, -12, 1, -34)
	scrollFrame.Position = UDim2.new(0, 6, 0, 30)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = pickerFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame

	-- Build a tile for each turret
	local allTurrets = TurretData.getAllTurrets()
	for idx, turret in allTurrets do
		local tile = Instance.new("TextButton")
		tile.Name = "Pick_" .. turret.id
		tile.Size = UDim2.new(1, -10, 0, 52)
		tile.BackgroundColor3 = Color3.fromRGB(35, 30, 55)
		tile.BackgroundTransparency = 0.15
		tile.BorderSizePixel = 0
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.LayoutOrder = idx
		tile.Parent = scrollFrame

		local tileCorner = Instance.new("UICorner")
		tileCorner.CornerRadius = UDim.new(0, 6)
		tileCorner.Parent = tile

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "TurretName"
		nameLabel.Size = UDim2.new(0.6, 0, 0, 22)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = turret.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = tile

		-- Stats
		local statsText = string.format("DMG:%d  RNG:%d  SPD:%.1f", turret.damage, turret.range, turret.fireRate)
		local statsLbl = Instance.new("TextLabel")
		statsLbl.Name = "Stats"
		statsLbl.Size = UDim2.new(1, -16, 0, 16)
		statsLbl.Position = UDim2.new(0, 8, 0, 28)
		statsLbl.BackgroundTransparency = 1
		statsLbl.Text = statsText
		statsLbl.TextColor3 = Color3.fromRGB(130, 200, 255)
		statsLbl.TextScaled = true
		statsLbl.Font = Enum.Font.Gotham
		statsLbl.TextXAlignment = Enum.TextXAlignment.Left
		statsLbl.Parent = tile

		-- Locked label (shows price)
		local lockedLabel = Instance.new("TextLabel")
		lockedLabel.Name = "LockedLabel"
		lockedLabel.Size = UDim2.new(0.4, 0, 0, 20)
		lockedLabel.Position = UDim2.new(0.58, 0, 0, 4)
		lockedLabel.BackgroundTransparency = 1
		lockedLabel.Text = "🔒"
		lockedLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		lockedLabel.TextScaled = true
		lockedLabel.Font = Enum.Font.Gotham
		lockedLabel.TextXAlignment = Enum.TextXAlignment.Right
		lockedLabel.Visible = not (unlocks[turret.id] == true)
		lockedLabel.Parent = tile

		-- Already used label
		local usedLabel = Instance.new("TextLabel")
		usedLabel.Name = "UsedLabel"
		usedLabel.Size = UDim2.new(0.3, 0, 0, 20)
		usedLabel.Position = UDim2.new(0.68, 0, 0, 4)
		usedLabel.BackgroundTransparency = 1
		usedLabel.Text = "In Use"
		usedLabel.TextColor3 = Color3.fromRGB(200, 180, 100)
		usedLabel.TextScaled = true
		usedLabel.Font = Enum.Font.Gotham
		usedLabel.TextXAlignment = Enum.TextXAlignment.Right
		usedLabel.Visible = false
		usedLabel.Parent = tile

		pickerTiles[turret.id] = tile

		tile.MouseButton1Click:Connect(function()
			onPickerTurretSelected(turret.id)
		end)
	end

	return screen
end

-- ── Public API ───────────────────────────────────────────────────────────────

function LoadoutSelector.show()
	if screenRef then screenRef.Enabled = true end
end

function LoadoutSelector.hide()
	if screenRef then screenRef.Enabled = false end
	closePicker()
end

function LoadoutSelector.init()
	local screen = buildUI()
	screen.Parent = playerGui
	screenRef = screen

	-- Auto-select scout if only 1 turret unlocked and loadout is empty
	local function tryAutoFill()
		local unlockedIds = {}
		for id, _ in unlocks do
			table.insert(unlockedIds, id)
		end
		if #unlockedIds == 1 and #loadout == 0 then
			loadout = { unlockedIds[1] }
			refreshSlots()
			refreshStatus()
			fireSetLoadout()
		end
	end

	-- Don't auto-fill immediately - wait for server to send saved loadout first
	refreshSlots()
	refreshStatus()

	-- Wire remotes
	task.spawn(function()
		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		if not Remotes then
			warn("[LoadoutSelector] Remotes folder not found")
			return
		end

		local SetLoadoutResult = Remotes:WaitForChild("SetLoadoutResult", 10)
		local ShopUpdate = Remotes:WaitForChild("ShopUpdate", 10)
		local SendLoadout = Remotes:WaitForChild("SendLoadout", 10)

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

		-- Listen for server sending saved loadout (on join)
		if SendLoadout then
			SendLoadout.OnClientEvent:Connect(function(serverLoadout: { number })
				if serverLoadout and #serverLoadout > 0 then
					loadout = serverLoadout
					refreshSlots()
					refreshStatus()
				else
					-- No saved loadout from server, try auto-fill
					tryAutoFill()
				end
			end)
		end

		-- Listen for shop updates (new turret purchased)
		if ShopUpdate then
			ShopUpdate.OnClientEvent:Connect(function(newUnlockArray: { number }, newCoins: number)
				local dict: { [number]: boolean } = {}
				for _, id in ipairs(newUnlockArray) do
					dict[id] = true
				end
				unlocks = dict
				persistentCoins = newCoins

				-- Remove loadout entries for turrets no longer unlocked
				local changed = false
				for i = #loadout, 1, -1 do
					if not unlocks[loadout[i]] then
						table.remove(loadout, i)
						changed = true
					end
				end

				-- Only try auto-fill if loadout is now empty after removing invalid entries
				if #loadout == 0 then
					tryAutoFill()
				elseif changed then
					refreshSlots()
					refreshStatus()
					fireSetLoadout()
				end
				-- Refresh picker if open
				if editingSlot then
					refreshPickerTiles()
				end
			end)
		end

		print("[LoadoutSelector] Loadout selector initialized")
	end)
end

return LoadoutSelector
