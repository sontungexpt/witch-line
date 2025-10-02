local M = {}


---@alias es nil|table<string, Id[]>
---@alias EventStore {events: es, user_events: es}
---@type EventStore
local EventStore       = {
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


--- The function to be called before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the stores.
M.on_vim_leave_pre     = function(CacheDataAccessor)
    CacheDataAccessor.set("EventStore", EventStore)
end
--- Load the event and timer stores from the persistent storage.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the stores.
--- @return function undo function to restore the previous state of the stores
M.load_cache           = function(CacheDataAccessor)
    local before_event_store = EventStore

    EventStore = CacheDataAccessor.get("EventStore") or EventStore

    return function()
        EventStore = before_event_store
    end
end

M.inspect = function()
  require("witch-line.utils.notifier").info(vim.inspect(EventStore))
end

--- Register events for components.
---@param comp Component
---@param etype "events" | "user_events"
M.register_events      = function(comp, etype)
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

--- Register the component for VimResized event if it has a minimum screen width.
--- @param comp Component The component to register for VimResized event.
M.register_vim_resized = function(comp)
    local store = EventStore["events"] or {}
    EventStore["events"] = store
    local es = store["VimResized"] or {}
    es[#es + 1] = comp.id
    store["VimResized"] = es
end

--- Initialize the autocmd for events and user events.
--- @param work fun(session_id: SessionId, ids: CompId[], event_info: table<string, any>) The function to execute when an event is triggered. It receives the session_id, component IDs, and event information as arguments.
--- @param event_info_store_name DepGraphId The name of the store to save event information in the
--- @return integer|nil group The ID of the autocmd group created.
--- @return integer|nil events_id The ID of the autocmd for events.
--- @return integer|nil user_events_id The ID of the autocmd for user events.
M.on_event             = function(work, event_info_store_name)
    local events, user_events = EventStore.events, EventStore.user_events
    local id_map = {}

    local emit = require("witch-line.utils").debounce(function()
        local Session = require("witch-line.core.Session")
        Session.run_once(function(session_id)
            Session.new_store(session_id, event_info_store_name, id_map)
            work(session_id, vim.tbl_keys(id_map), id_map)
            id_map = {}
        end)
    end, 100)

    local api = vim.api
    local group, id1, id2 = nil, nil, nil

    if events and next(events) then
        group = group or api.nvim_create_augroup("WitchLineEvents", { clear = true })
        id1 = api.nvim_create_autocmd(vim.tbl_keys(events), {
            group = group,
            callback = function(e)
                for _, id in ipairs(events[e.event]) do
                    id_map[id] = e
                end
                emit()
            end,
        })
    end

    if user_events and next(user_events) then
        group = group or api.nvim_create_augroup("WitchLineEvents", { clear = true })
        id2 = api.nvim_create_autocmd("User", {
            pattern = vim.tbl_keys(user_events),
            group = group,
            callback = function(e)
                for i, id in ipairs(user_events[e.match]) do
                    id_map[id] = e
                end
                emit()
            end,
        })
    end

    return group, id1, id2
end
return M
