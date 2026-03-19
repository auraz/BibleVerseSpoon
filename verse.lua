--- Verse fetching, caching, and parsing functions.
local translations = dofile(hs.spoons.resourcePath("translations.lua"))
local log = hs.logger.new("bibleverse", "debug")

local M = {}
local API_BASE = "https://bolls.life/get-random-verse/"
local CACHE_KEY = "bibleverse.verse"

function M.clean_text(raw)
    return raw:gsub("<[^>]+>", ""):gsub("&nbsp;", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

function M.get_book_name(book_num, translation)
    local books = translations[translation]
    return books and books[book_num] or ("Book " .. book_num)
end

function M.format_reference(data, translation)
    return M.get_book_name(data.book, translation) .. " " .. data.chapter .. ":" .. data.verse
end

function M.save_cache(data)
    local ok, err = pcall(hs.settings.set, CACHE_KEY, data)
    if not ok then
        log.w("[WARN] cache write failed: " .. tostring(err))
        return false
    end
    return true
end

function M.load_cache()
    local ok, data = pcall(hs.settings.get, CACHE_KEY)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

-- fetch(translation, callback)
-- callback(data, err_type) where err_type is nil on success, or "offline"|"service"|"unreadable"
-- Does NOT manage _fetching flag — caller's responsibility.
function M.fetch(translation, callback)
    local done = false
    local timed_out = false

    local function finish(data, err_type)
        if done then return end
        done = true
        callback(data, err_type)
    end

    local timeout_timer = hs.timer.doAfter(5, function()
        timed_out = true
        finish(nil, "unreadable")
    end)

    local nt_attempts = 0
    local max_nt_attempts = 5

    local function try_fetch()
        hs.http.asyncGet(API_BASE .. translation .. "/", nil, function(status, body)
            if timed_out then return end

            if status == -1 or status == 0 then
                timeout_timer:stop()
                finish(nil, "offline")
                return
            end

            if status >= 400 then
                timeout_timer:stop()
                finish(nil, "service")
                return
            end

            if status ~= 200 then
                timeout_timer:stop()
                finish(nil, "service")
                return
            end

            local ok, data = pcall(hs.json.decode, body)
            if not ok or type(data) ~= "table" then
                timeout_timer:stop()
                finish(nil, "unreadable")
                return
            end

            if type(data.book) ~= "number" or type(data.chapter) ~= "number"
                or type(data.verse) ~= "number" or type(data.text) ~= "string" then
                timeout_timer:stop()
                finish(nil, "unreadable")
                return
            end

            if data.book < 40 or data.book > 66 then
                nt_attempts = nt_attempts + 1
                if nt_attempts >= max_nt_attempts then
                    timeout_timer:stop()
                    finish(nil, "unreadable")
                    return
                end
                try_fetch()
                return
            end

            timeout_timer:stop()
            finish(data, nil)
        end)
    end

    try_fetch()
end

return M
