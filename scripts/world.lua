net_events = {
	client = {
		handshake = 1,
		keepalive = 2,
		transmit_samples = 3,
	},
	server = {
		handshake_response = 1,
		reject_samples = 2,
		echo_samples = 3,
	}
}

local m = _G["$Multiplayer"]
if m and m.side == "server" then
	require("server")
elseif m and m.side == "client" then
	require("client")
else
	events.on(PACK_ID .. ":hud_open", function () 
		gui.alert(gui.str("voicechat-only-multiplayer"))
	end)
end

function on_world_open()
	events.emit(PACK_ID .. ":world_open")
end

function on_world_tick()
    events.emit(PACK_ID .. ":world_tick")
end