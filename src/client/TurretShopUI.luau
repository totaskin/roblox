-- TurretShopUI.luau
-- Lobby shop UI for browsing and buying turrets with persistent coins.
-- Displays all turret types in a scrolling list with stats, prices,
-- locked/unlocked state, and a Buy button wired to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TurretData = require(game.ReplicatedStorage.Shared.TurretData)

local TurretShopUI = {}

-- ── State ────────────────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local unlocks: { [number]: boolean } = { [1] = true } -- Scout unlocked by default
local persistentCoins: number = 0

-- UI references for dynamic updates
local coinLabel: TextLabel = nil
local statusLabels: { [number]: TextLabel } = {}
local buyButtons: { [number]: TextButton } = {}
local messageLabel: TextLabel = nil
local messageHideThread: thread? = nil

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function showMessage(text: string, color: Color3?)
	if not messageLabel then return end
	messageLabel.Text = text
	messageLabel.TextColor3 = color or Color3.fromRGB(255, 80, 80)
	messageLabel.Visible = true
	if messageHideThread then
		task.cancel(messageHideThread)
	end
	messageHideThread = task.delay(3, function()
		if messageLabel then
			messageLabel.Visible = false
		end
	end)
end

local function refreshEntry(turretId: number)
	local isUnlocked = unlocks[turretId] == true
	local statusLbl = statusLabels[turretId]
	local buyBtn = buyButtons[turretId]

	if statusLbl then
		statusLbl.Text = isUnlocked and "✓ Owned" or "Locked"
		statusLbl.TextColor3 = isUnlocked
			and Color3.fromRGB(80, 220, 80)
			or Color3.fromRGB(200, 200, 200)
	end

	if buyBtn then
		buyBtn.Visible = not isUnlocked
	end
end

local function refreshAll()
	if coinLabel then
		coinLabel.Text = "💰 " .. persistentCoins
	end
	for _, turret in TurretData.getAllTurrets() do
		refreshEntry(turret.id)
	end
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

local function buildShopUI(): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "TurretShopUI"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Main container (right side of screen)
	local container = Instance.new("Frame")
	container.Name = "ShopContainer"
	container.Size = UDim2.new(0, 300, 0, 450)
	container.Position = UDim2.new(1, -310, 0.5, -225)
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
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.Text = "Turret Shop"
	header.TextColor3 = Color3.fromRGB(255, 220, 80)
	header.TextScaled = true
	header.Font = Enum.Font.GothamBold
	header.Parent = container

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 8)
	headerCorner.Parent = header

	-- Coin display
	coinLabel = Instance.new("TextLabel")
	coinLabel.Name = "CoinBalance"
	coinLabel.Size = UDim2.new(1, 0, 0, 24)
	coinLabel.Position = UDim2.new(0, 0, 0, 36)
	coinLabel.BackgroundTransparency = 1
	coinLabel.Text = "💰 " .. persistentCoins
	coinLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
	coinLabel.TextScaled = true
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.Parent = container

	-- Message label (for errors / success)
	messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "Message"
	messageLabel.Size = UDim2.new(1, -10, 0, 20)
	messageLabel.Position = UDim2.new(0, 5, 0, 60)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = ""
	messageLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	messageLabel.TextScaled = true
	messageLabel.Font = Enum.Font.Gotham
	messageLabel.Visible = false
	messageLabel.Parent = container

	-- Scrolling frame for turret list
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "TurretList"
	scrollFrame.Size = UDim2.new(1, -10, 1, -90)
	scrollFrame.Position = UDim2.new(0, 5, 0, 82)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0) -- auto-sized by layout
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame

	-- Build an entry for each turret
	local allTurrets = TurretData.getAllTurrets()
	for idx, turret in allTurrets do
		local entry = Instance.new("Frame")
		entry.Name = "Turret_" .. turret.id
		entry.Size = UDim2.new(1, -12, 0, 110)
		entry.BackgroundColor3 = Color3.fromRGB(25, 25, 45)
		entry.BackgroundTransparency = 0.2
		entry.BorderSizePixel = 0
		entry.LayoutOrder = idx
		entry.Parent = scrollFrame

		local entryCorner = Instance.new("UICorner")
		entryCorner.CornerRadius = UDim.new(0, 6)
		entryCorner.Parent = entry

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "TurretName"
		nameLabel.Size = UDim2.new(0.6, 0, 0, 22)
		nameLabel.Position = UDim2.new(0, 6, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = turret.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = entry

		-- Status (owned / locked)
		local statusLbl = Instance.new("TextLabel")
		statusLbl.Name = "Status"
		statusLbl.Size = UDim2.new(0.35, 0, 0, 20)
		statusLbl.Position = UDim2.new(0.63, 0, 0, 4)
		statusLbl.BackgroundTransparency = 1
		statusLbl.Text = "Locked"
		statusLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
		statusLbl.TextScaled = true
		statusLbl.Font = Enum.Font.GothamBold
		statusLbl.TextXAlignment = Enum.TextXAlignment.Right
		statusLbl.Parent = entry
		statusLabels[turret.id] = statusLbl

		-- Description
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "Desc"
		descLabel.Size = UDim2.new(1, -12, 0, 18)
		descLabel.Position = UDim2.new(0, 6, 0, 26)
		descLabel.BackgroundTransparency = 1
		descLabel.Text = turret.description
		descLabel.TextColor3 = Color3.fromRGB(170, 170, 190)
		descLabel.TextScaled = true
		descLabel.Font = Enum.Font.Gotham
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextWrapped = true
		descLabel.Parent = entry

		-- Stats line
		local statsText = string.format(
			"DMG: %d  RNG: %d  SPD: %.1f",
			turret.damage, turret.range, turret.fireRate
		)
		local statsLbl = Instance.new("TextLabel")
		statsLbl.Name = "Stats"
		statsLbl.Size = UDim2.new(1, -12, 0, 16)
		statsLbl.Position = UDim2.new(0, 6, 0, 46)
		statsLbl.BackgroundTransparency = 1
		statsLbl.Text = statsText
		statsLbl.TextColor3 = Color3.fromRGB(130, 200, 255)
		statsLbl.TextScaled = true
		statsLbl.Font = Enum.Font.Gotham
		statsLbl.TextXAlignment = Enum.TextXAlignment.Left
		statsLbl.Parent = entry

		-- Prices line
		local priceText = "Shop: 💰 " .. turret.shopPrice .. "  |  Place: 💰 " .. turret.placementCost
		local priceLbl = Instance.new("TextLabel")
		priceLbl.Name = "Prices"
		priceLbl.Size = UDim2.new(1, -12, 0, 16)
		priceLbl.Position = UDim2.new(0, 6, 0, 64)
		priceLbl.BackgroundTransparency = 1
		priceLbl.Text = priceText
		priceLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
		priceLbl.TextScaled = true
		priceLbl.Font = Enum.Font.Gotham
		priceLbl.TextXAlignment = Enum.TextXAlignment.Left
		priceLbl.Parent = entry

		-- Buy button (only visible when locked)
		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyBtn"
		buyBtn.Size = UDim2.new(0, 80, 0, 24)
		buyBtn.Position = UDim2.new(1, -86, 1, -30)
		buyBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
		buyBtn.BorderSizePixel = 0
		buyBtn.Text = "Buy"
		buyBtn.TextColor3 = Color3.new(1, 1, 1)
		buyBtn.TextScaled = true
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.Parent = entry

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = buyBtn

		buyButtons[turret.id] = buyBtn
	end

	-- Set initial locked/unlocked state
	refreshAll()

	return screen
end

-- ── Public API ───────────────────────────────────────────────────────────────

local screenRef: ScreenGui = nil

function TurretShopUI.show()
	if screenRef then screenRef.Enabled = true end
end

function TurretShopUI.hide()
	if screenRef then screenRef.Enabled = false end
end

function TurretShopUI.init()
	local screen = buildShopUI()
	screen.Parent = playerGui
	screenRef = screen

	-- Wire Buy buttons to fire BuyTurret remote
	task.spawn(function()
		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		if not Remotes then
			warn("[TurretShopUI] Remotes folder not found")
			return
		end

		local BuyTurret = Remotes:WaitForChild("BuyTurret", 10)
		local BuyTurretResult = Remotes:WaitForChild("BuyTurretResult", 10)
		local ShopUpdate = Remotes:WaitForChild("ShopUpdate", 10)

		-- Wire each Buy button
		for _, turret in TurretData.getAllTurrets() do
			local btn = buyButtons[turret.id]
			if btn then
				btn.MouseButton1Click:Connect(function()
					if unlocks[turret.id] then return end
					if BuyTurret then
						BuyTurret:FireServer(turret.id)
					end
				end)
			end
		end

		-- Listen for purchase result
		if BuyTurretResult then
			BuyTurretResult.OnClientEvent:Connect(function(success: boolean, reason: string?)
				if success then
					showMessage("Purchase successful!", Color3.fromRGB(80, 220, 80))
				else
					showMessage(reason or "Not enough persistent coins", Color3.fromRGB(255, 80, 80))
				end
			end)
		end

		-- Listen for shop state updates (unlocks as array of ids + coin balance)
		if ShopUpdate then
			ShopUpdate.OnClientEvent:Connect(function(newUnlockArray: { number }, newCoins: number)
				-- Convert array of turret ids back to dictionary for fast lookup
				local dict: { [number]: boolean } = {}
				for _, id in ipairs(newUnlockArray) do
					dict[id] = true
				end
				unlocks = dict
				persistentCoins = newCoins
				refreshAll()
			end)
		end

		print("[TurretShopUI] Shop initialized and wired to remotes")
	end)
end

return TurretShopUI
