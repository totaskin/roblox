-- RunPropertyTests.luau
-- Entry point to execute all property-based tests.
-- In Roblox Studio: require this module from the command bar or a test script.
-- With Luau CLI: luau src/tests/RunPropertyTests.luau

local LobbyPropertyTests = require(script.Parent.LobbyPropertyTests)
local TurretPropertyTests = require(script.Parent.TurretPropertyTests)
local DataPropertyTests = require(script.Parent.DataPropertyTests)
local RunePropertyTests = require(script.Parent.RunePropertyTests)

print("╔══════════════════════════════════════════════════════════╗")
print("║  Lobby System — Property-Based Tests (100 iterations)   ║")
print("╚══════════════════════════════════════════════════════════╝")
print("")

local lobbyResults = LobbyPropertyTests.runAll()

print("")
print("╔══════════════════════════════════════════════════════════╗")
print("║  Turret System — Property-Based Tests (100 iterations)  ║")
print("╚══════════════════════════════════════════════════════════╝")
print("")

local turretResults = TurretPropertyTests.runAll()

print("")
print("╔══════════════════════════════════════════════════════════╗")
print("║  Data System — Property-Based Tests (100 iterations)    ║")
print("╚══════════════════════════════════════════════════════════╝")
print("")

local dataResults = DataPropertyTests.runAll()

print("")
print("╔══════════════════════════════════════════════════════════╗")
print("║  Rune System — Property-Based Tests (100 iterations)    ║")
print("╚══════════════════════════════════════════════════════════╝")
print("")

local runeResults = RunePropertyTests.runAll()

-- Return combined results table for programmatic access
return {
	lobby = lobbyResults,
	turret = turretResults,
	data = dataResults,
	rune = runeResults,
}
