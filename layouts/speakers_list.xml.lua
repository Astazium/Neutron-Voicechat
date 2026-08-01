events.on(PACK_ID .. ":record_indicate", function (recording) document.recordIndicator.visible = recording end)

local speakers = {}
local speakers_dirty = false

function on_open()
    document.speakers:setInterval(100, function()
        local now = time.uptime()
        local changed = speakers_dirty
        speakers_dirty = false

        for identity, speaker in pairs(speakers) do
            if now - speaker.last_seen > 0.5 then
                speakers[identity] = nil
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

events.on(PACK_ID .. ":received_samples", function (player)
    local was_absent = speakers[player.identity] == nil
    speakers[player.identity] = {username=player.username, last_seen=time.uptime()}
    if was_absent then
        speakers_dirty = true
    end
end)