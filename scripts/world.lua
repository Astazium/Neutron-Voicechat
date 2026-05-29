PACK_NAME = "voicechat"

local m = _G["$Multiplayer"]
if m and m.side == "server" then
	require("server")
elseif m and m.side == "client" then
	require("client")
end

function on_world_tick()
    events.emit(PACK_NAME .. ":world_tick")
end