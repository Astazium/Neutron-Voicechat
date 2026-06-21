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
    events.on(PACK_NAME .. ":world_tick", function ()
        if not RECORDING then
            return
        end
        local samples = audio.input.fetch(ACCESS_TOKEN)
        if samples and #samples > 0 then
            NEUTRON_API.events.send(PACK_NAME, "record_data", samples)
        end
    end)

    NEUTRON_API.events.on(PACK_NAME, "record_reject", function (reason_key)
        if not RECORDING then
            return
        end
        RECORDING = false
        events.emit(PACK_NAME .. ":record_indicate", RECORDING)
        gui.alert(gui.str(utf8.tostring(reason_key), "voicechat"))
    end)
end

do
    local STREAMS = {}

    local MIN_SAFE_BUFFER     = 0.08
    local MAX_SAFE_BUFFER     = 0.25
    local INITIAL_SAFE_BUFFER = 0.13
    local JITTER_MARGIN       = 1.2
    local ANOMALY_THRESHOLD   = 0.5

    local SILENCE_TIMEOUT = 0.3

    local function get_or_create_stream(pid)
        if STREAMS[pid] then
            return STREAMS[pid]
        end
        local stream      = audio.PCMStream(44100, 1, 16)
        local stream_name = "voicechat_" .. pid
        local entry = {
            stream         = stream,
            stream_name    = stream_name,
            chunks         = {},
            speaker        = nil,
            initialized    = false,
            min_chunks     = 2,
            last_recv      = nil,
            max_delta      = 0,
            chunk_duration = 0,
        }
        STREAMS[pid] = entry
        return entry
    end

    local function ensure_speaker(entry)
        if entry.speaker and entry.speaker > 0 then
            return
        end
        entry.speaker = audio.play_stream_2d(entry.stream_name, 1.0, 1.0)
    end

    local function get_safe_buffer(entry)
        if entry.max_delta == 0 then
            return INITIAL_SAFE_BUFFER
        end
        local buf = entry.max_delta * JITTER_MARGIN
        return math.max(MIN_SAFE_BUFFER, math.min(MAX_SAFE_BUFFER, buf))
    end

    local function total_buffered_time(entry)
        local total = 0
        for _, c in ipairs(entry.chunks) do
            total = total + (#c / 2) / 44100
        end
        return total
    end

    local function reset_stream(entry)
        if entry.speaker and entry.speaker > 0 then
            audio.stop(entry.speaker)
        end
        entry.speaker     = nil
        entry.chunks      = {}
        entry.initialized = false
    end

    NEUTRON_API.events.on(PACK_NAME, "record_data", function(bytes)
        local data    = bjson.frombytes(bytes)
        local samples = data.samples
        if not samples or #samples == 0 then return end

        local entry = get_or_create_stream(data.player.pid)
        local now   = time.uptime()

        entry.chunk_duration = (#samples / 2) / 44100

        if entry.last_recv then
            local delta = now - entry.last_recv
            if delta <= ANOMALY_THRESHOLD and delta < SILENCE_TIMEOUT then
                if delta > entry.max_delta then
                    entry.max_delta = delta
                else
                    entry.max_delta = entry.max_delta * 0.99
                end
            end
        end

        entry.last_recv = now
        table.insert(entry.chunks, samples)
    end)

    local function flush_ready_chunks(entry)
        local safe_buffer = get_safe_buffer(entry)
        local total = total_buffered_time(entry)

        while #entry.chunks > 1 and total > safe_buffer do
            local c = entry.chunks[1]
            entry.stream:feed(c)
            table.remove(entry.chunks, 1)
            total = total - (#c / 2) / 44100
        end
    end

    local function check_silence(entry)
        if not entry.initialized then
            return
        end
        if not entry.last_recv then
            return
        end
        local now = time.uptime()
        if now - entry.last_recv > SILENCE_TIMEOUT then
            reset_stream(entry)
        end
    end

    events.on(PACK_NAME .. ":world_tick", function ()
        for pid, entry in pairs(STREAMS) do
            check_silence(entry)

            if #entry.chunks == 0 then
                goto continue
            end

            if not entry.initialized then
                local total = total_buffered_time(entry)
                local safe_buffer = get_safe_buffer(entry)
                if total < safe_buffer and #entry.chunks < entry.min_chunks then
                    goto continue
                end

                for _, chunk in ipairs(entry.chunks) do
                    entry.stream:feed(chunk)
                end
                entry.chunks = {}
                entry.stream:share(entry.stream_name)
                entry.speaker     = audio.play_stream_2d(entry.stream_name, 1.0, 1.0)
                entry.initialized = true
                goto continue
            end

            flush_ready_chunks(entry)
            ensure_speaker(entry)
            ::continue::
        end
    end)

    events.on(PACK_NAME .. ":hud_render", function ()
        for pid, entry in pairs(STREAMS) do
            if entry.initialized and #entry.chunks > 0 then
                flush_ready_chunks(entry)
                ensure_speaker(entry)
            end
        end
    end)
end