local next = next

local M = {}

--------------------------------------------------------------------------------
-- Dependency graph
--------------------------------------------------------------------------------
--- @enum DepGraphKind
local DepGraphKind = {
    Visible = 1,
    Event = 2,
    Timer = 3,
}
M.DepGraphKind = DepGraphKind

---@type table<DepGraphKind, table<CompId, table<CompId, true>>>
local DepGraph = {
    [DepGraphKind.Event] = {},
    [DepGraphKind.Timer] = {},
    [DepGraphKind.Visible] = {},
}

---@type table<CompId, Component>
local ManagedComps = {}

---External access is read-only via proxy.
---@type table<CompId, Component>
M.ManagedComps = setmetatable({}, { __index = ManagedComps })

---@param cid CompId
---@param comp Component
---@return ManagedComponent
M.register = function(cid, comp)
    ManagedComps[cid] = comp
    comp.___loaded = true
    return comp
end


---@param kind DepGraphKind
---@param source_id CompId
---@param dependent_id CompId
M.link_dependency = function(kind, source_id, dependent_id)
    local graph = DepGraph[kind]
    local deps = graph[source_id]
    if deps then
        deps[dependent_id] = true
    else
        graph[source_id] = { [dependent_id] = true }
    end
end

--- Iterates over dependent component IDs for a given kind and comp_id.
--- @param kind DepGraphKind
--- @param comp_id CompId
--- @return fun(table, any): CompId|nil
--- @return table|nil
--- @return nil
M.iterate_dependent_ids = function(kind, comp_id)
    local map = DepGraph[kind][comp_id]
    if map then
        return next, map, nil
    end
    return function() return nil end
end

M.inspect = function(target)
    local notifier = require("witch-line.util.notifier")
    if target == "dep_graph" then
        notifier.info("---- DepGraph ----\n" .. vim.inspect(DepGraph))
    elseif target == "comps" then
        notifier.info("---- ManagedComps ----\n" .. vim.inspect(ManagedComps))
    else
        notifier.info(vim.inspect({
            DepGraph = DepGraph,
            Comps = ManagedComps,
        }))
    end
end
return M
