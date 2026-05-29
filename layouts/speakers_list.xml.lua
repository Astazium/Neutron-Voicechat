events.on(PACK_NAME .. ":record_indicate", function (recording) document.recordIndicator.visible = recording end)

local speakers = {}
local speakers_dirty = false

function on_open()
    document.speakers:setInterval(100, function()
        local now = os.clock()
        local changed = speakers_dirty
        speakers_dirty = false

        for pid, speaker in pairs(speakers) do
            if now - speaker.last_seen > 0.5 then
                speakers[pid] = nil
                changed = true
            end
        end

        if changed then
            document.speakers:clear()
            for _, data in pairs(speakers) do
                document.speakers:add(gui.template("speaker_list", {username=data.username}))
            end
        end
    end)
end

---@type neutron.client
local NEUTRON_API = require(string.format("%s:api/%s/api", _G["$Multiplayer"].pack_id, _G["$Multiplayer"].api_references.Neutron.latest))["client"]
NEUTRON_API.events.on(PACK_NAME, "voice", function(bytes)
    local data = bjson.frombytes(bytes)
    local pid = data.player.pid
    local was_absent = speakers[pid] == nil
    speakers[pid] = {username=data.player.username, last_seen=os.clock()}
    if was_absent then
        speakers_dirty = true
    end
end)