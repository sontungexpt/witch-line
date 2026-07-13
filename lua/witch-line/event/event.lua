local next, type, api = next, type, vim.api
local str_byte, str_find, str_sub = string.byte, string.find, string.sub

local M = {}

--- Sentinel key for once-only ids (unique table ref, can't collide with numeric keys).
local ONCE = 0

--- @alias EventBucket table<table|integer,CompId|CompId[]>
--- { [1] = comp1, [2] = comp2, [ONCE] = { comp_once1, comp_once2 } }

--- @type table<string, EventBucket>
--- Patternless events, combined into one autocmd at compile time.
---
--- After registering "BufEnter" and "BufLeave ++once":
---   SimpleEvents = {
---     ["BufEnter"] = {
---         [ONCE] = { cid2 }
---         [1] = cid1
---     },
---   }
local VimEvents = {}

--- @type table<string, EventBucket>
--- User events keyed by name (autocmd pattern). One autocmd covers all.
---
--- After registering "User LazyLoad ++once" and "User ColorScheme":
---   UserEvents = {
---     ["LazyLoad"] = {
---         [ONCE] = { cid1 }
---         [1] = cid2
---     },
---     ["ColorScheme"] = {
---         [1] = cid2
---     }
---   }
local UserEvents = {}

--- @type table<string, table<string, EventBucket>>
--- Pattern events: PatternEvents[pattern][event] = bucket.
--- Groups by pattern so one autocmd covers all events sharing that pattern.
---
--- After registering "BufEnter *.lua ++once" and "BufWritePost *.lua":
---   PatternEvents = {
---     ["*.lua"] = {
---         ["BufEnter"] = {
---             [ONCE] = { cid1 }
---             [1] = cid2
---         },
---         ["BufWritePost"] = {
---              [1] = cid2
---         }
---     }
---   }
local PatternEvents = {}

--- Add comp_id to a bucket. Normal → numeric index, once → bucket[ONCE].
---@param bucket EventBucket
---@param comp_id CompId
---@param once? boolean
local add_to_bucket = function(bucket, comp_id, once)
    if once then
        local once_list = bucket[ONCE]
        if once_list == nil then
            bucket[ONCE] = { comp_id }
        else
            once_list[#once_list + 1] = comp_id
        end
    else
        bucket[#bucket + 1] = comp_id
    end
end

--- Parse and route an event string.
---
--- ```
---   "BufEnter"                          → SimpleEvents["BufEnter"]
---   " BufEnter "                        → SimpleEvents["BufEnter"]  (trimmed)
---   "BufEnter *.lua"                    → PatternEvents["*.lua"]["BufEnter"]
---   "BufEnter *.lua,*.md"              → PatternEvents["*.lua"]["BufEnter"]
---                                       + PatternEvents["*.md"]["BufEnter"]
---   "BufEnter *.lua , *.md"            → same, commas+spaces tolerated
---   "BufEnter *.lua ++once"            → PatternEvents["*.lua"]["BufEnter"] [ONCE]
---   "BufEnter *.lua,*.md ++once"       → same with ONCE on both patterns
---   "User LazyLoad"                     → UserEvents["LazyLoad"]
---   "User LazyLoad ++once"             → UserEvents["LazyLoad"] [ONCE]
---   "User MyEvent,OtherEvent"          → UserEvents["MyEvent"]
---                                       + UserEvents["OtherEvent"]
---   "BufWritePost *"                    → SimpleEvents["BufWritePost"]  (* = wildcard)
--- ```
--- Syntax: `<Event> [<Pat>[,<Pat>...]] [++once]`
--- Routing: patterns → PatternEvents, `User` → UserEvents, bare → SimpleEvents.
---
--- @param e       string
--- @param comp_id CompId
local register_string_event = function(e, comp_id)
    local slen = #e
    local pos = 1

    while pos <= slen and str_byte(e, pos) == 32 do
        pos = pos + 1
    end
    if pos > slen then return end

    local s_at = str_find(e, " ", pos, true)
    if s_at == nil then
        local name = str_sub(e, pos)
        local bucket = VimEvents[name]
        if bucket == nil then
            bucket = {}
            VimEvents[name] = bucket
        end
        add_to_bucket(bucket, comp_id, false)
        return
    end
    local event_name = str_sub(e, pos, s_at - 1)

    pos = s_at + 1
    while pos <= slen and str_byte(e, pos) == 32 do
        pos = pos + 1
    end
    if pos > slen then
        local bucket = VimEvents[event_name]
        if bucket == nil then
            bucket = {}
            VimEvents[event_name] = bucket
        end
        add_to_bucket(bucket, comp_id, false)
        return
    end

    local once = false
    local pend = slen
    if slen >= pos + 5 then
        local scan = slen
        while scan >= pos and str_byte(e, scan) == 32 do
            scan = scan - 1
        end
        if scan >= pos + 5 then
            local o_at = scan - 5
            local b1, b2, b3, b4, b5, b6 = str_byte(e, o_at, o_at + 5)
            if b1 == 43 and b2 == 43 and b3 == 111
                and b4 == 110 and b5 == 99 and b6 == 101
            then
                once = true
                pend = o_at - 1
            end
        end
    end

    local patterns, npat = {}, 0
    while pos <= pend do
        while pos <= pend and str_byte(e, pos) == 32 do
            pos = pos + 1
        end
        if pos > pend then
            break
        end

        local comma = str_find(e, ",", pos, true)
        local seg_end = (comma and comma <= pend) and comma - 1 or pend
        while seg_end >= pos and str_byte(e, seg_end) == 32 do
            seg_end = seg_end - 1
        end

        if seg_end >= pos then
            local t = str_sub(e, pos, seg_end)
            if t == "*" then
                npat = 0
                break
            end
            npat = npat + 1
            patterns[npat] = t
        end

        if comma == nil or comma > pend then
            break
        end
        pos = comma + 1
    end

    if event_name == "User" then
        for i = 1, npat do
            local bucket = UserEvents[patterns[i]]
            if bucket == nil then
                bucket = {}
                UserEvents[patterns[i]] = bucket
            end
            add_to_bucket(bucket, comp_id, once)
        end
    elseif npat > 0 then
        for i = 1, npat do
            local pat = patterns[i]
            local pat_bucket = PatternEvents[pat]
            if pat_bucket == nil then
                pat_bucket = {}
                PatternEvents[pat] = pat_bucket
            end
            local bucket = pat_bucket[event_name]
            if bucket == nil then
                bucket = {}
                pat_bucket[event_name] = bucket
            end
            add_to_bucket(bucket, comp_id, once)
        end
    else
        local bucket = VimEvents[event_name]
        if bucket == nil then
            bucket = {}
            VimEvents[event_name] = bucket
        end
        add_to_bucket(bucket, comp_id, once)
    end
end

--- Register a component for one or more event strings.
---
--- Accepts a single string or an array of strings. Each string is parsed by
--- `register_string_event` which routes into SimpleEvents, UserEvents, or
--- PatternEvents depending on the presence of patterns and the event name.
---
--- @param cid    CompId            Component identifier.
--- @param events string|string[] Event definition(s).
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

--- Register a component to be updated once on VimEnter.
--- Batches all IDs into a single autocmd.
--- @param cid CompId
M.register_vim_enter_once = function(cid)
    local bucket = VimEvents["VimEnter"]
    if bucket == nil then
        bucket = {}
        VimEvents["VimEnter"] = bucket
    end
    add_to_bucket(bucket, cid, true)
end

--- Print current registry state for debugging.
M.inspect = function()
    require("witch-line.util.notifier").info(vim.inspect({
        SimpleEvents = VimEvents,
        UserEvents = UserEvents,
        PatternEvents = PatternEvents,
    }))
end

--- Get a table's keys as a list.
--- @param t table
--- @return any[]
local tbl_keys = function(t)
    local keys, i = {}, 0
    --- Use next to reduce overhead
    for k in next, t do
        i = i + 1
        keys[i] = k
    end
    return keys
end

--- Compile registries into Neovim autocmds (call once after all register_events).
---
--- Autocmds created: 1 for SimpleEvents + 1 for UserEvents + 1 per PatternEvents key.
--- ONCE is managed in-callback (dispatch bucket[ONCE] then nil it) instead of
--- Neovim's `once=true`, avoiding one autocmd per (event, pattern, once) triple.
---
--- @param work fun(ids: CompId[], event_queue: table<CompId, vim.api.keyset.create_autocmd.callback_args>)
M.on_event = function(work)
    --- @type table<CompId, vim.api.keyset.create_autocmd.callback_args>
    local event_queue = {}

    local dispatch = function()
        local ids = tbl_keys(event_queue)
        work(ids, event_queue)
        event_queue = {}
    end

    local dispatch_debounce
    dispatch_debounce = function(...)
        dispatch_debounce = require("witch-line.util.debounce")(dispatch, 110)
        dispatch_debounce(...)
    end

    local enqueue = function(bucket, e)
        if bucket == nil then return end
        for i = 1, #bucket do
            event_queue[bucket[i]] = e
        end
        local once_list = bucket[ONCE]
        if once_list ~= nil then
            for i = 1, #once_list do
                event_queue[once_list[i]] = e
            end
            bucket[ONCE] = nil
        end
        dispatch_debounce()
    end

    local AUGROUP = api.nvim_create_augroup("WitchLineAutocmd", { clear = true })

    if next(VimEvents) then
        api.nvim_create_autocmd(tbl_keys(VimEvents), {
            group = AUGROUP,
            callback = function(e)
                enqueue(VimEvents[e.event], e)
            end,
        })
    end

    if next(UserEvents) then
        api.nvim_create_autocmd("User", {
            pattern = tbl_keys(UserEvents),
            group = AUGROUP,
            callback = function(e)
                enqueue(UserEvents[e.match], e)
            end,
        })
    end

    --- Use next to reduce overhead
    for pattern, event_buckets in next, PatternEvents do
        api.nvim_create_autocmd(tbl_keys(event_buckets), {
            pattern = pattern,
            group = AUGROUP,
            callback = function(e)
                enqueue(event_buckets[e.event], e)
            end
        })
    end
end

return M
