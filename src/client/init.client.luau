-- init.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyPath = require(game.ReplicatedStorage.Shared.EnemyPath)

local TowerPlacer = require(script.Parent.TowerPlacer)
local UI          = require(script.Parent.UI)

-- Wait for remotes to exist before initializing
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then
	warn("[Client] Remotes folder not found — is the server running?")
	return
end

-- Build grid for default map
TowerPlacer.buildGrid("Map1")

-- Listen for map changes (future: server broadcasts which map is active)
Remotes:WaitForChild("TowerPlaced").OnClientEvent:Connect(function(gx, gz)
	TowerPlacer.markOccupied(gx, gz)
end)

-- Init HUD
UI.init()

print("[Client] Tower Defense client initialized")
