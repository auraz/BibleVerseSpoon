--- State machine module. Central coordinator for widget visual state.
-- All widget rendering goes through M.transition — no other module calls widget.lua directly.
local log = hs.logger.new("bibleverse", "debug")

local M = {}

local _state_name = "loading"
local _cached_verse = nil
local _state_ref = nil   -- init.lua's state table
local _widget = nil      -- widget module
local _config = nil      -- active config table

function M.init(state_ref, widget_module, config)
    _state_ref = state_ref
    _widget = widget_module
    _config = config
end

function M.current()
    return _state_name
end

function M.cached_verse()
    return _cached_verse
end

-- announce_vo: no-go path — AX spike did not confirm hs.canvas AX API availability.
-- Sets _vo_unavailable on first call and logs one-time [WARN]. No-op thereafter.
-- To enable VoiceOver in a future version: replace body with confirmed AX call.
local function announce_vo(text)
    if not _state_ref then return end
    if _state_ref._vo_unavailable then return end
    if not _state_ref._vo_warned then
        _state_ref._vo_warned = true
        _state_ref._vo_unavailable = true
        log.w("[WARN] VoiceOver announcements unavailable in this Hammerspoon version")
    end
end

function M.transition(name, data)
    if not _state_ref or not _widget or not _config then
        log.w("[WARN] states.transition called before init")
        return
    end
    _state_name = name

    if name == "loading" then
        _state_ref.canvas = _widget.render_loading(_state_ref, _config)
        announce_vo("Loading verse...")

    elseif name == "displaying" then
        if type(data) ~= "table" or type(data.text) ~= "string" then
            log.w("[WARN] states.transition displaying called with invalid data")
            return
        end
        _cached_verse = data.verse_data or data
        _state_ref.canvas = _widget.render_verse(_state_ref, data.text, data.reference, _config, data.verse_data, 0)
        hs.timer.doAfter(0.01, function()
            _widget.fade_in(_state_ref, _config, 0.2)
        end)
        announce_vo(data.text .. " — " .. (data.reference or ""))

    elseif name == "error" then
        local bucket = (type(data) == "table") and data.bucket or "unreadable"
        local cached = (type(data) == "table") and data.cached_verse or nil
        _state_ref.canvas = _widget.render_error(_state_ref, bucket, cached, _config)
        local msg = bucket == "offline" and "No internet connection"
            or bucket == "service" and "Service unavailable"
            or "Could not load verse"
        announce_vo(msg)

    else
        log.w("[WARN] states.transition unknown state: " .. tostring(name))
    end
end

return M
