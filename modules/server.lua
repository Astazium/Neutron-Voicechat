---@type neutron.server
local NEUTRON_API = require(string.format("%s:api/%s/api", _G["$Multiplayer"].pack_id, _G["$Multiplayer"].api_references.Neutron.latest))["server"]

NEUTRON_API.events.on(PACK_NAME, "record", function (sender_client, bytes)
    local data = bjson.frombytes(bytes)
    if not data.samples or #data.samples == 0 then
        print("Rejected empty voice packet from \"" .. sender_client .. "\"")
        return
    end
    for _, player in pairs(NEUTRON_API.sandbox.players.get_all()) do
        local client = NEUTRON_API.accounts.by_identity.get_client(player.identity)
        if client and client ~= sender_client then
            NEUTRON_API.events.tell(PACK_NAME, "voice", client,
                bjson.tobytes({
                    player=sender_client.player,
                    input_info=data.input_info,
                    samples=data.samples
                }, true)
            )
        end
    end
end)