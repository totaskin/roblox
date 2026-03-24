-- UI.luau
-- Main HUD: money, base health, wave info, resource inventory, tower builder panel

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local TowerData    = require(game.ReplicatedStorage.Shared.TowerData)
local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)
local TowerPlacer  = require(script.Parent.TowerPlacer)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UI = {}

-- State
local money        = 0
local baseHealth   = 20
local currentRound = 0
local inventory: { [number]: number } = {}
local selectedResources: { number } = {}  -- resources chosen for next tower

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function makeLabel(parent, name, text, pos, size, fontSize, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.Position = pos
	label.Size = size
	label.BackgroundTransparency = 1
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = parent
	return label
end

local function makeFrame(parent, name, pos, size, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color or Color3.fromRGB(20, 20, 30)
	f.BackgroundTransparency = transparency or 0.3
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function makeButton(parent, name, text, pos, size, bgColor)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Text = text
	btn.Position = pos
	btn.Size = size
	btn.BackgroundColor3 = bgColor or Color3.fromRGB(60, 120, 200)
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextScaled = true
	btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	btn.Parent = parent
	return btn
end

-- ── Build ScreenGui ───────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TowerDefenseHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ── Top bar ──────────────────────────────────────────────────────────────────

local topBar = makeFrame(screenGui, "TopBar",
	UDim2.new(0, 0, 0, 0),
	UDim2.new(1, 0, 0, 50),
	Color3.fromRGB(15, 15, 25), 0.15)

local moneyLabel = makeLabel(topBar, "Money", "💰 150",
	UDim2.new(0, 10, 0, 5), UDim2.new(0, 160, 0, 40),
	14, Color3.fromRGB(255, 220, 50))

local baseLabel = makeLabel(topBar, "BaseHealth", "🏰 20",
	UDim2.new(0.5, -80, 0, 5), UDim2.new(0, 160, 0, 40),
	14, Color3.fromRGB(100, 220, 100))

local roundLabel = makeLabel(topBar, "Round", "Round 0",
	UDim2.new(1, -170, 0, 5), UDim2.new(0, 160, 0, 40),
	14, Color3.fromRGB(180, 180, 255))

-- ── Wave notification banner ──────────────────────────────────────────────────

local waveBanner = makeFrame(screenGui, "WaveBanner",
	UDim2.new(0.5, -200, 0, 60),
	UDim2.new(0, 400, 0, 50),
	Color3.fromRGB(200, 60, 60), 0.1)
waveBanner.Visible = false

local waveBannerLabel = makeLabel(waveBanner, "Label", "",
	UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0),
	16, Color3.new(1, 1, 1))

local function showBanner(text: string, duration: number)
	waveBannerLabel.Text = text
	waveBanner.Visible = true
	task.delay(duration, function()
		waveBanner.Visible = false
	end)
end

-- ── Resource inventory panel (bottom left) ────────────────────────────────────

local invPanel = makeFrame(screenGui, "Inventory",
	UDim2.new(0, 10, 1, -220),
	UDim2.new(0, 320, 0, 210),
	Color3.fromRGB(15, 15, 25), 0.2)

makeLabel(invPanel, "Title", "Resources",
	UDim2.new(0, 5, 0, 2), UDim2.new(1, -10, 0, 24),
	12, Color3.fromRGB(200, 200, 255))

local invGrid = Instance.new("Frame")
invGrid.Name = "Grid"
invGrid.Position = UDim2.new(0, 5, 0, 28)
invGrid.Size = UDim2.new(1, -10, 1, -30)
invGrid.BackgroundTransparency = 1
invGrid.Parent = invPanel

local UIGridLayout = Instance.new("UIGridLayout")
UIGridLayout.CellSize = UDim2.new(0, 56, 0, 80)
UIGridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
UIGridLayout.Parent = invGrid

-- Resource slot buttons (10 slots)
local resourceButtons: { Frame } = {}

local function updateResourceSlotVisual(id: number)
	local slot = resourceButtons[id]
	if not slot then return end
	local count = inventory[id] or 0
	local res = ResourceData.Resources[id]

	-- Highlight if selected
	local isSelected = false
	for _, rid in ipairs(selectedResources) do
		if rid == id then isSelected = true; break end
	end

	slot.BackgroundColor3 = isSelected
		and Color3.fromRGB(255, 220, 50)
		or (count > 0 and res.color or Color3.fromRGB(40, 40, 50))
	slot.BackgroundTransparency = count > 0 and 0.1 or 0.6

	local nameLabel = slot:FindFirstChild("Name")
	if nameLabel then nameLabel.Text = res.name end

	local countLabel = slot:FindFirstChild("Count")
	if countLabel then
		countLabel.Text = "x" .. count
		countLabel.TextColor3 = count > 0 and Color3.new(1,1,1) or Color3.fromRGB(120,120,120)
	end
end

for i = 1, 10 do
	local res = ResourceData.Resources[i]
	local slot = Instance.new("Frame")
	slot.Name = "Slot_" .. i
	slot.BackgroundColor3 = res.color
	slot.BackgroundTransparency = 0.6
	slot.BorderSizePixel = 0
	slot.Parent = invGrid

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = slot

	makeLabel(slot, "Name", res.name,
		UDim2.new(0, 2, 0, 2), UDim2.new(1, -4, 0, 28),
		10, Color3.new(1,1,1))

	makeLabel(slot, "Count", "x0",
		UDim2.new(0, 2, 0, 32), UDim2.new(1, -4, 0, 22),
		10, Color3.fromRGB(120,120,120))

	-- Tooltip hint on hover
	local hintLabel = makeLabel(slot, "Hint", res.hint,
		UDim2.new(0, 2, 0, 56), UDim2.new(1, -4, 0, 20),
		8, Color3.fromRGB(200, 200, 200))
	hintLabel.TextWrapped = true
	hintLabel.Visible = false

	-- Click to toggle resource selection
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = slot

	btn.MouseEnter:Connect(function()
		hintLabel.Visible = true
	end)
	btn.MouseLeave:Connect(function()
		hintLabel.Visible = false
	end)

	btn.MouseButton1Click:Connect(function()
		local count = inventory[i] or 0
		if count <= 0 then return end

		-- Toggle selection
		local found = false
		for idx, rid in ipairs(selectedResources) do
			if rid == i then
				table.remove(selectedResources, idx)
				found = true
				break
			end
		end
		if not found then
			if #selectedResources < 5 then
				table.insert(selectedResources, i)
			end
		end

		-- Refresh all slot visuals
		for j = 1, 10 do updateResourceSlotVisual(j) end
		UI.refreshBuildPanel()
	end)

	resourceButtons[i] = slot
end

-- ── Tower build panel (bottom center) ────────────────────────────────────────

local buildPanel = makeFrame(screenGui, "BuildPanel",
	UDim2.new(0.5, -175, 1, -220),
	UDim2.new(0, 350, 0, 210),
	Color3.fromRGB(15, 15, 25), 0.2)

makeLabel(buildPanel, "Title", "Tower Builder",
	UDim2.new(0, 5, 0, 2), UDim2.new(1, -10, 0, 24),
	12, Color3.fromRGB(200, 255, 200))

local comboNameLabel = makeLabel(buildPanel, "ComboName", "Select resources →",
	UDim2.new(0, 5, 0, 28), UDim2.new(1, -10, 0, 24),
	12, Color3.fromRGB(255, 255, 180))

local comboDescLabel = makeLabel(buildPanel, "ComboDesc", "",
	UDim2.new(0, 5, 0, 54), UDim2.new(1, -10, 0, 40),
	9, Color3.fromRGB(180, 180, 180))
comboDescLabel.TextWrapped = true
comboDescLabel.TextXAlignment = Enum.TextXAlignment.Left

local statsLabel = makeLabel(buildPanel, "Stats", "",
	UDim2.new(0, 5, 0, 96), UDim2.new(1, -10, 0, 30),
	9, Color3.fromRGB(150, 220, 255))
statsLabel.TextXAlignment = Enum.TextXAlignment.Left

local costLabel = makeLabel(buildPanel, "Cost", "",
	UDim2.new(0, 5, 0, 128), UDim2.new(1, -10, 0, 24),
	10, Color3.fromRGB(255, 220, 50))

local placeBtn = makeButton(buildPanel, "PlaceBtn", "Place Tower",
	UDim2.new(0, 5, 1, -44), UDim2.new(0.6, -10, 0, 36),
	Color3.fromRGB(50, 160, 80))

local clearBtn = makeButton(buildPanel, "ClearBtn", "Clear",
	UDim2.new(0.6, 0, 1, -44), UDim2.new(0.4, -5, 0, 36),
	Color3.fromRGB(160, 60, 60))

function UI.refreshBuildPanel()
	if #selectedResources == 0 then
		comboNameLabel.Text = "Select resources →"
		comboDescLabel.Text = ""
		statsLabel.Text = ""
		costLabel.Text = ""
		placeBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		return
	end

	local stats = TowerData.resolveStats(selectedResources)
	local cost  = 50 + #selectedResources * 30

	comboNameLabel.Text = stats.cursed and ("⚠ " .. stats.name) or stats.name
	comboNameLabel.TextColor3 = stats.cursed
		and Color3.fromRGB(255, 80, 80)
		or Color3.fromRGB(255, 255, 180)

	comboDescLabel.Text = stats.description
	statsLabel.Text = string.format(
		"DMG: %.1f  RNG: %.1f  SPD: %.1f  AoE: %.1f",
		stats.damage, stats.range, stats.fireRate, stats.aoeRadius
	)
	costLabel.Text = "Cost: 💰 " .. cost .. (money >= cost and "" or "  (need more money)")

	placeBtn.BackgroundColor3 = (money >= cost)
		and Color3.fromRGB(50, 160, 80)
		or Color3.fromRGB(80, 80, 80)
end

placeBtn.MouseButton1Click:Connect(function()
	if #selectedResources == 0 then return end
	local cost = 50 + #selectedResources * 30
	if money < cost then return end
	TowerPlacer.beginPlacement(table.clone(selectedResources))
	selectedResources = {}
	for i = 1, 10 do updateResourceSlotVisual(i) end
	UI.refreshBuildPanel()
end)

clearBtn.MouseButton1Click:Connect(function()
	selectedResources = {}
	for i = 1, 10 do updateResourceSlotVisual(i) end
	UI.refreshBuildPanel()
end)

-- ── Game over / intermission overlay ─────────────────────────────────────────

local overlay = makeFrame(screenGui, "Overlay",
	UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0),
	Color3.fromRGB(0, 0, 0), 0.5)
overlay.Visible = false
overlay.ZIndex = 10

local overlayLabel = makeLabel(overlay, "Label", "",
	UDim2.new(0.5, -300, 0.4, 0), UDim2.new(0, 600, 0, 80),
	20, Color3.new(1, 1, 1))
overlayLabel.ZIndex = 11

-- ── Remote connections ────────────────────────────────────────────────────────

function UI.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	Remotes:WaitForChild("MoneyUpdate").OnClientEvent:Connect(function(amount: number)
		money = amount
		moneyLabel.Text = "💰 " .. amount
		UI.refreshBuildPanel()
	end)

	Remotes:WaitForChild("InventoryUpdate").OnClientEvent:Connect(function(inv: { [number]: number })
		inventory = inv
		for i = 1, 10 do updateResourceSlotVisual(i) end
		UI.refreshBuildPanel()
	end)

	Remotes:WaitForChild("BaseDamaged").OnClientEvent:Connect(function(hp: number)
		baseHealth = hp
		baseLabel.Text = "🏰 " .. hp
		baseLabel.TextColor3 = hp <= 5
			and Color3.fromRGB(255, 80, 80)
			or Color3.fromRGB(100, 220, 100)
	end)

	Remotes:WaitForChild("WaveStarted").OnClientEvent:Connect(function(round: number, isBoss: boolean, count: number)
		currentRound = round
		roundLabel.Text = "Round " .. round
		local txt = isBoss
			and ("⚠ BOSS WAVE " .. round .. " — " .. count .. " enemies!")
			or ("Wave " .. round .. " — " .. count .. " enemies")
		showBanner(txt, 4)
	end)

	Remotes:WaitForChild("WaveCleared").OnClientEvent:Connect(function(round: number)
		showBanner("✓ Wave " .. round .. " cleared!", 3)
	end)

	Remotes:WaitForChild("Intermission").OnClientEvent:Connect(function(secs: number, lastRound: number)
		showBanner("Next wave in " .. secs .. "s...", secs)
	end)

	Remotes:WaitForChild("BossDrop").OnClientEvent:Connect(function(resourceId: number)
		local res = ResourceData.Resources[resourceId]
		showBanner("Boss dropped: " .. res.name .. "!", 4)
		-- Request updated inventory
		Remotes.RequestInventory:FireServer()
	end)

	Remotes:WaitForChild("EnemyKilled").OnClientEvent:Connect(function(reward: number, isBoss: boolean)
		-- Optimistic money update (server will confirm via MoneyUpdate)
		money += reward
		moneyLabel.Text = "💰 " .. money
		UI.refreshBuildPanel()
	end)

	Remotes:WaitForChild("TowerPlaced").OnClientEvent:Connect(function(gx, gz, wx, wz, resourceIds, towerId)
		TowerPlacer.markOccupied(gx, gz)
	end)

	Remotes:WaitForChild("PlaceTowerResult").OnClientEvent:Connect(function(success: boolean, msg: string)
		if not success then
			showBanner("✗ " .. (msg or "Placement failed"), 3)
		end
	end)

	Remotes:WaitForChild("GameOver").OnClientEvent:Connect(function(reason: string, round: number)
		-- Brief banner only; the LobbyShowResults screen handles the full results + OK button
		showBanner("GAME OVER — " .. reason .. " — Round " .. round, 4)
	end)

	-- Request initial inventory
	Remotes:WaitForChild("RequestInventory"):FireServer()

	print("[UI] HUD initialized")
end

return UI
