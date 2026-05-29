local settings_speakers = {}
local settings_dirty = false

function on_open()
    document.speakers:setInterval(200, function()
        if not settings_dirty then return end
        settings_dirty = false
        document.speakers:clear()
        for pid, data in pairs(settings_speakers) do
            document.speakers:add(gui.template("speaker_settings", {pid=pid, username=data.username}))
        end
    end)
end

---@type neutron.client
local NEUTRON_API = require(string.format("%s:api/%s/api", _G["$Multiplayer"].pack_id, _G["$Multiplayer"].api_references.Neutron.latest))["client"]
NEUTRON_API.events.on(PACK_NAME, "voice", function(bytes)
    local data = bjson.frombytes(bytes)
    local pid = data.player.pid
    if not settings_speakers[pid] then
        settings_speakers[pid] = {username=data.player.username, volume=1.0}
        settings_dirty = true
    end
end)