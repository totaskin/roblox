-- LobbyClient.luau
-- Renders area status as BillboardGuis above each pad in the 3D world,
-- plus a rejection banner and results screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LobbyClient = {}

-- ── Constants ────────────────────────────────────────────────────────────────

local AREA_COUNT = 3

local COLOR_DEFAULT     = Color3.new(1, 1, 1)
local COLOR_HIGHLIGHTED = Color3.fromRGB(80, 255, 80)

local ResourceData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ResourceData"))

-- ── Module state ─────────────────────────────────────────────────────────────

local areaLabels: { TextLabel } = {}
local areaBillboards: { BillboardGui } = {}

local localPlayerAreaIndex: number? = nil
local pendingJoinHighlight: boolean = false
local lastOccupantCounts: { number } = { 0, 0, 0 }

-- Banking info cached from TurretGameOver (shown on results screen)
local cachedBankingInfo: { killEarnings: number, balance: number }? = nil

-- Runes earned during the current game session (reset on game start)
local runesEarnedThisGame: { [number]: number } = {}

-- Lobby rune inventory display
local lobbyRuneInventory: { [number]: number } = {}
local lobbyRuneFrame: Frame? = nil
local lobbyRuneSlots: { [number]: { frame: Frame, countLabel: TextLabel } } = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function buildLabelText(index: number, status: string, occupantCount: number, countdown: number): string
	local header = "Area " .. index

	if status == "IN_GAME" then
		return header .. "\nIn Progress"
	end

	if status == "RESULTS" then
		return header .. "\nResults"
	end

	local text
	if status == "WAITING" and countdown > 0 then
		text = header .. "\n" .. occupantCount .. "/2 players\n" .. countdown .. "s"
	else
		text = header .. "\n" .. occupantCount .. "/2 players"
	end

	if occupantCount == 2 then
		text = text .. "\nFull"
	end

	return text
end

local function refreshHighlight()
	for i = 1, AREA_COUNT do
		local label = areaLabels[i]
		if label then
			if localPlayerAreaIndex == i then
				label.TextColor3 = COLOR_HIGHLIGHTED
			else
				label.TextColor3 = COLOR_DEFAULT
			end
		end
	end
end

-- ── Results Screen ───────────────────────────────────────────────────────────

local function showResults(roundReached: number, areaIndex: number)
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screen = playerGui:FindFirstChild("ResultsScreen")
	if screen then screen:Destroy() end

	screen = Instance.new("ScreenGui")
	screen.Name = "ResultsScreen"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 100
	screen.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 20
	backdrop.Parent = screen

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0.5, 0, 0.55, 0)
	panel.Position = UDim2.new(0.25, 0, 0.22, 0)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	panel.BorderSizePixel = 0
	panel.ZIndex = 21
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0, 50)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Game Over!"
	titleLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.ZIndex = 22
	titleLabel.Parent = panel

	local roundLabel = Instance.new("TextLabel")
	roundLabel.Size = UDim2.new(1, 0, 0, 35)
	roundLabel.Position = UDim2.new(0, 0, 0, 50)
	roundLabel.BackgroundTransparency = 1
	roundLabel.Text = "You reached round " .. roundReached .. "!"
	roundLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
	roundLabel.TextScaled = true
	roundLabel.Font = Enum.Font.GothamBold
	roundLabel.ZIndex = 22
	roundLabel.Parent = panel

	-- Banking info
	local bankingText = ""
	if cachedBankingInfo then
		bankingText = "Banked: 💰 " .. cachedBankingInfo.killEarnings .. "  |  Balance: 💰 " .. cachedBankingInfo.balance
	end
	local bankingLabel = Instance.new("TextLabel")
	bankingLabel.Size = UDim2.new(1, 0, 0, 28)
	bankingLabel.Position = UDim2.new(0, 0, 0, 88)
	bankingLabel.BackgroundTransparency = 1
	bankingLabel.Text = bankingText
	bankingLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	bankingLabel.TextScaled = true
	bankingLabel.Font = Enum.Font.Gotham
	bankingLabel.ZIndex = 22
	bankingLabel.Parent = panel

	-- Runes earned section
	local runesHeader = Instance.new("TextLabel")
	runesHeader.Size = UDim2.new(1, 0, 0, 30)
	runesHeader.Position = UDim2.new(0, 0, 0, 125)
	runesHeader.BackgroundTransparency = 1
	runesHeader.Text = "✨ Runes Earned ✨"
	runesHeader.TextColor3 = Color3.fromRGB(255, 200, 100)
	runesHeader.TextScaled = true
	runesHeader.Font = Enum.Font.GothamBold
	runesHeader.ZIndex = 22
	runesHeader.Parent = panel

	-- Runes container
	local runesContainer = Instance.new("Frame")
	runesContainer.Name = "RunesContainer"
	runesContainer.Size = UDim2.new(0.9, 0, 0, 70)
	runesContainer.Position = UDim2.new(0.05, 0, 0, 158)
	runesContainer.BackgroundColor3 = Color3.fromRGB(30, 25, 50)
	runesContainer.BackgroundTransparency = 0.3
	runesContainer.BorderSizePixel = 0
	runesContainer.ZIndex = 22
	runesContainer.Parent = panel

	local runesCorner = Instance.new("UICorner")
	runesCorner.CornerRadius = UDim.new(0, 10)
	runesCorner.Parent = runesContainer

	-- Check if any runes were earned
	local totalRunesEarned = 0
	for _, count in pairs(runesEarnedThisGame) do
		totalRunesEarned = totalRunesEarned + count
	end

	if totalRunesEarned == 0 then
		local noRunesLabel = Instance.new("TextLabel")
		noRunesLabel.Size = UDim2.new(1, 0, 1, 0)
		noRunesLabel.BackgroundTransparency = 1
		noRunesLabel.Text = "No runes earned this game"
		noRunesLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		noRunesLabel.TextScaled = true
		noRunesLabel.Font = Enum.Font.Gotham
		noRunesLabel.ZIndex = 23
		noRunesLabel.Parent = runesContainer
	else
		-- Display earned runes
		local runeLayout = Instance.new("UIListLayout")
		runeLayout.FillDirection = Enum.FillDirection.Horizontal
		runeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		runeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		runeLayout.Padding = UDim.new(0, 10)
		runeLayout.Parent = runesContainer

		for runeId, count in pairs(runesEarnedThisGame) do
			if count > 0 then
				local runeData = ResourceData.Resources[runeId]
				if runeData then
					local runeSlot = Instance.new("Frame")
					runeSlot.Size = UDim2.new(0, 55, 0, 55)
					runeSlot.BackgroundColor3 = runeData.color
					runeSlot.BackgroundTransparency = 0.2
					runeSlot.BorderSizePixel = 0
					runeSlot.ZIndex = 23
					runeSlot.Parent = runesContainer

					local slotCorner = Instance.new("UICorner")
					slotCorner.CornerRadius = UDim.new(0, 8)
					slotCorner.Parent = runeSlot

					local slotStroke = Instance.new("UIStroke")
					slotStroke.Color = runeData.color
					slotStroke.Thickness = 2
					slotStroke.Parent = runeSlot

					local abbrev = Instance.new("TextLabel")
					abbrev.Size = UDim2.new(1, 0, 0.6, 0)
					abbrev.BackgroundTransparency = 1
					abbrev.Text = string.sub(runeData.name, 1, 2)
					abbrev.TextColor3 = Color3.new(1, 1, 1)
					abbrev.TextScaled = true
					abbrev.Font = Enum.Font.GothamBold
					abbrev.ZIndex = 24
					abbrev.Parent = runeSlot

					local countLabel = Instance.new("TextLabel")
					countLabel.Size = UDim2.new(1, 0, 0.4, 0)
					countLabel.Position = UDim2.new(0, 0, 0.6, 0)
					countLabel.BackgroundTransparency = 1
					countLabel.Text = "+" .. count
					countLabel.TextColor3 = Color3.fromRGB(255, 255, 150)
					countLabel.TextScaled = true
					countLabel.Font = Enum.Font.GothamBold
					countLabel.ZIndex = 24
					countLabel.Parent = runeSlot
				end
			end
		end
	end

	local okButton = Instance.new("TextButton")
	okButton.Size = UDim2.new(0.4, 0, 0, 45)
	okButton.Position = UDim2.new(0.3, 0, 1, -60)
	okButton.BackgroundColor3 = Color3.fromRGB(50, 160, 50)
	okButton.BorderSizePixel = 0
	okButton.Text = "OK"
	okButton.TextColor3 = Color3.new(1, 1, 1)
	okButton.TextScaled = true
	okButton.Font = Enum.Font.GothamBold
	okButton.ZIndex = 22
	okButton.Parent = panel

	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 8)
	okCorner.Parent = okButton

	okButton.MouseButton1Click:Connect(function()
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if Remotes then
			local LobbyReturnToLobby = Remotes:FindFirstChild("LobbyReturnToLobby")
			if LobbyReturnToLobby then
				LobbyReturnToLobby:FireServer(areaIndex)
			end
		end
		cachedBankingInfo = nil
		screen:Destroy()
	end)
end

-- ── Lobby Rune Display ────────────────────────────────────────────────────────

local RuneCombinationData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RuneCombinationData"))
local MarketplaceService = game:GetService("MarketplaceService")

-- Product IDs for individual rune purchases (matching RuneShopUI/RunePurchaseManager)
local RUNE_PRODUCT_IDS: { [number]: number } = {
	[1] = 3563208948,  -- Ember
	[2] = 3563209074,  -- Frost
	[3] = 3563209170,  -- Spark
	[4] = 3563209276,  -- Spore
	[5] = 3563209364,  -- Shadow
	[6] = 3563209463,  -- Radiance
	[7] = 3563209561,  -- Stone
	[8] = 3563209643,  -- Gale
	[9] = 3563209747,  -- Arcane
	[10] = 3563209831, -- Void
}

local function refreshLobbyRuneDisplay()
	for i = 1, 10 do
		local slot = lobbyRuneSlots[i]
		if slot then
			local count = lobbyRuneInventory[i] or 0
			slot.countLabel.Text = "x" .. count
			slot.frame.BackgroundTransparency = count > 0 and 0.1 or 0.65
		end
	end
end

local function buildLobbyRuneDisplay(parent: Instance): Frame
	-- Full panel that appears when triggered by ProximityPrompt
	local frame = Instance.new("Frame")
	frame.Name = "LobbyRuneDisplay"
	frame.Size = UDim2.new(0.5, 0, 0.7, 0)
	frame.Position = UDim2.new(0.25, 0, 0.15, 0)
	frame.BackgroundColor3 = Color3.fromRGB(12, 8, 28)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 50
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = Color3.fromRGB(30, 15, 60)
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 51
	titleBar.Parent = frame

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 12)
	titleCorner.Parent = titleBar

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -50, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "✨ Rune Collection"
	title.TextColor3 = Color3.fromRGB(200, 160, 255)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 52
	title.Parent = titleBar

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 34, 0, 34)
	closeBtn.Position = UDim2.new(1, -40, 0, 5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.ZIndex = 52
	closeBtn.Parent = titleBar

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)

	-- Buy Runes button (opens Rune Shop)
	local buyRunesBtn = Instance.new("TextButton")
	buyRunesBtn.Name = "BuyRunesBtn"
	buyRunesBtn.Size = UDim2.new(0, 100, 0, 30)
	buyRunesBtn.Position = UDim2.new(1, -150, 0, 7)
	buyRunesBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 160)
	buyRunesBtn.BorderSizePixel = 0
	buyRunesBtn.Text = "Buy Runes"
	buyRunesBtn.TextColor3 = Color3.fromRGB(255, 220, 100)
	buyRunesBtn.TextScaled = true
	buyRunesBtn.Font = Enum.Font.GothamBold
	buyRunesBtn.ZIndex = 52
	buyRunesBtn.Parent = titleBar

	local buyRunesBtnCorner = Instance.new("UICorner")
	buyRunesBtnCorner.CornerRadius = UDim.new(0, 6)
	buyRunesBtnCorner.Parent = buyRunesBtn

	local buyRunesBtnStroke = Instance.new("UIStroke")
	buyRunesBtnStroke.Color = Color3.fromRGB(255, 200, 80)
	buyRunesBtnStroke.Thickness = 1
	buyRunesBtnStroke.Parent = buyRunesBtn

	buyRunesBtn.MouseButton1Click:Connect(function()
		frame.Visible = false -- Close collection panel
		local RuneShopUI = require(script.Parent.RuneShopUI)
		RuneShopUI.show()
	end)

	-- Rune grid container
	local gridContainer = Instance.new("ScrollingFrame")
	gridContainer.Name = "RuneGrid"
	gridContainer.Size = UDim2.new(1, -20, 1, -56)
	gridContainer.Position = UDim2.new(0, 10, 0, 50)
	gridContainer.BackgroundTransparency = 1
	gridContainer.BorderSizePixel = 0
	gridContainer.ScrollBarThickness = 4
	gridContainer.ScrollBarImageColor3 = Color3.fromRGB(120, 80, 200)
	gridContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridContainer.ZIndex = 51
	gridContainer.Parent = frame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -6, 0, 90)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridContainer

	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 4)
	gridPadding.PaddingLeft = UDim.new(0, 2)
	gridPadding.Parent = gridContainer

	for i = 1, 10 do
		local res = ResourceData.Resources[i]
		local effect = RuneCombinationData.getSingleEffect(i)

		local card = Instance.new("Frame")
		card.Name = "RuneCard_" .. i
		card.BackgroundColor3 = Color3.fromRGB(20, 12, 40)
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.ZIndex = 52
		card.Parent = gridContainer

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 8)
		cardCorner.Parent = card

		-- Color accent bar on left
		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.Size = UDim2.new(0, 5, 1, -8)
		accent.Position = UDim2.new(0, 4, 0, 4)
		accent.BackgroundColor3 = res.color
		accent.BorderSizePixel = 0
		accent.ZIndex = 53
		accent.Parent = card

		local accentCorner = Instance.new("UICorner")
		accentCorner.CornerRadius = UDim.new(0, 3)
		accentCorner.Parent = accent

		-- Rune name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(0.55, 0, 0, 24)
		nameLabel.Position = UDim2.new(0, 16, 0, 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = res.name
		nameLabel.TextColor3 = res.color
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.ZIndex = 53
		nameLabel.Parent = card

		-- Count label
		local countLabel = Instance.new("TextLabel")
		countLabel.Name = "CountLabel"
		countLabel.Size = UDim2.new(0.35, 0, 0, 24)
		countLabel.Position = UDim2.new(0.62, 0, 0, 6)
		countLabel.BackgroundTransparency = 1
		countLabel.Text = "x0"
		countLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		countLabel.TextScaled = true
		countLabel.Font = Enum.Font.GothamBold
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.ZIndex = 53
		countLabel.Parent = card

		-- Effect description
		local effectParts = {}
		if effect.damage ~= 1 then
			table.insert(effectParts, string.format("DMG %.0f%%", (effect.damage - 1) * 100))
		end
		if effect.range ~= 1 then
			table.insert(effectParts, string.format("RNG %.0f%%", (effect.range - 1) * 100))
		end
		if effect.fireRate ~= 1 then
			table.insert(effectParts, string.format("SPD %.0f%%", (effect.fireRate - 1) * 100))
		end
		if effect.special then
			table.insert(effectParts, effect.special)
		end
		local effectText = #effectParts > 0 and table.concat(effectParts, "  ") or "—"

		local effectLabel = Instance.new("TextLabel")
		effectLabel.Name = "EffectLabel"
		effectLabel.Size = UDim2.new(1, -20, 0, 18)
		effectLabel.Position = UDim2.new(0, 16, 0, 32)
		effectLabel.BackgroundTransparency = 1
		effectLabel.Text = effectText
		effectLabel.TextColor3 = Color3.fromRGB(140, 180, 255)
		effectLabel.TextScaled = true
		effectLabel.Font = Enum.Font.Gotham
		effectLabel.TextXAlignment = Enum.TextXAlignment.Left
		effectLabel.ZIndex = 53
		effectLabel.Parent = card

		-- Hint
		local hintLabel = Instance.new("TextLabel")
		hintLabel.Name = "HintLabel"
		hintLabel.Size = UDim2.new(0.65, -20, 0, 22)
		hintLabel.Position = UDim2.new(0, 16, 0, 52)
		hintLabel.BackgroundTransparency = 1
		hintLabel.Text = res.hint
		hintLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
		hintLabel.TextScaled = true
		hintLabel.Font = Enum.Font.Gotham
		hintLabel.TextXAlignment = Enum.TextXAlignment.Left
		hintLabel.TextWrapped = true
		hintLabel.ZIndex = 53
		hintLabel.Parent = card

		-- Buy button for this rune
		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyBtn"
		buyBtn.Size = UDim2.new(0, 50, 0, 24)
		buyBtn.Position = UDim2.new(1, -58, 1, -30)
		buyBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
		buyBtn.BorderSizePixel = 0
		buyBtn.Text = "Buy"
		buyBtn.TextColor3 = Color3.new(1, 1, 1)
		buyBtn.TextScaled = true
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.ZIndex = 54
		buyBtn.Parent = card

		local buyBtnCorner = Instance.new("UICorner")
		buyBtnCorner.CornerRadius = UDim.new(0, 5)
		buyBtnCorner.Parent = buyBtn

		local productId = RUNE_PRODUCT_IDS[i]
		buyBtn.MouseButton1Click:Connect(function()
			if productId then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
			end
		end)

		lobbyRuneSlots[i] = { frame = card, countLabel = countLabel }
	end

	return frame
end

-- ── Public API ───────────────────────────────────────────────────────────────

function LobbyClient.setBankingInfo(killEarnings: number, balance: number)
	cachedBankingInfo = { killEarnings = killEarnings, balance = balance }
end

function LobbyClient.updateRuneInventory(inventory: { [number]: number })
	lobbyRuneInventory = inventory
	refreshLobbyRuneDisplay()
end

function LobbyClient.showRuneDisplay()
	if lobbyRuneFrame then
		lobbyRuneFrame.Visible = true
		refreshLobbyRuneDisplay()
	end
end

function LobbyClient.hideRuneDisplay()
	if lobbyRuneFrame then lobbyRuneFrame.Visible = false end
end

function LobbyClient.showFallbackResults(roundReached: number)
	-- Find which area the player is in by asking the server
	-- Use areaIndex 1 as default; the server's LobbyReturnToLobby handler
	-- will find the player in whichever area they're actually in
	showResults(roundReached, 1)
end

function LobbyClient.updateAreaDisplay(areaStates: { { index: number, status: string, occupantCount: number, countdown: number } })
	for _, snapshot in ipairs(areaStates) do
		local i = snapshot.index
		if i < 1 or i > AREA_COUNT then continue end

		if pendingJoinHighlight and localPlayerAreaIndex == nil then
			if snapshot.occupantCount > lastOccupantCounts[i] then
				localPlayerAreaIndex = i
				pendingJoinHighlight = false
			end
		end

		lastOccupantCounts[i] = snapshot.occupantCount

		local label = areaLabels[i]
		if label then
			label.Text = buildLabelText(i, snapshot.status, snapshot.occupantCount, snapshot.countdown)
		end

		if localPlayerAreaIndex == i and snapshot.status == "EMPTY" then
			localPlayerAreaIndex = nil
		end
	end

	refreshHighlight()
end

function LobbyClient.init()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	-- ── Find sign panels and wire up status labels ──────────────────────────

	for i = 1, AREA_COUNT do
		-- Wait for the server to create the sign panel parts
		local signPanel = Workspace:WaitForChild("AreaSignPanel_" .. i, 15)
		if not signPanel then
			warn("[LobbyClient] AreaSignPanel_" .. i .. " not found")
			continue
		end

		-- Find the SurfaceGui on the sign panel
		local surfaceGui = signPanel:WaitForChild("AreaSignGui_" .. i, 10)
		if not surfaceGui then
			warn("[LobbyClient] AreaSignGui_" .. i .. " not found")
			continue
		end

		local label = surfaceGui:FindFirstChild("SignLabel")
		if label then
			areaLabels[i] = label
		end
	end

	-- ── Rejection banner (ScreenGui — stays on screen) ───────────────────────

	local screen = Instance.new("ScreenGui")
	screen.Name = "LobbyNotifications"
	screen.ResetOnSpawn = false
	screen.Parent = playerGui

	local rejectionBanner = Instance.new("TextLabel")
	rejectionBanner.Name = "RejectionBanner"
	rejectionBanner.Size = UDim2.new(0.4, 0, 0.06, 0)
	rejectionBanner.Position = UDim2.new(0.3, 0, 0.45, 0)
	rejectionBanner.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
	rejectionBanner.BackgroundTransparency = 1
	rejectionBanner.TextTransparency = 1
	rejectionBanner.Text = ""
	rejectionBanner.TextColor3 = Color3.new(1, 1, 1)
	rejectionBanner.TextScaled = true
	rejectionBanner.Font = Enum.Font.GothamBold
	rejectionBanner.ZIndex = 10
	rejectionBanner.Parent = screen

	local function showRejectionBanner(message: string)
		rejectionBanner.Text = message
		rejectionBanner.BackgroundTransparency = 0.2
		rejectionBanner.TextTransparency = 0
		task.delay(3, function()
			local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
			local tween = TweenService:Create(rejectionBanner, fadeInfo, {
				BackgroundTransparency = 1,
				TextTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				rejectionBanner.Text = ""
			end)
		end)
	end

	-- ── Lobby Rune Inventory Display ─────────────────────────────────────────
	lobbyRuneFrame = buildLobbyRuneDisplay(screen)

	-- ── Rune Shop Button (Task 8.2) ──────────────────────────────────────────
	local runeShopBtn = Instance.new("TextButton")
	runeShopBtn.Name = "RuneShopBtn"
	runeShopBtn.Size = UDim2.new(0, 150, 0, 44)
	runeShopBtn.Position = UDim2.new(1, -160, 0, 108)
	runeShopBtn.BackgroundColor3 = Color3.fromRGB(50, 30, 100)
	runeShopBtn.BorderSizePixel = 0
	runeShopBtn.Text = "Runes"
	runeShopBtn.TextColor3 = Color3.fromRGB(255, 220, 80)
	runeShopBtn.TextScaled = true
	runeShopBtn.Font = Enum.Font.GothamMedium
	runeShopBtn.ZIndex = 10
	runeShopBtn.Parent = screen

	local runeShopBtnCorner = Instance.new("UICorner")
	runeShopBtnCorner.CornerRadius = UDim.new(0, 8)
	runeShopBtnCorner.Parent = runeShopBtn

	local runeShopBtnStroke = Instance.new("UIStroke")
	runeShopBtnStroke.Color = Color3.fromRGB(255, 200, 50)
	runeShopBtnStroke.Thickness = 2
	runeShopBtnStroke.Parent = runeShopBtn

	runeShopBtn.MouseButton1Click:Connect(function()
		local RuneShopUI = require(script.Parent.RuneShopUI)
		RuneShopUI.show()
	end)

	-- ── Wire remotes ─────────────────────────────────────────────────────────

	task.spawn(function()
		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		if not Remotes then
			warn("[LobbyClient] Remotes folder not found")
			return
		end
		print("[LobbyClient] Remotes folder found, connecting handlers...")

		local LobbyState = Remotes:WaitForChild("LobbyState")
		LobbyState.OnClientEvent:Connect(function(areaStates)
			LobbyClient.updateAreaDisplay(areaStates)
		end)

		local LobbyCountdown = Remotes:WaitForChild("LobbyCountdown")
		LobbyCountdown.OnClientEvent:Connect(function(areaIndex: number, seconds: number)
			if areaIndex < 1 or areaIndex > AREA_COUNT then return end
			local label = areaLabels[areaIndex]
			if not label then return end
			local currentText = label.Text
			if currentText:find("%d+s") then
				label.Text = currentText:gsub("%d+s", seconds .. "s")
			else
				local fullSuffix = currentText:find("\nFull")
				if fullSuffix then
					label.Text = currentText:sub(1, fullSuffix - 1) .. "\n" .. seconds .. "s" .. "\nFull"
				else
					label.Text = currentText .. "\n" .. seconds .. "s"
				end
			end
		end)

		local LobbyJoinResult = Remotes:WaitForChild("LobbyJoinResult")
		LobbyJoinResult.OnClientEvent:Connect(function(success: boolean, reason: string?)
			if success then
				pendingJoinHighlight = true
			else
				showRejectionBanner(reason or "Cannot join area")
			end
		end)

		local LobbyShowResults = Remotes:WaitForChild("LobbyShowResults")
		LobbyShowResults.OnClientEvent:Connect(function(roundReached: number, areaIndex: number)
			print("[LobbyClient] LobbyShowResults received, runesEarnedThisGame:", runesEarnedThisGame)
			showResults(roundReached, areaIndex)
			-- Reset runes earned for next game
			runesEarnedThisGame = {}
		end)

		-- Track runes earned during the game - connect BEFORE other handlers to ensure it's ready
		print("[LobbyClient] Looking for RuneDrop remote...")
		local RuneDrop = Remotes:WaitForChild("RuneDrop", 15)
		if RuneDrop then
			print("[LobbyClient] RuneDrop remote found! Connecting handler...")
			RuneDrop.OnClientEvent:Connect(function(runeTypeId: number)
				print("[LobbyClient] *** RuneDrop received! runeTypeId:", runeTypeId, "***")
				runesEarnedThisGame[runeTypeId] = (runesEarnedThisGame[runeTypeId] or 0) + 1
				print("[LobbyClient] Updated runesEarnedThisGame:", runesEarnedThisGame)
			end)
			print("[LobbyClient] RuneDrop handler connected for tracking")
		else
			warn("[LobbyClient] RuneDrop remote NOT found after 15 seconds!")
		end

		-- Reset runes earned when a new game starts
		local WaveStarted = Remotes:WaitForChild("WaveStarted", 10)
		if WaveStarted then
			WaveStarted.OnClientEvent:Connect(function(round: number)
				if round == 1 then
					print("[LobbyClient] Wave 1 started, resetting runesEarnedThisGame")
					runesEarnedThisGame = {}
				end
			end)
		end

		-- Wire RuneInventoryUpdate to keep lobby rune display in sync
		local RuneInventoryUpdate = Remotes:WaitForChild("RuneInventoryUpdate", 10)
		if RuneInventoryUpdate then
			RuneInventoryUpdate.OnClientEvent:Connect(function(inventory: { [number]: number })
				LobbyClient.updateRuneInventory(inventory)
			end)
		end

		-- Wire OpenRuneViewer to show the rune panel when triggered by ProximityPrompt
		local OpenRuneViewer = Remotes:WaitForChild("OpenRuneViewer", 10)
		if OpenRuneViewer then
			OpenRuneViewer.OnClientEvent:Connect(function()
				LobbyClient.showRuneDisplay()
			end)
		end

		-- Wire OpenTurretShop to show the turret shop when triggered by ProximityPrompt
		local OpenTurretShop = Remotes:WaitForChild("OpenTurretShop", 10)
		if OpenTurretShop then
			OpenTurretShop.OnClientEvent:Connect(function()
				local TurretShopUI = require(script.Parent.TurretShopUI)
				TurretShopUI.show()
			end)
		end

		print("[LobbyClient] Lobby BillboardGui overlay initialised")
	end)
end

return LobbyClient
