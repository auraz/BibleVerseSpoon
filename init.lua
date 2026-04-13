--- BibleVerse Spoon — displays random Bible verses as desktop widget.
local obj = {}
obj.__index = obj
obj.name = "BibleVerse"
obj.version = "2.1"
obj.author = "Oleksandr"

local log = hs.logger.new("bibleverse", "debug")
local verse = dofile(hs.spoons.resourcePath("verse.lua"))
local widget = dofile(hs.spoons.resourcePath("widget.lua"))

local ok_cfg, raw_config = pcall(dofile, hs.spoons.resourcePath("config.lua"))
if not ok_cfg then
    log.e(string.format("[ERROR] config parse failed: %s", tostring(raw_config)))
    raw_config = {
        translation = "KJV", refresh_interval = 3600,
        background = { color = { red = 0.1, green = 0.1, blue = 0.15 }, alpha = 0.85, corner_radius = 25 },
        font = { name = "Helvetica", size = 18, color = { red = 0.78, green = 0.77, blue = 0.96 },
                 reference_color = { red = 0.61, green = 0.64, blue = 0.69 }, reference_size = 14 },
        width = 400, height = 165, position = { default = { x = -350, y = -15 } },
        timestampAlpha = 0.45
    }
end

local function validate_config(cfg)
    if cfg.translation ~= "UBIO" and cfg.translation ~= "KJV" then
        log.w(string.format("[WARN] Unknown translation '%s', defaulting to KJV", tostring(cfg.translation)))
        cfg.translation = "KJV"
    end
    if type(cfg.refresh_interval) ~= "number" or cfg.refresh_interval <= 0 then
        log.w("[WARN] Invalid refreshInterval, defaulting to 3600")
        cfg.refresh_interval = 3600
    end
    if type(cfg.font) == "table" and type(cfg.font.size) == "number" then
        if cfg.font.size < 10 or cfg.font.size > 48 then
            local clamped = math.max(10, math.min(48, cfg.font.size))
            log.w(string.format("[WARN] fontSize clamped to %d", clamped))
            cfg.font.size = clamped
        end
    end
    if type(cfg.background) == "table" and type(cfg.background.alpha) == "number" then
        if cfg.background.alpha < 0 or cfg.background.alpha > 1 then
            local clamped = math.max(0, math.min(1, cfg.background.alpha))
            log.w(string.format("[WARN] alpha clamped to %.2f", clamped))
            cfg.background.alpha = clamped
        end
    end
    if type(cfg.font) == "table" and (cfg.font.name == nil or cfg.font.name == "") then
        cfg.font.name = "Helvetica"
    end
    if type(cfg.timestampAlpha) == "number" then
        if cfg.timestampAlpha < 0 or cfg.timestampAlpha > 1 then
            local clamped = math.max(0, math.min(1, cfg.timestampAlpha))
            log.w(string.format("[WARN] timestampAlpha clamped to %.2f", clamped))
            cfg.timestampAlpha = clamped
        end
    elseif cfg.timestampAlpha ~= nil then
        log.w("[WARN] timestampAlpha invalid type, defaulting to 0.45")
        cfg.timestampAlpha = 0.45
    end
    return cfg
end

obj.config = {}
for k, v in pairs(raw_config) do obj.config[k] = v end
obj.config = validate_config(obj.config)

local state = {
    canvas = nil, timer = nil, watcher = nil,
    _fetching = false, _last_fetch_time = nil,
    _retry_timer = nil, _retry_count = 0,
    _focus_ring_shown = false,
    _hotkeys = nil, _tooltip_canvas = nil,
    _vo_unavailable = false, _vo_warned = false,
    _current_text = nil, _current_ref = nil,
    _last_success_time = nil
}

local states -- forward declaration; assigned in start() after states.lua loads

local RETRY_DELAYS = { 5, 15, 30 }

local function check_version()
    local ver = (hs.processInfo and hs.processInfo.version) or "0.0.0"
    local major, minor, patch = ver:match("(%d+)%.(%d+)%.(%d+)")
    major, minor, patch = tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    if major == 0 and (minor < 9 or (minor == 9 and patch < 100)) then
        log.w("[WARN] BibleVerseSpoon requires Hammerspoon >= 0.9.100. Some features may not work.")
    end
end

function obj:_schedule_retry()
    if state._retry_count >= 3 then return end
    state._retry_count = state._retry_count + 1
    local delay = RETRY_DELAYS[state._retry_count]
    log.d(string.format("[FETCH-RETRY attempt%d]", state._retry_count))
    state._retry_timer = hs.timer.doAfter(delay, function() self:refresh("retry") end)
end

function obj:_on_wake()
    local now = os.time()
    if state._last_fetch_time == nil then
        log.d("[WAKE-FETCH reason=first-fetch]")
        self:refresh("wake")
        return
    end
    local delta = now - state._last_fetch_time
    if delta < 0 then
        log.w("[WARN] Clock skew detected, skipping wake refresh")
        return
    end
    if delta >= 900 then self:refresh("wake") end
end

function obj:refresh(source)
    source = source or "manual"
    if source == "manual" and state._retry_timer then
        state._retry_timer:stop()
        state._retry_timer = nil
    end
    if state._fetching then
        log.d("[FETCH-SKIP in-flight]")
        return self
    end
    state._fetching = true
    state._last_fetch_time = os.time()
    if states then states.transition("loading") end
    local fetch_start = os.time()
    verse.fetch(self.config.translation, function(data, err_type)
        state._fetching = false
        if data then
            data.cached_at = os.time()
            verse.save_cache(data)
            state._last_success_time = os.time()
            state._retry_count = 0
            if state._retry_timer then state._retry_timer:stop(); state._retry_timer = nil end
            if states then
                local text = verse.clean_text(data.text)
                local ref = verse.format_reference(data, self.config.translation)
                states.transition("displaying", { text = text, reference = ref, verse_data = data, cached_at = data.cached_at })
            end
            log.d(string.format("[FETCH-OK elapsed=%d]", os.time() - fetch_start))
        else
            log.d(string.format("[FETCH-FAIL reason=%s]", tostring(err_type)))
            if state._last_success_time == nil or (os.time() - state._last_success_time) > 86400 then
                log.w("[WARN] bolls.life may be permanently unavailable — no successful fetch in 24h or ever")
            end
            local cached = verse.load_cache()
            if states then states.transition("error", { bucket = err_type, cached_verse = cached }) end
            self:_schedule_retry()
        end
    end)
    return self
end

function obj:start()
    check_version()
    log.d("[INFO] FULLSCREEN-EXCLUDE logging not available in this Hammerspoon version")
    if state.canvas ~= nil then self:stop() end

    local start_ms = os.clock()

    widget.set_refresh_callback(function() self:refresh("manual") end)

    local ok_st, loaded_states = pcall(dofile, hs.spoons.resourcePath("states.lua"))
    if ok_st then
        states = loaded_states
        states.init(state, widget, self.config)
    else
        log.e("[ERROR] states.lua load failed: " .. tostring(loaded_states))
    end

    local cached = verse.load_cache()
    if cached and type(cached.text) == "string" then
        state._last_fetch_time = cached.cached_at or (os.time() - self.config.refresh_interval)
        if states then
            local text = verse.clean_text(cached.text)
            local ref = verse.format_reference(cached, self.config.translation)
            states.transition("displaying", { text = text, reference = ref, verse_data = cached, cached_at = cached.cached_at })
        end
    else
        if states then states.transition("loading") end
        self:refresh("manual")
    end

    state.timer = hs.timer.doEvery(self.config.refresh_interval, function() self:refresh("timer") end)
    state.watcher = hs.caffeinate.watcher.new(function(e)
        if e == hs.caffeinate.watcher.systemDidWake then self:_on_wake() end
    end)
    state.watcher:start()

    hs.urlevent.bind("bibleverse", function(event_name)
        if event_name == "refresh" then self:refresh("manual") end
    end)

    log.d(string.format("[INIT-COMPLETE ms=%d]", math.floor((os.clock() - start_ms) * 1000)))
    return self
end

function obj:stop()
    hs.urlevent.bind("bibleverse", nil)
    if state._retry_timer then state._retry_timer:stop() end
    if state.timer then state.timer:stop() end
    if state.watcher then state.watcher:stop() end
    if state._hotkeys then
        for _, hk in ipairs(state._hotkeys) do hk:delete() end
    end
    if state._tooltip_canvas then state._tooltip_canvas:delete() end
    widget.destroy(state.canvas)
    state = {
        canvas = nil, timer = nil, watcher = nil,
        _fetching = false, _last_fetch_time = nil,
        _retry_timer = nil, _retry_count = 0,
        _focus_ring_shown = false,
        _hotkeys = nil, _tooltip_canvas = nil,
        _vo_unavailable = false, _vo_warned = false,
        _current_text = nil, _current_ref = nil,
        _last_success_time = nil
    }
    return self
end

function obj:focus()
    return self
end

return obj
