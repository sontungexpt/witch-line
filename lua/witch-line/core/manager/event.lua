local next, type, pairs, vim = next, type, pairs, vim
local nvim_create_autocmd = vim.api.nvim_create_autocmd

local M = {}


local AUGROUP = vim.api.nvim_create_augroup("WitchLineEvent", { clear = true })

--- Options used for configuring a special event.
--- These fields control event behavior but do not include identifiers.
--- @class SpecialEventOpts
--- @field once? boolean  Optional flag. If true, the event is triggered only once.
--- @field remove_when? fun():boolean The event will be remove when `remove_when` return true
---
--- Optional file/buffer pattern(s).
--- Can be:
---   - string: a single pattern
---   - string[]: list of patterns
---   - nil: no pattern filtering
--- Empty strings or "*" are treated as no pattern.
--- @field pattern? string|string[]|nil

--- Represents a fully registered special event entry stored in the event registry.
--- This type includes resolved event names and the list of component IDs bound to it.
--- @class SpecialEvent : SpecialEventOpts
---
--- One or more event names.
--- After normalization, this is **always** a list-of-strings.
--- @field name string|string[]
--- @field ids? CompId[] Array of component IDs associated with this event.

--- Input shape for incoming special events before being stored.
--- This type is used when registering new events.
--- It omits `ids` because the store is responsible for managing and appending them.
--- @class SpecialEventInput : SpecialEvent
--- @field ids nil `ids` must be nil. The system will create and populate this field.

--- Stores component dependencies for nvim events
--- ### Example
---   events = {
---     [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for nvim events
---   },
--- @type table<string, CompId[]>
local Events = {}


--- Stores component dependencies for user-defined events
--- ### Example
--    user_events = {
-- 	    [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for user-defined events
--    },
--- @type table<string, CompId[]>
local UserEvents = {}

--- Stores component dependencies for special events
--- ### Example
---   special_events = {
---     {
---       name = "BufEnter",
---       pattern = "*lua"
---       ids = { comp1, comp2 }
---     }
---   }
--- @type SpecialEvent[]
local SpecialEvents = {}



M.inspect = function()
    require("witch-line.utils.notifier").info(vim.inspect({
        Events = Events,
        UserEvents = UserEvents,
        SpecialEvents = SpecialEvents,
    }))
end

--- Compare two string-or-string[] values for equality.
--- Single-element lists are treated as equivalent to bare strings.
---@param a string|string[]
---@param b string|string[]
---@return boolean
local function string_list_equal(a, b)
    local ta, tb = type(a), type(b)

    -- Case 1: Same type
    if ta == tb then
        if ta == "string" then
            return a == b
        elseif ta == "table" then
            --- @cast b table
            return require("witch-line.utils.tbl").array_equal(a, b)
        end
        return false
    end

    -- Case 2: Compare string vs single-element list
    -- Normalize: ensure "list" is always first variable
    local str, list
    if ta == "string" and tb == "table" then
        str, list = a, b
    elseif ta == "table" and tb == "string" then
        str, list = b, a
    else
        return false -- unsupported types
    end

    -- Only equal if list is exactly one element AND matches string
    if #list == 1 then
        return list[1] == str
    end

    return false
end

--- Check whether two special event option tables are functionally identical.
---@param a SpecialEvent
---@param b SpecialEvent
---@return boolean
local same_special_event_opts = function(a, b)
    if a.once ~= b.once then
        return false
    elseif a.remove_when ~= b.remove_when then
        return false
    elseif not string_list_equal(a.pattern, b.pattern) then
        return false
    end
    return true
end

--- Find an existing special event in the store that matches the given entry.
---@param store SpecialEvent[]
---@param e SpecialEvent
---@return integer  Index of the matching entry, or -1 if not found.
local find_matching_special_event = function(store, e)
    for k = 1, #store do
        local existed = store[k]
        if same_special_event_opts(existed, e) then
            return k
        end
    end
    return -1
end

--- Push a component ID into `store[name]`.
--- If the list does not exist, create it before appending.
--- @param store table<string, table> The store table containing event lists.
--- @param event string The name of the list inside the store.
--- @param comp_id CompId The value to append into the list.
local function register_normal_event(store, event, comp_id)
    local list = store[event]

    if list then
        list[#list + 1] = comp_id
        return list
    end

    list = { comp_id }
    store[event] = list
    return list
end

--- Register a component for a special event entry.
--- Merges with existing entries when options match, appending the component id.
---@param store SpecialEvent[]
---@param event SpecialEvent
---@param comp_id CompId
local function register_special_event_entry(store, event, comp_id)
    -- Normalize incoming_names into either string or list-of-strings
    local event_name = event.name
    if type(event_name) == "table" then
        local names = event.name
        if type(names) == "table" then
            event_name = vim.tbl_filter(function(v)
                return v ~= ""
            end, event_name)
            local n = #event_name
            if n == 0 then
                return
            end
            if n == 1 then
                event_name = event_name[1]
            end
        end
    end

    -- Find existing entry index (-1 if not found)
    local entry_index = find_matching_special_event(store, event)
    if entry_index > 0 then
        local entry = store[entry_index]

        -- Append component ID
        entry.ids[#entry.ids + 1] = comp_id

        -- Normalize "name" to list
        local name_list, name_list_size = entry.name or {}, nil
        if type(name_list) == "string" then
            name_list = { name_list }
            name_list_size = 1
        else
            name_list_size = #name_list
        end

        -- Merge event.name into existing list
        if type(event_name) == "table" then
            for i, name in ipairs(event_name) do
                name_list[name_list_size + i] = name
            end
        else
            name_list[name_list_size + 1] = event_name
        end
        entry.name = name_list
    else
        event.name = event_name
        event.ids = { comp_id }
        -- Insert a brand new event entry
        store[#store + 1] = event
    end
end

--- Parse a string-form event definition like "BufEnter *.lua" or "User LazyLoad".
---
--- Accepted formats:
---   "EventName"              → normal event, no pattern
---   "EventName   "           → normal event (trailing space stripped)
---   "EventName Pattern"      → special event with one pattern
---   "EventName P1, P2, P3"   → special event with multiple patterns
---   "User EventName"         → user event (one or more comma-separated names)
---   "  EventName  P1, P2"    → leading/redundant whitespace is stripped
---
--- Whitespace is ignored as padding. Only commas separate tokens within the
--- pattern section.  "*" tokens are silently dropped.
---
--- @param e string    The raw event string to parse.
--- @param comp_id any  Component identifier to associate with the event.
local function register_string_event(e, comp_id)
    local n = #e
    local pos = 1

    -- Strip leading whitespace from the event string.
    -- e.g. "  CursorHold" → "CursorHold"
    while pos <= n and e:byte(pos) == 32 do pos = pos + 1 end
    if pos > n then return end

    -- Find the first space that separates the event name from the pattern part.
    -- Starting at `pos + 1` avoids re-checking the first (non-space) character.
    -- e.g. "BufEnter *.lua"   → space at index 9
    --       "User LazyLoad"   → space at index 5
    --       "CursorHold"      → no space → whole string is the event name
    local space = e:find(" ", pos + 1, true)
    if not space then
        -- Entire string is the event name, no patterns at all.
        register_normal_event(Events, e:sub(pos), comp_id)
        return
    end

    local event_name = e:sub(pos, space - 1)

    -- Strip redundant whitespace between event name and patterns.
    -- e.g. "BufEnter   *.lua" → advance past the extra spaces
    pos = space + 1
    while pos <= n and e:byte(pos) == 32 do pos = pos + 1 end
    if pos > n then
        -- Only whitespace after the event name → no patterns.
        register_normal_event(Events, event_name, comp_id)
        return
    end

    -- The remaining substring contains the comma-separated pattern tokens.
    local s = e:sub(pos)
    local sn = #s

    -- Split on commas, strip surrounding spaces, drop bare "*".
    -- Tokenises `s` into a list.  Always returns (table, count).
    -- Examples:
    --   "*.lua"          → {"*.lua"}, 1
    --   "*.lua, *.py"    → {"*.lua","*.py"}, 2
    --   ",   *.lua ,"    → {"*.lua"}, 1
    --   ""               → {}, 0
    local tokens, nt = {}, 0
    do
        local cp = 1
        while cp <= sn do
            while cp <= sn and s:byte(cp) == 32 do cp = cp + 1 end
            if cp > sn then break end
            local comma = s:find(",", cp, true)
            local te = (comma or sn + 1) - 1
            while te >= cp and s:byte(te) == 32 do te = te - 1 end
            if te >= cp then
                local token = s:sub(cp, te)
                if token ~= "*" then
                    nt = nt + 1
                    tokens[nt] = token
                end
            end
            if not comma then break end
            cp = comma + 1
        end
    end

    if event_name == "User" then
        -- User events: each token is a user-defined event name to fire.
        for i = 1, nt do
            register_normal_event(UserEvents, tokens[i], comp_id)
        end
    else
        -- Other events (BufEnter, InsertCharPre, …):
        -- tokens are file/buffer patterns for the autocmd.
        -- Use a plain string for a single pattern to reduce memory.
        register_special_event_entry(SpecialEvents, {
            name = event_name,
            pattern = nt > 1 and tokens or tokens[1],
        }, comp_id)
    end
end

--- Process a table-based event definition.
--- This function extracts numeric-index event names, normalizes the pattern,
--- and decides whether to register a normal event or a special event.
---
--- Example accepted input:
--- {
---   [1] = "BufEnter",
---   [2] = "BufLeave",
---   pattern = "*.lua",
---   once = true,
--- }
---
--- @param e Component.SpecialEvent The raw event definition supplied by user. May contain:
---   - numeric keys → event names
---   - "pattern" (string|string[]|nil)
---   - "once" (boolean|nil)
--- @param comp_id CompId Component object that contains `id`
local function register_tbl_event(e, comp_id)
    local event_names, event_count, entry, has_opts = {}, 0, {}, false

    for k, v in pairs(e) do
        if type(k) == "number" then
            if type(v) == "string" and v ~= "" then
                event_count = event_count + 1
                event_names[event_count] = v
            end
        elseif k ~= "pattern" then
            entry[k] = v
            has_opts = true
        end
    end
    if event_count == 0 then return end

    -- Normalize pattern: table → filtered list, string → drop if empty/"*"
    local pattern = e.pattern
    if pattern then
        local pt = type(pattern)
        if pt == "table" then
            local new, n = {}, 0
            for i = 1, #pattern do
                local v = pattern[i]
                if v ~= "" and v ~= "*" then
                    n = n + 1
                    new[n] = v
                end
            end
            pattern = n > 1 and new or n == 1 and new[1] or nil
        elseif pt == "string" then
            if pattern == "" or pattern == "*" then pattern = nil end
        else
            error("Invalid pattern in " .. vim.inspect(e))
        end
    end

    -- No options, no pattern → register as normal event
    if not has_opts and not pattern then
        for i = 1, event_count do
            register_normal_event(Events, event_names[i], comp_id)
        end
        return
    end

    entry.name = event_names
    entry.pattern = pattern
    register_special_event_entry(SpecialEvents, entry, comp_id)
end

M.register_events = function(comp)
    local cid, events = comp.id, comp.events
    local t = type(events)
    if t == "string" then
        register_string_event(events, cid)
    elseif t == "table" then
        for i = 1, #events do
            local e = events[i]
            local etype = type(e)
            if etype == "string" then
                register_string_event(e, cid)
            elseif etype == "table" then
                --- @cast e Component.SpecialEvent
                register_tbl_event(e, cid)
            end
        end
    end
end

M.register_vim_resized = function(comp)
    register_normal_event(Events, "VimResized", comp.id)
end

M.register_win_enter = function(comp)
    register_normal_event(Events, "WinEnter", comp.id)
end

--- Initialize autocmds for events, user events, and special events.
--- @param work fun(ids: CompId[], event_info: table<CompId, vim.api.keyset.create_autocmd.callback_args>)
M.on_event = function(work)
    --- @type table<CompId, vim.api.keyset.create_autocmd.callback_args>
    local event_queue = {}

    local function dispatch()
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
        dispatch_debounce = require("witch-line.utils").debounce(dispatch, 110)
        dispatch_debounce(...)
    end

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
        for i = 1, #SpecialEvents do
            local entry = SpecialEvents[i]
            nvim_create_autocmd(entry.name, {
                pattern = entry.pattern,
                once = entry.once,
                group = AUGROUP,
                callback = function(e)
                    for _, id in ipairs(entry.ids) do
                        event_queue[id] = e
                    end
                    dispatch_debounce()

                    local remove_when = entry.remove_when
                    if type(remove_when) == "function" then
                        return remove_when()
                    end
                end,
            })
        end
    end
end

return M
