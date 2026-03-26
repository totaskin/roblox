-- init.client.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyClient = require(script.LobbyClient)
local TurretShopUI = require(script.TurretShopUI)
local LoadoutSelector = require(script.LoadoutSelector)
local TurretHUD = require(script.TurretHUD)
local RuneHUD = require(script.RuneHUD)
local RuneShopUI = require(script.RuneShopUI)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

LobbyClient.init()
TurretShopUI.init()
LoadoutSelector.init()
TurretHUD.init()
RuneHUD.init()
RuneShopUI.init()

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



local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)

-- Wave info label in center of bar
local waveLabel = Instance.new("TextLabel")
waveLabel.Size = UDim2.new(0.4, 0, 0, 48)
waveLabel.Position = UDim2.new(0.3, 0, 0, 0)
waveLabel.BackgroundTransparency = 1
waveLabel.Text = "Step on a pad to play!"
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
moneyLabel.Text = ""
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

	waveLabel.Text = "Step on a pad to play!"

	-- Track whether LobbyShowResults has been received after a GameOver
	local gotResults = false

	-- Ask server for current state in case we joined mid-intermission
	local StateRequest = Remotes:FindFirstChild("RequestState")
	if StateRequest then
		StateRequest:FireServer()
	end

	-- Listen for server-authoritative loadout (sent once at game start from lobby)
	local SendLoadout = Remotes:WaitForChild("SendLoadout", 10)
	if SendLoadout then
		SendLoadout.OnClientEvent:Connect(function(serverLoadout: { number })
			TurretHUD.resetForNewGame()
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
		LobbyClient.hideRuneDisplay()
	end)

	Remotes:WaitForChild("WaveCleared").OnClientEvent:Connect(function(round)
		waveLabel.Text = "✓ Round " .. round .. " cleared!"
		waveLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	end)

	Remotes:WaitForChild("Intermission").OnClientEvent:Connect(function(secs, currentRound)
		-- Live countdown showing which round is next
		local remaining = secs
		local nextRound = (currentRound or 0) + 1
		waveLabel.Text = "Round " .. nextRound .. " in " .. remaining .. "s"
		waveLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
		task.spawn(function()
			while remaining > 0 do
				task.wait(1)
				remaining -= 1
				waveLabel.Text = "Round " .. nextRound .. " in " .. remaining .. "s"
			end
		end)
	end)

	Remotes:WaitForChild("MoneyUpdate").OnClientEvent:Connect(function(amount)
		moneyLabel.Text = "💰 " .. amount
	end)

	-- Show persistent coins in the lobby (before a game starts)
	local ShopUpdate = Remotes:WaitForChild("ShopUpdate", 10)
	if ShopUpdate then
		ShopUpdate.OnClientEvent:Connect(function(_unlockArray: { number }, coins: number)
			moneyLabel.Text = "💰 " .. coins
		end)
	end

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
			TurretShopUI.hide()
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
				TurretShopUI.hide()
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

	-- Colorful rune drop notification
	print("[Client] Looking for RuneDrop remote...")
	local RuneDrop = Remotes:WaitForChild("RuneDrop", 15)
	if RuneDrop then
		print("[Client] RuneDrop remote found! Connecting notification handler...")
		RuneDrop.OnClientEvent:Connect(function(runeTypeId: number)
			print("[Client] *** RuneDrop notification received! runeTypeId:", runeTypeId, "***")
			local res = ResourceData.Resources[runeTypeId]
			if not res then 
				print("[Client] Invalid rune type:", runeTypeId)
				return 
			end

			-- Create a BIG fancy notification frame (centered on screen)
			local notification = Instance.new("Frame")
			notification.Name = "RuneDropNotification"
			notification.Size = UDim2.new(0, 450, 0, 180)
			notification.Position = UDim2.new(0.5, -225, 0.5, -200) -- Start above center
			notification.BackgroundColor3 = Color3.fromRGB(10, 5, 25)
			notification.BackgroundTransparency = 0.05
			notification.BorderSizePixel = 0
			notification.ZIndex = 100
			notification.Parent = screen

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 20)
			corner.Parent = notification

			-- Thick colorful border
			local stroke = Instance.new("UIStroke")
			stroke.Color = res.color
			stroke.Thickness = 6
			stroke.Parent = notification

			-- Glowing background effect
			local glow = Instance.new("Frame")
			glow.Name = "Glow"
			glow.Size = UDim2.new(1, 40, 1, 40)
			glow.Position = UDim2.new(0, -20, 0, -20)
			glow.BackgroundColor3 = res.color
			glow.BackgroundTransparency = 0.7
			glow.BorderSizePixel = 0
			glow.ZIndex = 99
			glow.Parent = notification

			local glowCorner = Instance.new("UICorner")
			glowCorner.CornerRadius = UDim.new(0, 30)
			glowCorner.Parent = glow

			-- "RUNE DROP!" header with sparkles - BIGGER
			local header = Instance.new("TextLabel")
			header.Name = "Header"
			header.Size = UDim2.new(1, 0, 0, 50)
			header.Position = UDim2.new(0, 0, 0, 10)
			header.BackgroundTransparency = 1
			header.Text = "✨ RUNE DROP! ✨"
			header.TextColor3 = Color3.fromRGB(255, 220, 80)
			header.TextScaled = true
			header.Font = Enum.Font.GothamBold
			header.ZIndex = 101
			header.Parent = notification

			-- Rune icon (colored circle) - BIGGER
			local runeIcon = Instance.new("Frame")
			runeIcon.Name = "RuneIcon"
			runeIcon.Size = UDim2.new(0, 70, 0, 70)
			runeIcon.Position = UDim2.new(0, 30, 0, 70)
			runeIcon.BackgroundColor3 = res.color
			runeIcon.BorderSizePixel = 0
			runeIcon.ZIndex = 101
			runeIcon.Parent = notification

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0.5, 0)
			iconCorner.Parent = runeIcon

			local iconGlow = Instance.new("UIStroke")
			iconGlow.Color = Color3.new(1, 1, 1)
			iconGlow.Thickness = 3
			iconGlow.Transparency = 0.3
			iconGlow.Parent = runeIcon

			-- Rune abbreviation inside icon
			local iconText = Instance.new("TextLabel")
			iconText.Size = UDim2.new(1, 0, 1, 0)
			iconText.BackgroundTransparency = 1
			iconText.Text = string.sub(res.name, 1, 2)
			iconText.TextColor3 = Color3.new(1, 1, 1)
			iconText.TextScaled = true
			iconText.Font = Enum.Font.GothamBold
			iconText.ZIndex = 102
			iconText.Parent = runeIcon

			-- Rune name - BIGGER
			local runeName = Instance.new("TextLabel")
			runeName.Name = "RuneName"
			runeName.Size = UDim2.new(0, 300, 0, 45)
			runeName.Position = UDim2.new(0, 115, 0, 70)
			runeName.BackgroundTransparency = 1
			runeName.Text = res.name
			runeName.TextColor3 = res.color
			runeName.TextScaled = true
			runeName.Font = Enum.Font.GothamBold
			runeName.TextXAlignment = Enum.TextXAlignment.Left
			runeName.ZIndex = 101
			runeName.Parent = notification

			-- Rune description/hint - BIGGER
			local runeHint = Instance.new("TextLabel")
			runeHint.Name = "RuneHint"
			runeHint.Size = UDim2.new(0, 300, 0, 35)
			runeHint.Position = UDim2.new(0, 115, 0, 115)
			runeHint.BackgroundTransparency = 1
			runeHint.Text = res.hint or ""
			runeHint.TextColor3 = Color3.fromRGB(200, 200, 220)
			runeHint.TextScaled = true
			runeHint.Font = Enum.Font.Gotham
			runeHint.TextXAlignment = Enum.TextXAlignment.Left
			runeHint.TextWrapped = true
			runeHint.ZIndex = 101
			runeHint.Parent = notification

			-- Animate: slide in from top to CENTER of screen
			local TweenService = game:GetService("TweenService")
			local slideIn = TweenService:Create(notification, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, -225, 0.5, -90) -- Center of screen
			})
			slideIn:Play()

			-- Pulse the glow more dramatically
			task.spawn(function()
				for _ = 1, 8 do
					local pulseOut = TweenService:Create(glow, TweenInfo.new(0.25), { BackgroundTransparency = 0.5, Size = UDim2.new(1, 60, 1, 60) })
					pulseOut:Play()
					pulseOut.Completed:Wait()
					local pulseIn = TweenService:Create(glow, TweenInfo.new(0.25), { BackgroundTransparency = 0.8, Size = UDim2.new(1, 40, 1, 40) })
					pulseIn:Play()
					pulseIn.Completed:Wait()
				end
			end)

			-- Rotate the icon more dramatically
			task.spawn(function()
				for _ = 1, 5 do
					local rotateLeft = TweenService:Create(runeIcon, TweenInfo.new(0.12), { Rotation = -15 })
					rotateLeft:Play()
					rotateLeft.Completed:Wait()
					local rotateRight = TweenService:Create(runeIcon, TweenInfo.new(0.12), { Rotation = 15 })
					rotateRight:Play()
					rotateRight.Completed:Wait()
				end
				local rotateBack = TweenService:Create(runeIcon, TweenInfo.new(0.1), { Rotation = 0 })
				rotateBack:Play()
			end)

			-- After 4 seconds, slide out and destroy
			task.delay(4, function()
				local slideOut = TweenService:Create(notification, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, -225, 0, -200)
				})
				slideOut:Play()
				slideOut.Completed:Wait()
				notification:Destroy()
			end)
		end)
		print("[Client] RuneDrop notification handler connected!")
	else
		warn("[Client] RuneDrop remote NOT found after 15 seconds!")
	end

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

-- ── Debug: Press F8 to give 100 of each rune (for testing) ───────────────────
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.F8 then
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if Remotes then
			local DebugGiveRunes = Remotes:FindFirstChild("DebugGiveRunes")
			if DebugGiveRunes then
				DebugGiveRunes:FireServer()
				print("[Client] Debug: Requested 100 of each rune")
			end
		end
	end
end)
