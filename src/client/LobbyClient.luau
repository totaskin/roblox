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

-- ── Module state ─────────────────────────────────────────────────────────────

local areaLabels: { TextLabel } = {}
local areaBillboards: { BillboardGui } = {}

local localPlayerAreaIndex: number? = nil
local pendingJoinHighlight: boolean = false
local lastOccupantCounts: { number } = { 0, 0, 0 }

-- Banking info cached from TurretGameOver (shown on results screen)
local cachedBankingInfo: { killEarnings: number, balance: number }? = nil

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
	panel.Size = UDim2.new(0.4, 0, 0.3, 0)
	panel.Position = UDim2.new(0.3, 0, 0.35, 0)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	panel.BorderSizePixel = 0
	panel.ZIndex = 21
	panel.Parent = backdrop

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0.3, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Game Over!"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.ZIndex = 22
	titleLabel.Parent = panel

	local roundLabel = Instance.new("TextLabel")
	roundLabel.Size = UDim2.new(1, 0, 0.2, 0)
	roundLabel.Position = UDim2.new(0, 0, 0.3, 0)
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
	bankingLabel.Size = UDim2.new(1, 0, 0.18, 0)
	bankingLabel.Position = UDim2.new(0, 0, 0.5, 0)
	bankingLabel.BackgroundTransparency = 1
	bankingLabel.Text = bankingText
	bankingLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	bankingLabel.TextScaled = true
	bankingLabel.Font = Enum.Font.Gotham
	bankingLabel.ZIndex = 22
	bankingLabel.Parent = panel

	local okButton = Instance.new("TextButton")
	okButton.Size = UDim2.new(0.4, 0, 0.2, 0)
	okButton.Position = UDim2.new(0.3, 0, 0.72, 0)
	okButton.BackgroundColor3 = Color3.fromRGB(50, 160, 50)
	okButton.BorderSizePixel = 0
	okButton.Text = "OK"
	okButton.TextColor3 = Color3.new(1, 1, 1)
	okButton.TextScaled = true
	okButton.Font = Enum.Font.GothamBold
	okButton.ZIndex = 22
	okButton.Parent = panel

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

-- ── Public API ───────────────────────────────────────────────────────────────

function LobbyClient.setBankingInfo(killEarnings: number, balance: number)
	cachedBankingInfo = { killEarnings = killEarnings, balance = balance }
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

	-- ── Wire remotes ─────────────────────────────────────────────────────────

	task.spawn(function()
		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
		if not Remotes then
			warn("[LobbyClient] Remotes folder not found")
			return
		end

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
			showResults(roundReached, areaIndex)
		end)

		print("[LobbyClient] Lobby BillboardGui overlay initialised")
	end)
end

return LobbyClient
