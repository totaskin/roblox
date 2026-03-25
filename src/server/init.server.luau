-- init.server.luau
-- script = the Server folder script, children are the modules
local RunePurchaseManager = require(script.RunePurchaseManager)

local ok, err = pcall(function()
	local LobbyManager = require(script.LobbyManager)
	LobbyManager.init()
end)

if not ok then
	warn("[Server] LobbyManager failed to start:", err)
end

-- Initialize RunePurchaseManager after LobbyManager (which initializes DataManager and RuneManager)
-- This registers the ProcessReceipt callback for Developer Product purchases
local purchaseOk, purchaseErr = pcall(function()
	RunePurchaseManager.init()
end)

if not purchaseOk then
	warn("[Server] RunePurchaseManager failed to start:", purchaseErr)
end
