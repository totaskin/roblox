-- RuneShopUI.luau
-- Client-side Rune Shop UI for purchasing runes with Robux.
-- Displays single-rune products and bundle products with buy buttons.
-- Follows the same module pattern as TurretShopUI.luau and RuneHUD.luau.
-- Task 6, Task 7

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)

local RuneShopUI = {}

-- ── Constants ────────────────────────────────────────────────────────────────

-- Product IDs matching RunePurchaseManager (real Developer Product IDs)
local SINGLE_RUNE_PRODUCTS: { { productId: number, runeTypeId: number } } = {
	{ productId = 3563208948, runeTypeId = 1 },  -- Ember Rune
	{ productId = 3563209074, runeTypeId = 2 },  -- Frost Rune
	{ productId = 3563209170, runeTypeId = 3 },  -- Spark Rune
	{ productId = 3563209276, runeTypeId = 4 },  -- Spore Rune
	{ productId = 3563209364, runeTypeId = 5 },  -- Shadow Rune
	{ productId = 3563209463, runeTypeId = 6 },  -- Radiance Rune
	{ productId = 3563209561, runeTypeId = 7 },  -- Stone Rune
	{ productId = 3563209643, runeTypeId = 8 },  -- Gale Rune
	{ productId = 3563209747, runeTypeId = 9 },  -- Arcane Rune
	{ productId = 3563209831, runeTypeId = 10 }, -- Void Rune
}

-- Bundle product
local BUNDLE_PRODUCT = {
	productId = 3563210415,
	quantity = 5,
}

-- ── State ────────────────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local runeInventory: { [number]: number } = {} -- rune type id -> count
local purchaseInProgress: boolean = false      -- disable buttons while prompt is open

-- UI references
local screenGui: ScreenGui = nil
local productButtons: { [number]: TextButton } = {}  -- productId -> button
local inventoryLabels: { [number]: TextLabel } = {}  -- runeTypeId -> inventory count label
local bundleButton: TextButton = nil
local notificationLabel: TextLabel = nil            -- notification display
local notificationDismissThread: thread? = nil      -- auto-dismiss coroutine

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function setButtonsEnabled(enabled: boolean)
	for _, btn in pairs(productButtons) do
		btn.AutoButtonColor = enabled
		if enabled then
			btn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
		else
			btn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		end
	end
	if bundleButton then
		bundleButton.AutoButtonColor = enabled
		if enabled then
			bundleButton.BackgroundColor3 = Color3.fromRGB(80, 50, 160)
		else
			bundleButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		end
	end
end

local function refreshInventoryDisplay()
	for runeTypeId = 1, 10 do
		local label = inventoryLabels[runeTypeId]
		if label then
			local count = runeInventory[runeTypeId] or 0
			label.Text = "Owned: " .. count
		end
	end
end

-- ── Notification System (Task 7.1, 7.2) ──────────────────────────────────────

local function hideNotification()
	if notificationLabel then
		notificationLabel.Visible = false
	end
	if notificationDismissThread then
		task.cancel(notificationDismissThread)
		notificationDismissThread = nil
	end
end

local function showNotification(message: string, isError: boolean?)
	if not notificationLabel then return end

	-- Cancel any existing auto-dismiss
	if notificationDismissThread then
		task.cancel(notificationDismissThread)
		notificationDismissThread = nil
	end

	-- Set notification style based on type
	if isError then
		notificationLabel.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
		notificationLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
	else
		notificationLabel.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
		notificationLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
	end

	notificationLabel.Text = message
	notificationLabel.Visible = true

	-- Task 7.2: Auto-dismiss after 3 seconds
	notificationDismissThread = task.delay(3, function()
		hideNotification()
	end)
end

-- Format runes granted into a readable message (Task 7.1)
local function formatPurchaseSuccessMessage(runesGranted: { [number]: number }): string
	local parts = {}
	local totalRunes = 0

	for runeTypeId, quantity in pairs(runesGranted) do
		totalRunes = totalRunes + quantity
		local res = ResourceData.Resources[runeTypeId]
		if res then
			if quantity == 1 then
				table.insert(parts, "+" .. quantity .. " " .. res.name .. " Rune")
			else
				table.insert(parts, "+" .. quantity .. " " .. res.name .. " Runes")
			end
		end
	end

	-- If multiple rune types, show summary
	if #parts > 2 then
		return "+" .. totalRunes .. " Random Runes"
	end

	return table.concat(parts, ", ")
end

-- ── Build Shop UI (Tasks 6.2, 6.3, 6.4) ──────────────────────────────────────

local function buildShopUI(): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "RuneShopUI"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Main container (centered)
	local container = Instance.new("Frame")
	container.Name = "ShopContainer"
	container.Size = UDim2.new(0, 340, 0, 520)
	container.Position = UDim2.new(0.5, -170, 0.5, -260)
	container.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
	container.BackgroundTransparency = 0.05
	container.BorderSizePixel = 0
	container.Parent = screen

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 10)
	containerCorner.Parent = container

	-- Header
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 40)
	header.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.Text = "🔮 Rune Shop"
	header.TextColor3 = Color3.fromRGB(255, 220, 80)
	header.TextScaled = true
	header.Font = Enum.Font.GothamBold
	header.Parent = container

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = header

	-- Close button (Task 6.2)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -38, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = container

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		RuneShopUI.hide()
	end)

	-- Notification label (Task 7.1, 7.2)
	local notification = Instance.new("TextButton")
	notification.Name = "Notification"
	notification.Size = UDim2.new(1, -16, 0, 36)
	notification.Position = UDim2.new(0, 8, 0, 44)
	notification.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
	notification.BackgroundTransparency = 0.1
	notification.BorderSizePixel = 0
	notification.Text = ""
	notification.TextColor3 = Color3.fromRGB(200, 255, 200)
	notification.TextScaled = true
	notification.Font = Enum.Font.GothamBold
	notification.Visible = false
	notification.ZIndex = 10
	notification.Parent = container

	local notificationCorner = Instance.new("UICorner")
	notificationCorner.CornerRadius = UDim.new(0, 6)
	notificationCorner.Parent = notification

	-- Task 7.2: Dismiss notification on click
	notification.MouseButton1Click:Connect(function()
		hideNotification()
	end)

	notificationLabel = notification

	-- Scrolling frame for product list (Task 6.2)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ProductList"
	scrollFrame.Size = UDim2.new(1, -16, 1, -96)  -- Adjusted for notification area
	scrollFrame.Position = UDim2.new(0, 8, 0, 88) -- Below notification area
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame

	-- Build single-rune product entries (Task 6.3)
	for idx, productInfo in ipairs(SINGLE_RUNE_PRODUCTS) do
		local runeTypeId = productInfo.runeTypeId
		local productId = productInfo.productId
		local res = ResourceData.Resources[runeTypeId]

		local entry = Instance.new("Frame")
		entry.Name = "Rune_" .. runeTypeId
		entry.Size = UDim2.new(1, -12, 0, 50)
		entry.BackgroundColor3 = Color3.fromRGB(25, 25, 45)
		entry.BackgroundTransparency = 0.2
		entry.BorderSizePixel = 0
		entry.LayoutOrder = idx
		entry.Parent = scrollFrame

		local entryCorner = Instance.new("UICorner")
		entryCorner.CornerRadius = UDim.new(0, 6)
		entryCorner.Parent = entry

		-- Color indicator
		local colorIndicator = Instance.new("Frame")
		colorIndicator.Name = "ColorIndicator"
		colorIndicator.Size = UDim2.new(0, 8, 1, -8)
		colorIndicator.Position = UDim2.new(0, 4, 0, 4)
		colorIndicator.BackgroundColor3 = res.color
		colorIndicator.BorderSizePixel = 0
		colorIndicator.Parent = entry

		local colorCorner = Instance.new("UICorner")
		colorCorner.CornerRadius = UDim.new(0, 4)
		colorCorner.Parent = colorIndicator

		-- Rune name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "RuneName"
		nameLabel.Size = UDim2.new(0, 100, 0, 24)
		nameLabel.Position = UDim2.new(0, 20, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = res.name .. " Rune"
		nameLabel.TextColor3 = res.color
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = entry

		-- Inventory count
		local invLabel = Instance.new("TextLabel")
		invLabel.Name = "InventoryCount"
		invLabel.Size = UDim2.new(0, 80, 0, 18)
		invLabel.Position = UDim2.new(0, 20, 0, 28)
		invLabel.BackgroundTransparency = 1
		invLabel.Text = "Owned: 0"
		invLabel.TextColor3 = Color3.fromRGB(170, 170, 190)
		invLabel.TextScaled = true
		invLabel.Font = Enum.Font.Gotham
		invLabel.TextXAlignment = Enum.TextXAlignment.Left
		invLabel.Parent = entry
		inventoryLabels[runeTypeId] = invLabel

		-- Buy button (Task 6.5)
		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyBtn"
		buyBtn.Size = UDim2.new(0, 70, 0, 32)
		buyBtn.Position = UDim2.new(1, -78, 0.5, -16)
		buyBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
		buyBtn.BorderSizePixel = 0
		buyBtn.Text = "Buy"
		buyBtn.TextColor3 = Color3.new(1, 1, 1)
		buyBtn.TextScaled = true
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.Parent = entry

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = buyBtn

		productButtons[productId] = buyBtn

		-- Wire buy button click (Task 6.5)
		buyBtn.MouseButton1Click:Connect(function()
			if purchaseInProgress then return end
			purchaseInProgress = true
			setButtonsEnabled(false)
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
	end

	-- Separator
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(1, -20, 0, 2)
	separator.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
	separator.BorderSizePixel = 0
	separator.LayoutOrder = 11
	separator.Parent = scrollFrame

	-- Bundle product entry (Task 6.4)
	local bundleEntry = Instance.new("Frame")
	bundleEntry.Name = "Bundle"
	bundleEntry.Size = UDim2.new(1, -12, 0, 60)
	bundleEntry.BackgroundColor3 = Color3.fromRGB(35, 25, 55)
	bundleEntry.BackgroundTransparency = 0.1
	bundleEntry.BorderSizePixel = 0
	bundleEntry.LayoutOrder = 12
	bundleEntry.Parent = scrollFrame

	local bundleCorner = Instance.new("UICorner")
	bundleCorner.CornerRadius = UDim.new(0, 6)
	bundleCorner.Parent = bundleEntry

	-- Bundle icon/indicator
	local bundleIcon = Instance.new("TextLabel")
	bundleIcon.Name = "BundleIcon"
	bundleIcon.Size = UDim2.new(0, 40, 0, 40)
	bundleIcon.Position = UDim2.new(0, 8, 0.5, -20)
	bundleIcon.BackgroundColor3 = Color3.fromRGB(120, 80, 200)
	bundleIcon.BackgroundTransparency = 0.3
	bundleIcon.BorderSizePixel = 0
	bundleIcon.Text = "📦"
	bundleIcon.TextScaled = true
	bundleIcon.Font = Enum.Font.GothamBold
	bundleIcon.Parent = bundleEntry

	local bundleIconCorner = Instance.new("UICorner")
	bundleIconCorner.CornerRadius = UDim.new(0, 8)
	bundleIconCorner.Parent = bundleIcon

	-- Bundle name
	local bundleNameLabel = Instance.new("TextLabel")
	bundleNameLabel.Name = "BundleName"
	bundleNameLabel.Size = UDim2.new(0, 140, 0, 26)
	bundleNameLabel.Position = UDim2.new(0, 56, 0, 6)
	bundleNameLabel.BackgroundTransparency = 1
	bundleNameLabel.Text = BUNDLE_PRODUCT.quantity .. " Random Runes"
	bundleNameLabel.TextColor3 = Color3.fromRGB(200, 160, 255)
	bundleNameLabel.TextScaled = true
	bundleNameLabel.Font = Enum.Font.GothamBold
	bundleNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	bundleNameLabel.Parent = bundleEntry

	-- Bundle description
	local bundleDescLabel = Instance.new("TextLabel")
	bundleDescLabel.Name = "BundleDesc"
	bundleDescLabel.Size = UDim2.new(0, 140, 0, 18)
	bundleDescLabel.Position = UDim2.new(0, 56, 0, 32)
	bundleDescLabel.BackgroundTransparency = 1
	bundleDescLabel.Text = "Get random runes!"
	bundleDescLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
	bundleDescLabel.TextScaled = true
	bundleDescLabel.Font = Enum.Font.Gotham
	bundleDescLabel.TextXAlignment = Enum.TextXAlignment.Left
	bundleDescLabel.Parent = bundleEntry

	-- Bundle buy button
	local bundleBuyBtn = Instance.new("TextButton")
	bundleBuyBtn.Name = "BuyBtn"
	bundleBuyBtn.Size = UDim2.new(0, 70, 0, 36)
	bundleBuyBtn.Position = UDim2.new(1, -78, 0.5, -18)
	bundleBuyBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 160)
	bundleBuyBtn.BorderSizePixel = 0
	bundleBuyBtn.Text = "Buy"
	bundleBuyBtn.TextColor3 = Color3.new(1, 1, 1)
	bundleBuyBtn.TextScaled = true
	bundleBuyBtn.Font = Enum.Font.GothamBold
	bundleBuyBtn.Parent = bundleEntry

	local bundleBtnCorner = Instance.new("UICorner")
	bundleBtnCorner.CornerRadius = UDim.new(0, 6)
	bundleBtnCorner.Parent = bundleBuyBtn

	bundleButton = bundleBuyBtn
	productButtons[BUNDLE_PRODUCT.productId] = bundleBuyBtn

	-- Wire bundle buy button (Task 6.5)
	bundleBuyBtn.MouseButton1Click:Connect(function()
		if purchaseInProgress then return end
		purchaseInProgress = true
		setButtonsEnabled(false)
		MarketplaceService:PromptProductPurchase(player, BUNDLE_PRODUCT.productId)
	end)

	return screen
end

-- ── Public API (Task 6.1) ────────────────────────────────────────────────────

function RuneShopUI.init()
	-- Initialize inventory to zeros
	for i = 1, 10 do
		runeInventory[i] = 0
	end

	screenGui = buildShopUI()
	screenGui.Enabled = false -- hidden by default
	screenGui.Parent = playerGui

	-- Task 6.6: Wire PromptProductPurchaseFinished to re-enable buttons
	-- Task 7.4: Handle purchase failures with error message
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, isPurchased)
		if userId == player.UserId then
			purchaseInProgress = false
			setButtonsEnabled(true)

			-- Task 7.4: If purchase was attempted but failed (not cancelled), show error
			-- Note: isPurchased is false for both cancellation and failure
			-- We can't distinguish between them, so we don't show error on cancel
			-- The error message is shown when server-side processing fails
		end
	end)

	-- Task 7.1, 7.2: Wire PurchaseSuccess remote for success notifications
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if remotes then
		local purchaseSuccess = remotes:FindFirstChild("PurchaseSuccess")
		if purchaseSuccess then
			purchaseSuccess.OnClientEvent:Connect(function(runesGranted: { [number]: number })
				local message = formatPurchaseSuccessMessage(runesGranted)
				showNotification(message, false)
			end)
		end

		-- Task 7.3: Wire RuneInventoryUpdate remote to update displayed inventory
		local runeInventoryUpdate = remotes:FindFirstChild("RuneInventoryUpdate")
		if runeInventoryUpdate then
			runeInventoryUpdate.OnClientEvent:Connect(function(inventory: { [number]: number })
				RuneShopUI.setInventory(inventory)
			end)
		end
	end

	print("[RuneShopUI] Initialized")
end

function RuneShopUI.show()
	if screenGui then
		screenGui.Enabled = true
	end
	refreshInventoryDisplay()
end

function RuneShopUI.hide()
	if screenGui then
		screenGui.Enabled = false
	end
end

function RuneShopUI.setInventory(inventory: { [number]: number })
	runeInventory = inventory
	refreshInventoryDisplay()
end

-- Task 7.4: Show error message for purchase failures
function RuneShopUI.showError(message: string?)
	local errorMessage = message or "Unable to complete purchase. Please try again."
	showNotification(errorMessage, true)
end

-- Task 7.1: Show success notification (can be called externally if needed)
function RuneShopUI.showSuccess(runesGranted: { [number]: number })
	local message = formatPurchaseSuccessMessage(runesGranted)
	showNotification(message, false)
end

return RuneShopUI
