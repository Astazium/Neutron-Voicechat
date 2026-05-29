---@type neutron.client
local NEUTRON_API = require(string.format("%s:api/%s/api", _G["$Multiplayer"].pack_id, _G["$Multiplayer"].api_references.Neutron.latest))["client"]

do
    local ACCESS_TOKEN
    local RECORDING = false
    events.on(PACK_NAME .. ":hud_open", function ()
        hud.open_permanent(PACK_NAME .. ":speakers_list")
        input.add_callback(PACK_NAME .. ".speak", function ()
            if not ACCESS_TOKEN then
                audio.input.request_open(function (access_token) ACCESS_TOKEN = access_token end)
                return
            end
            RECORDING = not RECORDING
            events.emit(PACK_NAME .. ":record_indicate", RECORDING)
        end)
    end)
    local INPUT_INFO = audio.input.get_input_info()
    local CHUNK_SIZE = math.floor(INPUT_INFO.sample_rate / 20) * 2
    events.on(PACK_NAME .. ":world_tick", function ()
        if not RECORDING then
            return
        end
        local samples = audio.input.fetch(ACCESS_TOKEN, CHUNK_SIZE)
        if samples and #samples > 0 then
            NEUTRON_API.events.send(PACK_NAME, "record", bjson.tobytes({input_info=INPUT_INFO, samples=samples}, true))
        end
    end)
end

do
    local streams = {}  -- streams[pid] = {stream, speaker, initialized}

    local function get_or_create_stream(pid, input_info)
        if streams[pid] then
            return streams[pid]
        end
        local stream = audio.PCMStream(
            input_info.sample_rate,
            input_info.channels,
            input_info.bits_per_sample
        )
        local stream_name = "voicechat_" .. pid
        local entry = {stream=stream, stream_name=stream_name, speaker=nil, initialized=false}
        streams[pid] = entry
        return entry
    end

    local function ensure_speaker(entry)
        if entry.speaker and entry.speaker > 0 then
            return
        end
        entry.speaker = audio.play_stream_2d(entry.stream_name, 1.0, 1.0)
    end

    NEUTRON_API.events.on(PACK_NAME, "voice", function(bytes)
        local data = bjson.frombytes(bytes)
        local samples = data.samples
        if not samples or #samples == 0 then
            return
        end
        local entry = get_or_create_stream(data.player.pid, data.input_info)

        if not entry.initialized then
            entry.stream:feed(samples)
            entry.stream:share(entry.stream_name)
            entry.speaker = audio.play_stream_2d(entry.stream_name, 1.0, 1.0)
            entry.initialized = true
            return
        end

        entry.stream:feed(samples)
        ensure_speaker(entry)
    end)
end