local ACTIVE_SPEAKERS = {}
local ACTIVE_SPEAKERS_COUNT = 0
local MAX_SPEAKERS = 0

events.on(PACK_NAME .. ":world_open",function ()
    local config_path = pack.shared_file(PACK_NAME, "config.toml")
    if not file.exists(config_path) then
        file.write(config_path, toml.tostring({MAX_SPEAKERS = 8}))
    end
    MAX_SPEAKERS = toml.parse(file.read(config_path)).MAX_SPEAKERS
end)

---@type neutron.server
local NEUTRON_API = require(string.format("%s:api/%s/api", _G["$Multiplayer"].pack_id, _G["$Multiplayer"].api_references.Neutron.latest))["server"]

events.on(PACK_NAME .. ":world_tick", function ()
    for identity, last_seen in pairs(ACTIVE_SPEAKERS) do
        if time.uptime() - last_seen > 0.5 then
            ACTIVE_SPEAKERS[identity] = nil
            ACTIVE_SPEAKERS_COUNT = ACTIVE_SPEAKERS_COUNT - 1
        end
    end
end)

NEUTRON_API.events.on(PACK_NAME, "record_data", function (sender_client, bytes)
    if ACTIVE_SPEAKERS_COUNT >= MAX_SPEAKERS and not ACTIVE_SPEAKERS[sender_client.player.identity] then
        NEUTRON_API.events.tell(PACK_NAME, "record_reject", sender_client, utf8.tobytes("you-exceed-speakers-limit"))
        return
    end
    local data = bjson.frombytes(bytes)
    if not data.samples or #data.samples == 0 then
        print("Rejected empty voice packet from \"" .. sender_client.player.username .. "\"")
        return
    end
    if not ACTIVE_SPEAKERS[sender_client.player.identity] then
        ACTIVE_SPEAKERS_COUNT = ACTIVE_SPEAKERS_COUNT + 1
    end
    ACTIVE_SPEAKERS[sender_client.player.identity] = time.uptime()
    for _, player in pairs(NEUTRON_API.sandbox.players.get_all()) do
        local client = NEUTRON_API.accounts.by_identity.get_client(player.identity)
        if client and client ~= sender_client then
            NEUTRON_API.events.tell(PACK_NAME, "record_data", client,
                bjson.tobytes({
                    player=sender_client.player,
                    input_info=data.input_info,
                    samples=data.samples
                }, true)
            )
        end
    end
end)
