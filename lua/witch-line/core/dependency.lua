local M = {}

---@enum DepGraphKind
M.DepGraphKind = {
    Event = 1,
    Visible = 2,
    Timer = 3,
    All = 4,
}


---@type table<DepGraphKind, table<CompId, table<CompId, true>>>
local DepGraph = {
    [M.DepGraphKind.Event] = {},
    [M.DepGraphKind.Timer] = {},
    [M.DepGraphKind.Visible] = {},
    [M.DepGraphKind.All] = {},
}

local noop = function() end

---@param kind DepGraphKind
---@param source_id CompId
---@param dependent_id CompId
M.link_dependency = function(kind, source_id, dependent_id)
    local graph = DepGraph[kind]
    local deps = graph[source_id]
    if deps == nil then
        graph[source_id] = { [dependent_id] = true }
    else
        deps[dependent_id] = true
    end
end

--- Iterates over dependent component IDs for a given kind and comp_id.
--- @param kind DepGraphKind
--- @param comp_id CompId
--- @return fun(): CompId|nil
M.iterate_dependent_ids = function(kind, comp_id)
    local graph = DepGraph[kind]
    if graph ~= nil then
        local map = graph[comp_id]
        if map ~= nil then
            local id = nil
            return function()
                id, _ = next(map, id)
                return id
            end
        end
    end
    return noop
end

---@param target "dep_graph"|nil
M.inspect = function(target)
    local notifier = require("witch-line.util.notifier")
    if target == "dep_graph" then
        notifier.info(vim.inspect(DepGraph))
    else
        notifier.info(vim.inspect(DepGraph))
    end
end

return M
