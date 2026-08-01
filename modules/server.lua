local DEFAULTS_STR = [[
# Neutron-Voicechat configuration
ip = "localhost"
max_speakers = 8
port = 22005
]]

events.on(PACK_ID .. ":world_open", function ()
    local config
    do
        local DEFAULTS = toml.parse(DEFAULTS_STR)
        local config_file = pack.shared_file(PACK_ID, "config.toml")
        if not file.exists(config_file) then
            file.write(config_file, DEFAULTS_STR)
            print("\nVOICECHAT: configuration generated. See "..string.escape(config_file).."\n")
            return
        else
            local readconfig = toml.parse(file.read(config_file))
            config = setmetatable(readconfig, {__index=DEFAULTS})
        end
    end

    local clients = {}         -- identity = { address=address, port=port }
    local active_speakers = {} -- identity = last_seen
    local active_speakers_count = 0

    network.udp_open(config.port, function (address, port, bytes, srv)
        local data = bjson.frombytes(bytes)
        local identity = data.player.identity
        local client = clients[identity]
        if data.event == net_events.client.keepalive then
            clients[identity] = {address=address, port=port}
        elseif data.event == net_events.client.handshake then
            if client and client.address == address and client.port == port  then
                return
            end
            clients[identity] = {address=address, port=port}
            srv:send(address, port, bjson.tobytes({event=net_events.server.handshake_response}))
        elseif data.event == net_events.client.transmit_samples then
            if not client or client.address ~= address or client.port ~= port then
                clients[identity] = {address=address, port=port}
            end
            if active_speakers_count >= config.max_speakers and not active_speakers[identity] then
                srv:send(address, port, bjson.tobytes({event=net_events.server.reject_samples, reason_key="voicechat-you-exceed-speakers-limit"}))
                return
            end
            local samples = data.samples
            if not samples or #samples == 0 then
                return
            end
            if not active_speakers[identity] then
                active_speakers_count = active_speakers_count + 1
            end
            active_speakers[identity] = time.uptime()

            for _, net_data in pairs(clients) do
                if net_data.address ~= address or net_data.port ~= port then
                    srv:send(net_data.address, net_data.port, bjson.tobytes({event=net_events.server.echo_samples, samples=samples, player=data.player}))
                end
            end
        end
    end)
    print(string.format("\nVOICECHAT: opened udp server at port %s\n", config.port))

    events.on(PACK_ID .. ":world_tick", function ()
        for identity, last_seen in pairs(active_speakers) do
            if time.uptime() - last_seen > 0.5 then
                active_speakers[identity] = nil
                active_speakers_count = active_speakers_count - 1
            end
        end
    end)

    events.on("server:client_disconnected", function (client)
        for identity, _ in pairs(clients) do
            if client.player.identity == identity then
                clients[identity] = nil
                break
            end
        end
    end)

    ---@type neutron.server
    local neutron_api = require(string.format("%s:api/%s/api", _G["$Multiplayer"].pack_id, _G["$Multiplayer"].api_references.Neutron.latest))["server"]

    events.on("server:on_player_ready", function (client)
        neutron_api.events.tell(PACK_ID, "voicechat_connect", client,
            bjson.tobytes({
                player={username=client.player.username, identity=client.player.identity},
                address=config.ip,
                port=config.port,
            })
        )
    end)
end)
