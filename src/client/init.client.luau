-- init.client.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyClient = require(script.LobbyClient)
local TurretShopUI = require(script.TurretShopUI)
local LoadoutSelector = require(script.LoadoutSelector)
local TurretHUD = require(script.TurretHUD)
local RuneHUD = require(script.RuneHUD)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

LobbyClient.init()
TurretShopUI.init()
LoadoutSelector.init()
TurretHUD.init()
RuneHUD.init()

-- ── Simple test UI (no server dependency) ────────────────────────────────────
local screen = Instance.new("ScreenGui")
screen.Name = "TestHUD"
screen.ResetOnSpawn = false
screen.Parent = playerGui

-- Background bar
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 48)
bar.Position = UDim2.new(0, 0, 0, 0)
bar.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
bar.BackgroundTransparency = 0.1
bar.BorderSizePixel = 0
bar.Parent = screen



-- Resource strip at bottom
local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)

local strip = Instance.new("Frame")
strip.Size = UDim2.new(1, 0, 0, 70)
strip.Position = UDim2.new(0, 0, 1, -70)
strip.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
strip.BackgroundTransparency = 0.2
strip.BorderSizePixel = 0
strip.Parent = screen

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 4)
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Parent = strip

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.Parent = strip

for i = 1, 10 do
	local res = ResourceData.Resources[i]

	local slot = Instance.new("Frame")
	slot.Size = UDim2.new(0, 80, 0, 60)
	slot.BackgroundColor3 = res.color
	slot.BackgroundTransparency = 0.2
	slot.BorderSizePixel = 0
	slot.Parent = strip

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = slot

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.5, 0)
	name.BackgroundTransparency = 1
	name.Text = res.name
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextScaled = true
	name.Font = Enum.Font.GothamBold
	name.Parent = slot

	local count = Instance.new("TextLabel")
	count.Size = UDim2.new(1, 0, 0.5, 0)
	count.Position = UDim2.new(0, 0, 0.5, 0)
	count.BackgroundTransparency = 1
	count.Text = "x0"
	count.TextColor3 = Color3.fromRGB(200, 200, 200)
	count.TextScaled = true
	count.Font = Enum.Font.Gotham
	count.Parent = slot
end

-- Wave info label in center of bar
local waveLabel = Instance.new("TextLabel")
waveLabel.Size = UDim2.new(0.4, 0, 0, 48)
waveLabel.Position = UDim2.new(0.3, 0, 0, 0)
waveLabel.BackgroundTransparency = 1
waveLabel.Text = "Waiting for server..."
waveLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
waveLabel.TextScaled = true
waveLabel.Font = Enum.Font.GothamBold
waveLabel.ZIndex = 2
waveLabel.Parent = screen

-- Money label (left side of bar)
local moneyLabel = Instance.new("TextLabel")
moneyLabel.Size = UDim2.new(0, 140, 0, 48)
moneyLabel.Position = UDim2.new(0, 8, 0, 0)
moneyLabel.BackgroundTransparency = 1
moneyLabel.Text = "💰 150"
moneyLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
moneyLabel.TextScaled = true
moneyLabel.Font = Enum.Font.GothamBold
moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyLabel.Parent = screen

-- Base health label (right side of bar)
local baseLabel = Instance.new("TextLabel")
baseLabel.Size = UDim2.new(0, 140, 0, 48)
baseLabel.Position = UDim2.new(1, -148, 0, 0)
baseLabel.BackgroundTransparency = 1
baseLabel.Text = "🏰 20"
baseLabel.TextColor3 = Color3.fromRGB(100, 220, 100)
baseLabel.TextScaled = true
baseLabel.Font = Enum.Font.GothamBold
baseLabel.TextXAlignment = Enum.TextXAlignment.Right
moneyLabel.ZIndex = 2
baseLabel.ZIndex = 2
baseLabel.Parent = screen

-- ── Hook up remotes once server is ready ─────────────────────────────────────
task.spawn(function()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not Remotes then
		waveLabel.Text = "⚠ No Remotes folder"
		warn("[Client] Remotes not found")
		return
	end

	waveLabel.Text = "Round 0 — Waiting..."

	-- Track whether LobbyShowResults has been received after a GameOver
	local gotResults = false

	-- Ask server for current state in case we joined mid-intermission
	local StateRequest = Remotes:FindFirstChild("RequestState")
	if StateRequest then
		StateRequest:FireServer()
	end

	-- Listen for server-authoritative loadout
	local SendLoadout = Remotes:WaitForChild("SendLoadout", 10)
	if SendLoadout then
		SendLoadout.OnClientEvent:Connect(function(serverLoadout: { number })
			TurretHUD.setLoadout(serverLoadout)
		end)
	end

	Remotes:WaitForChild("WaveStarted").OnClientEvent:Connect(function(round, isBoss)
		waveLabel.Text = isBoss and ("⚠ BOSS — Round " .. round) or ("Round " .. round)
		waveLabel.TextColor3 = isBoss
			and Color3.fromRGB(255, 80, 80)
			or Color3.fromRGB(255, 220, 80)

		-- Reset health label color in case it was red from previous game
		baseLabel.TextColor3 = Color3.fromRGB(100, 220, 100)

		-- Show the in-game HUD
		screen.Enabled = true

		-- Hide lobby UIs, show in-game turret HUD
		TurretShopUI.hide()
		LoadoutSelector.hide()
		TurretHUD.show()
		RuneHUD.show()
	end)

	Remotes:WaitForChild("WaveCleared").OnClientEvent:Connect(function(round)
		waveLabel.Text = "✓ Round " .. round .. " cleared!"
		waveLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	end)

	Remotes:WaitForChild("Intermission").OnClientEvent:Connect(function(secs)
		-- Live countdown
		local remaining = secs
		waveLabel.Text = "Next wave in " .. remaining .. "s"
		waveLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
		task.spawn(function()
			while remaining > 0 do
				task.wait(1)
				remaining -= 1
				waveLabel.Text = "Next wave in " .. remaining .. "s"
			end
		end)
	end)

	Remotes:WaitForChild("MoneyUpdate").OnClientEvent:Connect(function(amount)
		moneyLabel.Text = "💰 " .. amount
	end)

	Remotes:WaitForChild("BaseDamaged").OnClientEvent:Connect(function(hp)
		baseLabel.Text = "🏰 " .. hp
		baseLabel.TextColor3 = hp <= 5
			and Color3.fromRGB(255, 80, 80)
			or Color3.fromRGB(100, 220, 100)
	end)

	-- When game ends, restore lobby UIs and hide turret HUD
	local LobbyShowResults = Remotes:WaitForChild("LobbyShowResults", 10)
	if LobbyShowResults then
		LobbyShowResults.OnClientEvent:Connect(function()
			gotResults = true
			TurretHUD.hide()
			RuneHUD.hide()
			TurretShopUI.show()
			LoadoutSelector.show()
			-- Hide the in-game HUD so it doesn't block the results screen
			screen.Enabled = false
		end)
	end

	-- Immediately react to GameOver: update wave label, hide turret HUD
	Remotes:WaitForChild("GameOver").OnClientEvent:Connect(function(_reason: string, round: number)
		waveLabel.Text = "GAME OVER — Round " .. round
		waveLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		TurretHUD.hide()
		RuneHUD.hide()
		gotResults = false

		-- Fallback: if LobbyShowResults doesn't arrive within 3 seconds,
		-- create the results screen directly
		task.delay(3, function()
			if not gotResults then
				warn("[Client] LobbyShowResults not received — showing fallback results screen")
				TurretShopUI.show()
				LoadoutSelector.show()
				screen.Enabled = false
				LobbyClient.showFallbackResults(round)
			end
		end)
	end)

	-- Cache banking info for the results screen
	local TurretGameOver = Remotes:WaitForChild("TurretGameOver", 10)
	if TurretGameOver then
		TurretGameOver.OnClientEvent:Connect(function(killEarningsBanked: number, newPersistentBalance: number)
			LobbyClient.setBankingInfo(killEarningsBanked, newPersistentBalance)
		end)
	end

	Remotes:WaitForChild("BossDrop").OnClientEvent:Connect(function(resourceId)
		local res = ResourceData.Resources[resourceId]
		waveLabel.Text = "Boss dropped: " .. res.name .. "!"
		waveLabel.TextColor3 = res.color
	end)

	Remotes:WaitForChild("EnemyKilled").OnClientEvent:Connect(function(reward)
		local current = tonumber(moneyLabel.Text:match("%d+")) or 0
		moneyLabel.Text = "💰 " .. (current + reward)
	end)

	print("[Client] HUD connected to server remotes")
end)

print("[Client] Test HUD loaded")

-- ── Speed toggle button ──────────────────────────────────────────────────────
local currentSpeed = 1
local speedBtn = Instance.new("TextButton")
speedBtn.Name = "SpeedBtn"
speedBtn.Size = UDim2.new(0, 50, 0, 30)
speedBtn.Position = UDim2.new(0.5, 100, 0, 56)
speedBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
speedBtn.BackgroundTransparency = 0.2
speedBtn.BorderSizePixel = 0
speedBtn.Text = "1x"
speedBtn.TextColor3 = Color3.fromRGB(255, 220, 80)
speedBtn.TextScaled = true
speedBtn.Font = Enum.Font.GothamBold
speedBtn.Parent = screen

local speedCorner = Instance.new("UICorner")
speedCorner.CornerRadius = UDim.new(0, 6)
speedCorner.Parent = speedBtn

speedBtn.MouseButton1Click:Connect(function()
	if currentSpeed == 1 then
		currentSpeed = 2
	elseif currentSpeed == 2 then
		currentSpeed = 3
	else
		currentSpeed = 1
	end
	speedBtn.Text = currentSpeed .. "x"
	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if Remotes then
		local SetGameSpeed = Remotes:FindFirstChild("SetGameSpeed")
		if SetGameSpeed then
			SetGameSpeed:FireServer(currentSpeed)
		end
	end
end)
