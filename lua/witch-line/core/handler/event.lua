local M = {}


---@alias es nil|table<string, Id[]>
---@alias EventStore {events: es, user_events: es}
---@type EventStore
local EventStore   = {
    -- Stores component dependencies for events
    -- Only init if needed
    -- events = {
    -- 	-- [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for nvim events
    -- },

    -- -- -- Stores component dependencies for user events
    -- Only init if needed
    -- user_events = {
    -- 	-- [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for user-defined events
    -- },
}

M.on_vim_leave_pre = function()
    CacheMod.cache(EventStore, "EventStore")
end
--- Load the event and timer stores from the persistent storage.
--- @param Cache Cache The cache module to use for loading the stores.
--- @return function undo function to restore the previous state of the stores
M.load_cache       = function(Cache)
    local before_event_store = EventStore

    EventStore = Cache.get("EventStore") or EventStore

    return function()
        EventStore = before_event_store
    end
end

--- Register events for components.
---@param comp Component
---@param etype "events" | "user_events"
M.registry_events  = function(comp, etype)
    local es = comp[etype]
    if type(es) == "table" then
        local es_size = #es
        if es_size > 0 then
            local store = EventStore[etype] or {}
            EventStore[etype] = store
            for i = 1, es_size do
                local e = es[i]
                local store_e = store[e] or {}
                store_e[#store_e + 1] = comp.id
                store[e] = store_e
            end
        end
    end
end

--- Initialize the autocmd for events and user events.
--- @return integer|nil group The ID of the autocmd group created.
--- @return integer|nil events_id The ID of the autocmd for events.
--- @return integer|nil user_events_id The ID of the autocmd for user events.
M.on_event         = function(work)
    local events, user_events = EventStore.events, EventStore.user_events
    local equeue = {}

    local on_event_debounce = require("witch-line.utils").debounce(function(stack, key)
        local Session = require("witch-line.core.Session")
        Session.run_once(function(id)
            for etype, es in pairs(equeue) do
                local store = EventStore[etype]
                if store then
                    for i = 1, #es do
                        local e = es[i]
                        local ids = store[e]
                        if ids then
                            for i = stack_size, 1, -1 do
                                local ids = store[stack[i]]
                                stack[i] = nil

                                if ids then
                                    M.update_comp_graph_by_ids(ids, id, DepStoreKey.Event, seen)
                                end
                            end
                            statusline.render()
                        end
                    end
                end
            end
        end)
    end, 100)

    local api = vim.api
    local group, id1, id2 = nil, nil, nil

    if events and next(events) then
        group = group or api.nvim_create_augroup("WitchLineEvents", { clear = true })
        equeue.events = {}
        id1 = api.nvim_create_autocmd(vim.tbl_keys(events), {
            group = group,
            callback = function(e)
                table.insert(equeue.events, e.event)
                on_event_debounce(equeue.events, "events")
            end,
        })
    end

    if user_events and next(user_events) then
        group = group or api.nvim_create_augroup("WitchLineEvents", { clear = true })
        equeue.user_events = {}
        id2 = api.nvim_create_autocmd("User", {
            pattern = vim.tbl_keys(user_events),
            group = group,
            callback = function(e)
                table.insert(equeue.user_events, e.match)
                on_event_debounce(equeue.user_events, "user_events")
            end,
        })
    end

    return group, id1, id2
end
return M
