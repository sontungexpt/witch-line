local next, type, pairs, vim = next, type, pairs, vim
local byte, find = string.byte, string.find
local nvim_create_autocmd = vim.api.nvim_create_autocmd

local M = {}


--- @type table<string, CompId[]>
local Events = {}

--- @type table<string, CompId[]>
local UserEvents = {}

--- SpecialEvents[event_name][pattern_or_true] = { ids = CompId[], once = boolean }
--- @type table<string, table<string|true, {ids:CompId[], once:boolean}>>
local SpecialEvents = {}

local function register_normal_event(store, key, comp_id)
    local list = store[key]
    if list then
        list[#list + 1] = comp_id
        return list
    end
    list = { comp_id }
    store[key] = list
    return list
end

local function register_special_event(name, pattern, once, comp_id)
    local bucket = SpecialEvents[name]
    if not bucket then
        bucket = {}
        SpecialEvents[name] = bucket
    end

    -- normalize key: string stays as-is, table is serialized, nil becomes true
    local key = pattern or true
    local entry = bucket[key]
    if entry then
        entry.ids[#entry.ids + 1] = comp_id
        entry.once = entry.once or once
    else
        bucket[key] = { ids = { comp_id }, once = once, pattern = pattern }
    end
end

--- Grammar: `<Event> [<Pat>[,<Pat>...]] [++once]`
---
--- `Event` = first whitespace-delimited word. `Pat` = comma-separated list
--- (space does NOT split — only `,`). `++once` must be the **last** token.
--- `*` as sole pattern = wildcard (stripped). `"User"` events store each
--- pattern independently. Multiple registrations for the same event+pattern
--- merge their `CompId` lists (once = OR'd).
---
--- Examples:
---   `"BufEnter"`               → BufEnter, normal
---   `"BufEnter ++once"`        → BufEnter, once
---   `"BufEnter *.lua"`         → BufEnter, pat=*.lua, normal
---   `"BufEnter *.lua ++once"`  → BufEnter, pat=*.lua, once
---   `"BufEnter *.lua,*.py ++once"` → BufEnter, pats={*.lua,*.py}, once
---   `"User FormatEnabled"`     → User FormatEnabled, normal
---   `"User FormatEnabled ++once"` → User FormatEnabled, once
---   `"User A,B ++once"`        → User A *and* B, each once
---   `"BufEnter ++once *.lua"`  → ++once treated as literal pattern
---
--- @param e       string  The event definition string.
--- @param comp_id any     Component identifier to register.
local function register_string_event(e, comp_id)
    local slen = #e
    local pos = 1

    -- skip leading whitespace before the event name
    while pos <= slen and byte(e, pos) == 32 do pos = pos + 1 end -- skip space (byte 32)
    if pos > slen then return end

    -- extract event name: the first whitespace-delimited word
    local s_at = find(e, " ", pos, true)
    if not s_at then
        register_normal_event(Events, e:sub(pos), comp_id)
        return
    end
    local event_name = e:sub(pos, s_at - 1)

    -- advance past whitespace between event name and patterns
    pos = s_at + 1
    while pos <= slen and byte(e, pos) == 32 do pos = pos + 1 end
    if pos > slen then
        register_normal_event(Events, event_name, comp_id)
        return
    end

    -- detect ++once: scan backward from end, skipping trailing whitespace
    -- then check if the last 6 non-whitespace bytes are "++once"
    local once = false
    local pend = slen -- effective end of pattern area (truncated if ++once found)
    if slen >= pos + 5 then
        local scan = slen
        while scan >= pos and byte(e, scan) == 32 do
            scan = scan - 1
        end
        if scan >= pos + 5 then
            local o_at = scan - 5
            local b1, b2, b3, b4, b5, b6 = byte(e, o_at, o_at + 5)
            -- "++once" = 43,43,111,110,99,101
            if b1 == 43
                and b2 == 43
                and b3 == 111
                and b4 == 110
                and b5 == 99
                and b6 == 101
            then
                once = true
                pend = o_at - 1
            end
        end
    end

    -- split pattern area by comma, trim leading/trailing whitespace per segment
    local patterns, npat = {}, 0
    while pos <= pend do
        -- skip leading whitespace within each segment
        while pos <= pend and byte(e, pos) == 32 do
            pos = pos + 1
        end
        if pos > pend then
            break
        end

        -- find the end of this segment (comma or end of pattern area)
        local comma = find(e, ",", pos, true)
        local seg_end
        if comma and comma <= pend then
            seg_end = comma - 1
        else
            seg_end = pend
        end
        -- trim trailing whitespace from the segment
        while seg_end >= pos and byte(e, seg_end) == 32 do
            seg_end = seg_end - 1
        end

        if seg_end >= pos then
            local t = e:sub(pos, seg_end)

            if t == "*" then
                -- "*" matches everything → clear patterns, register without pattern
                npat = 0
                break
            end
            npat = npat + 1; patterns[npat] = t
        end

        if not comma or comma > pend then
            break
        end
        pos = comma + 1
    end

    -- route: User events go to UserEvents, ++once or pattern-bearing events to SpecialEvents
    if event_name == "User" then
        if once then
            for i = 1, npat do
                register_special_event("User", patterns[i], once, comp_id)
            end
        else
            for i = 1, npat do
                register_normal_event(UserEvents, patterns[i], comp_id)
            end
        end
    elseif once or npat > 0 then
        for i = 1, npat do
            register_special_event(event_name, patterns[i], once, comp_id)
        end
    else
        register_normal_event(Events, event_name, comp_id)
    end
end

M.register_events = function(cid, events)
    local t = type(events)
    if t == "string" then
        register_string_event(events, cid)
    elseif t == "table" then
        for i = 1, #events do
            local event = events[i]
            if type(event) == "string" then
                register_string_event(event, cid)
            end
        end
    end
end

M.inspect = function()
    require("witch-line.util.notifier").info(vim.inspect({
        Events = Events,
        UserEvents = UserEvents,
        SpecialEvents = SpecialEvents,
    }))
end

M.on_event = function(work)
    --- @type table<CompId, vim.api.keyset.create_autocmd.callback_args>
    local event_queue = {}

    local dispatch = function()
        local ids, i = {}, 0
        for id in pairs(event_queue) do
            i = i + 1
            ids[i] = id
        end
        work(ids, event_queue)
        event_queue = {}
    end

    local dispatch_debounce
    dispatch_debounce = function(...)
        dispatch_debounce = require("witch-line.util.debounce")(dispatch, 110)
        dispatch_debounce(...)
    end

    local AUGROUP = vim.api.nvim_create_augroup("WitchLineEvent", { clear = true })
    if next(Events) then
        nvim_create_autocmd(vim.tbl_keys(Events), {
            group = AUGROUP,
            callback = function(e)
                for _, id in ipairs(Events[e.event]) do
                    event_queue[id] = e
                end
                dispatch_debounce()
            end,
        })
    end

    if next(UserEvents) then
        nvim_create_autocmd("User", {
            pattern = vim.tbl_keys(UserEvents),
            group = AUGROUP,
            callback = function(e)
                for _, id in ipairs(UserEvents[e.match]) do
                    event_queue[id] = e
                end
                dispatch_debounce()
            end,
        })
    end

    if next(SpecialEvents) then
        for name, bucket in pairs(SpecialEvents) do
            for _, entry in pairs(bucket) do
                nvim_create_autocmd(name, {
                    pattern = entry.pattern or nil,
                    once = entry.once or nil,
                    group = AUGROUP,
                    callback = function(e)
                        for _, id in ipairs(entry.ids) do
                            event_queue[id] = e
                        end
                        dispatch_debounce()
                    end,
                })
            end
        end
    end
end

return M
