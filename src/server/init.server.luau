-- init.server.luau
-- script = the Server folder script, children are the modules
local ok, err = pcall(function()
	local LobbyManager = require(script.LobbyManager)
	LobbyManager.init()
end)

if not ok then
	warn("[Server] LobbyManager failed to start:", err)
end
