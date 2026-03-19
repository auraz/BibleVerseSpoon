--- Widget rendering functions.
-- All rendering called by states.lua. No external caller should call these directly.
local log = hs.logger.new("bibleverse", "debug")

local M = {}

local function get_screen_config(config, screen_name)
    local pos = config.position[screen_name] or config.position.default
    local width = (config.size and config.size[screen_name] and config.size[screen_name].width) or config.width
    local height = (config.size and config.size[screen_name] and config.size[screen_name].height) or config.height
    return { position = pos, width = width, height = height }
end

local function calculate_position(screen_frame, config, screen_name)
    local sc = get_screen_config(config, screen_name)
    local x = sc.position.x >= 0 and sc.position.x or (screen_frame.w + sc.position.x - sc.width)
    local y = sc.position.y >= 0 and sc.position.y or (screen_frame.h + sc.position.y - sc.height)
    local rx = screen_frame.x + x
    local ry = screen_frame.y + y
    local on_screen = false
    for _, scr in ipairs(hs.screen.allScreens()) do
        local sf = scr:frame()
        if rx < sf.x + sf.w and rx + sc.width > sf.x and ry < sf.y + sf.h and ry + sc.height > sf.y then
            on_screen = true
            break
        end
    end
    if not on_screen then
        log.w("[WARN] Configured position is off-screen, using default")
        local def = config.position.default
        rx = screen_frame.x + (def.x >= 0 and def.x or (screen_frame.w + def.x - sc.width))
        ry = screen_frame.y + (def.y >= 0 and def.y or (screen_frame.h + def.y - sc.height))
    end
    return { x = rx, y = ry, w = sc.width, h = sc.height }
end

local function make_canvas(state, config)
    if state.canvas then state.canvas:delete() end
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local pos = calculate_position(frame, config, screen:name())
    local canvas = hs.canvas.new({ x = pos.x, y = pos.y, w = pos.w, h = pos.h })
    canvas:level(hs.canvas.windowLevels.floating)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    return canvas
end

local function bg_elements(config, alpha_override)
    local bg = config.background
    local a = alpha_override ~= nil and alpha_override or bg.alpha
    return {
        { id = "bg", type = "rectangle", action = "fill", trackMouseUp = true,
          roundedRectRadii = { xRadius = bg.corner_radius, yRadius = bg.corner_radius },
          fillColor = { red = bg.color.red, green = bg.color.green, blue = bg.color.blue, alpha = a } },
        { type = "rectangle", action = "stroke",
          roundedRectRadii = { xRadius = bg.corner_radius, yRadius = bg.corner_radius },
          strokeColor = { red = 0.3, green = 0.4, blue = 0.5, alpha = 0.5 }, strokeWidth = 1 },
        { id = "focus_ring", type = "rectangle", action = "stroke", hidden = true,
          roundedRectRadii = { xRadius = bg.corner_radius + 2, yRadius = bg.corner_radius + 2 },
          frame = { x = -3, y = -3, w = config.width + 6, h = config.height + 6 },
          strokeColor = { red = 0.145, green = 0.388, blue = 0.922, alpha = 1 }, strokeWidth = 3 },
    }
end

local function truncate_text(text, config)
    local chars_per_line = math.floor(config.width * 0.9 / (config.font.size * 0.6))
    local max_chars = chars_per_line * 4
    if #text > max_chars then return text:sub(1, max_chars - 1) .. "…" end
    return text
end

local function relative_time(ts)
    if not ts then return "" end
    local delta = os.time() - ts
    if delta < 60 then return "Just now"
    elseif delta < 3600 then return math.floor(delta / 60) .. " min ago"
    elseif delta < 86400 then return math.floor(delta / 3600) .. " hr ago"
    else return math.floor(delta / 86400) .. " days ago"
    end
end

local function dispatch_refresh()
    hs.urlevent.openURL("bibleverse://refresh")
end

function M.register_hotkeys(state, canvas, config)
    if state._hotkeys then
        for _, hk in ipairs(state._hotkeys) do hk:delete() end
    end
    state._hotkeys = {}

    state._hotkeys[#state._hotkeys+1] = hs.hotkey.new({}, "space", function()
        if not state._fetching then dispatch_refresh() end
    end)
    state._hotkeys[#state._hotkeys+1] = hs.hotkey.new({}, "return", function()
        if not state._fetching then dispatch_refresh() end
    end)

    state._hotkeys[#state._hotkeys+1] = hs.hotkey.new({"cmd"}, "c", function()
        if not canvas then return end
        local text = state._current_text or ""
        local ref = state._current_ref or ""
        local full = text .. (ref ~= "" and ("\n" .. ref) or "")
        local copy_ok = pcall(hs.pasteboard.setContents, full)
        if copy_ok then
            log.d("[COPY-OK]")
            if canvas["copied_tooltip"] then
                canvas["copied_tooltip"].hidden = false
                hs.timer.doAfter(1.5, function()
                    if canvas and canvas["copied_tooltip"] then canvas["copied_tooltip"].hidden = true end
                end)
            end
        else
            log.d("[COPY-FAIL]")
        end
    end)

    state._hotkeys[#state._hotkeys+1] = hs.hotkey.new({}, "escape", function()
        if canvas then canvas:hide() end
    end)

    for _, hk in ipairs(state._hotkeys) do hk:enable() end

    if not state._focus_ring_shown then
        state._focus_ring_shown = true
        if canvas["focus_ring"] then canvas["focus_ring"].hidden = false end
        M._show_shortcut_tooltip(state, canvas, config)
    end
end

function M._show_shortcut_tooltip(state, canvas, config)
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local pos = calculate_position(frame, config, screen:name())
    local tip = hs.canvas.new({ x = pos.x, y = pos.y - 30, w = pos.w, h = 26 })
    tip:appendElements({
        { type = "rectangle", action = "fill",
          fillColor = { red = 0, green = 0, blue = 0, alpha = 0.7 },
          roundedRectRadii = { xRadius = 4, yRadius = 4 } },
        { type = "text", text = "Space: refresh  •  Cmd+C: copy  •  Esc: dismiss error",
          textColor = { white = 1 }, textSize = 11, textFont = config.font.name,
          textAlignment = "right", frame = { x = "2%", y = "5%", w = "96%", h = "90%" } }
    })
    tip:level(hs.canvas.windowLevels.floating)
    tip:show()
    state._tooltip_canvas = tip
    hs.timer.doAfter(3, function()
        if state._tooltip_canvas then state._tooltip_canvas:delete(); state._tooltip_canvas = nil end
    end)
end

function M.render_loading(state, config)
    local canvas = make_canvas(state, config)
    local line_h = config.font.size * 1.4
    local ref_h = config.font.reference_size * 1.4
    local gap = config.font.size * 0.4
    local fill = { red = 150/255, green = 150/255, blue = 150/255, alpha = 0.3 }
    local x_off = math.floor(config.width * 0.05)
    local w_full = math.floor(config.width * 0.90)
    local w_ref = math.floor(config.width * 0.40)
    local y1 = math.floor(config.height * 0.08)
    local y2 = math.floor(y1 + line_h + gap)
    local y3 = math.floor(config.height * 0.78)
    local lh = math.floor(line_h)
    local rh = math.floor(ref_h)
    local elems = bg_elements(config)
    elems[#elems+1] = { type = "rectangle", action = "fill", fillColor = fill,
        frame = { x = x_off, y = y1, w = w_full, h = lh } }
    elems[#elems+1] = { type = "rectangle", action = "fill", fillColor = fill,
        frame = { x = x_off, y = y2, w = w_full, h = lh } }
    elems[#elems+1] = { type = "rectangle", action = "fill", fillColor = fill,
        frame = { x = x_off, y = y3, w = w_ref, h = rh } }
    canvas:appendElements(elems)
    canvas:canvasMouseEvents(false, true, false, false)
    canvas:show()
    return canvas
end

function M.render_verse(state, text, reference, config, verse_data, alpha_override)
    local canvas = make_canvas(state, config)
    local font = config.font
    local display_text = truncate_text(text, config)
    state._current_text = display_text
    state._current_ref = reference or ""
    local elems = bg_elements(config, alpha_override)
    elems[#elems+1] = { id = "verse_text", type = "text", text = display_text,
        textColor = font.color, textSize = font.size, textFont = font.name,
        textAlignment = "left", frame = { x = "5%", y = "8%", w = "90%", h = "68%" } }
    elems[#elems+1] = { id = "ref_text", type = "text", text = "— " .. (reference or ""),
        textColor = font.reference_color, textSize = font.reference_size, textFont = font.name,
        textAlignment = "right", frame = { x = "5%", y = "78%", w = "90%", h = "18%" } }
    elems[#elems+1] = { id = "offline_pill_bg", type = "rectangle", action = "fill", hidden = true,
        frame = { x = "80%", y = "4%", w = "18%", h = "14%" },
        fillColor = { red = 107/255, green = 114/255, blue = 128/255, alpha = 1 },
        roundedRectRadii = { xRadius = 3, yRadius = 3 } }
    elems[#elems+1] = { id = "offline_pill_text", type = "text", text = "Offline", hidden = true,
        textColor = { white = 1 }, textSize = 11, textFont = font.name,
        textAlignment = "center", frame = { x = "80%", y = "4%", w = "18%", h = "14%" } }
    elems[#elems+1] = { id = "copied_tooltip", type = "text", text = "Copied!", hidden = true,
        textColor = { red = 0.6, green = 0.6, blue = 0.6, alpha = 1 }, textSize = 11, textFont = font.name,
        textAlignment = "right", frame = { x = "60%", y = "4%", w = "38%", h = "14%" } }
    local ts_text = verse_data and verse_data.cached_at and ("Last updated " .. relative_time(verse_data.cached_at)) or ""
    elems[#elems+1] = { id = "timestamp", type = "text", text = ts_text,
        textColor = { red = font.color.red, green = font.color.green, blue = font.color.blue,
                      alpha = config.timestampAlpha or 0.45 },
        textSize = 10, textFont = font.name,
        textAlignment = "right", frame = { x = "5%", y = "87%", w = "90%", h = "10%" } }

    canvas:canvasMouseEvents(false, true, false, false)
    canvas:mouseCallback(function(c, msg, id, x, y)
        if msg ~= "mouseUp" or not verse_data then return end
        if c["bg"] then
            c["bg"].fillColor = { red = 37/255, green = 99/255, blue = 235/255, alpha = 0.15 }
            hs.timer.doAfter(0.1, function()
                if c and c["bg"] then
                    c["bg"].fillColor = { red = config.background.color.red, green = config.background.color.green, blue = config.background.color.blue, alpha = config.background.alpha }
                end
            end)
        end
        local url = "https://bolls.life/" .. verse_data.translation .. "/" .. verse_data.book .. "/" .. verse_data.chapter .. "/"
        hs.urlevent.openURL(url)
        log.d(string.format("[CLICK-OPEN translation=%s book=%d chapter=%d]", verse_data.translation, verse_data.book, verse_data.chapter))
    end)

    canvas:appendElements(elems)
    M.register_hotkeys(state, canvas, config)
    canvas:show()
    return canvas
end

function M.render_error(state, bucket, cached_verse, config)
    local canvas = make_canvas(state, config)
    local font = config.font
    local warn_color = { red = 212/255, green = 160/255, blue = 23/255, alpha = 1 }
    local elems = bg_elements(config)

    elems[#elems+1] = { type = "rectangle", action = "fill",
        fillColor = { red = 212/255, green = 160/255, blue = 23/255, alpha = 0.08 },
        roundedRectRadii = { xRadius = config.background.corner_radius, yRadius = config.background.corner_radius },
        frame = { x = 0, y = 0, w = config.width, h = config.height } }

    elems[#elems+1] = { type = "text", text = "⚠", textColor = warn_color, textSize = 16, textFont = font.name,
        textAlignment = "left", frame = { x = "5%", y = "8%", w = "15%", h = "25%" } }

    local msg = bucket == "offline" and "No internet connection"
        or bucket == "service" and "Service unavailable"
        or "Could not load verse"
    elems[#elems+1] = { type = "text", text = msg, textColor = font.color, textSize = 14, textFont = font.name,
        textAlignment = "left", frame = { x = "22%", y = "10%", w = "73%", h = "25%" } }

    elems[#elems+1] = { id = "try_again", type = "text", text = "Try Again",
        textColor = warn_color, textSize = 14, textFont = font.name, trackMouseUp = true,
        textAlignment = "center", frame = { x = "30%", y = "60%", w = "40%", h = "25%" } }

    local pill_hidden = bucket ~= "offline"
    elems[#elems+1] = { id = "offline_pill_bg", type = "rectangle", action = "fill", hidden = pill_hidden,
        frame = { x = "80%", y = "4%", w = "18%", h = "14%" },
        fillColor = { red = 107/255, green = 114/255, blue = 128/255, alpha = 1 },
        roundedRectRadii = { xRadius = 3, yRadius = 3 } }
    elems[#elems+1] = { id = "offline_pill_text", type = "text", text = "Offline", hidden = pill_hidden,
        textColor = { white = 1 }, textSize = 11, textFont = font.name,
        textAlignment = "center", frame = { x = "80%", y = "4%", w = "18%", h = "14%" } }

    if cached_verse and type(cached_verse.text) == "string" then
        local cleaned = cached_verse.text:gsub("<[^>]+>", ""):gsub("&nbsp;", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
        local time_str = cached_verse.cached_at and (" · Last updated " .. relative_time(cached_verse.cached_at)) or ""
        elems[#elems+1] = { type = "text", text = "Showing saved verse" .. time_str,
            textColor = warn_color, textSize = 10, textFont = font.name,
            textAlignment = "left", frame = { x = "5%", y = "42%", w = "90%", h = "8%" } }
        elems[#elems+1] = { type = "text", text = cleaned,
            textColor = { red = font.color.red or 0.78, green = font.color.green or 0.77, blue = font.color.blue or 0.96, alpha = 0.45 },
            textSize = font.size * 0.85, textFont = font.name,
            textAlignment = "left", frame = { x = "5%", y = "51%", w = "90%", h = "27%" } }
    end

    canvas:canvasMouseEvents(false, true, false, false)
    canvas:mouseCallback(function(c, cb_msg, id)
        if cb_msg == "mouseUp" and id == "try_again" then dispatch_refresh() end
    end)

    if state._hotkeys then
        for _, hk in ipairs(state._hotkeys) do hk:delete() end
    end
    state._hotkeys = {}
    state._hotkeys[#state._hotkeys+1] = hs.hotkey.new({}, "space", function()
        if not state._fetching then dispatch_refresh() end
    end)
    state._hotkeys[#state._hotkeys+1] = hs.hotkey.new({}, "return", function()
        if not state._fetching then dispatch_refresh() end
    end)
    state._hotkeys[#state._hotkeys+1] = hs.hotkey.new({}, "escape", function()
        if canvas then canvas:hide() end
    end)
    for _, hk in ipairs(state._hotkeys) do hk:enable() end

    canvas:appendElements(elems)
    canvas:show()
    return canvas
end

-- fade_in: animates bg alpha from current value to target over `duration` seconds.
-- Uses upvalue to capture timer handle — hs.timer.doEvery does NOT pass timer to callback.
function M.fade_in(state, config, duration)
    if not state.canvas then return end
    local steps = 20
    local step_time = duration / steps
    local current_step = 0
    local target_alpha = config.background.alpha
    local t
    t = hs.timer.doEvery(step_time, function()
        current_step = current_step + 1
        local alpha = target_alpha * current_step / steps
        if state.canvas and state.canvas["bg"] then
            state.canvas["bg"].fillColor = {
                red = config.background.color.red,
                green = config.background.color.green,
                blue = config.background.color.blue,
                alpha = alpha
            }
        end
        if current_step >= steps then t:stop() end
    end)
end

function M.destroy(canvas)
    if canvas then canvas:delete() end
end

return M
