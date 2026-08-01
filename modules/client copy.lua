local function inactive_voicechat_callback()
    gui.alert(gui.str("voicechat-unavailable"))
end

local ACCESS_TOKEN
local RECORDING = false

local function active_voicechat_callback()
    if not ACCESS_TOKEN then
        audio.input.request_open(function (access_token) ACCESS_TOKEN = access_token end)
        return
    end
    RECORDING = not RECORDING
    events.emit(PACK_ID .. ":record_indicate", RECORDING)
end

local voicechat_callback = inactive_voicechat_callback

events.on(PACK_ID .. ":hud_open", function ()
    hud.open_permanent(PACK_ID .. ":speakers_list")
    input.add_callback(PACK_ID .. ".speak", function ()
        voicechat_callback()
    end)
end)

local client
local SELF_PLAYER

local function datagram_handler(bytes)
    local data = bjson.frombytes(bytes)
    if data.event == net_events.server.handshake_response then
        voicechat_callback = active_voicechat_callback
        events.on(PACK_ID .. ":world_tick", function ()
            if not RECORDING then
                return
            end
            local samples = audio.input.fetch(ACCESS_TOKEN)
            if samples and #samples > 0 then
                client:send(bjson.tobytes({event=net_events.client.transmit_samples, samples=samples, player=SELF_PLAYER}, true))
            end
        end)
    elseif data.event == net_events.server.reject_samples then
        if not RECORDING then
            return
        end
        RECORDING = false
        events.emit(PACK_ID .. ":record_indicate", RECORDING)
        gui.alert(gui.str(data.reason_key))
    elseif data.event == net_events.server.echo_samples then
        debug.print(data)
        events.emit(PACK_ID .. ":received_samples", data.player)
    end
end

---@type neutron.client
local neutron_api = require(string.format("%s:api/%s/api", _G["$Multiplayer"].pack_id, _G["$Multiplayer"].api_references.Neutron.latest))["client"]

neutron_api.events.on(PACK_ID, "voicechat_connect", function (bytes)
    local data = bjson.frombytes(bytes)
    SELF_PLAYER = data.player
    client = network.udp_connect(data.address, data.port, datagram_handler,
    function (socket)
        socket:send(bjson.tobytes({event=net_events.client.handshake, player=SELF_PLAYER}))
    end)
end)