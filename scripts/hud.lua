function on_hud_open()
    events.emit(PACK_NAME .. ":hud_open")
end

function on_hud_render()
    events.emit(PACK_NAME .. ":hud_render")
end