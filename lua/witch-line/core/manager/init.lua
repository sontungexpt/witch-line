local next = next
local Component = require("witch-line.core.Component")

local M = {}

--- @enum DepGraphKind
local DepGraphKind = {
    Visible = 1,
    Event = 2,
    Timer = 3,
}

M.DepGraphKind = DepGraphKind
M.DepGraphKinds = { DepGraphKind.Visible, DepGraphKind.Event, DepGraphKind.Timer }

--- Three-way dependency graph.
--- Structure: { [source_id] = { [dependent_id] = true } }
--- One such table per DepGraphKind, pre-allocated at load.
---
--- EventGraph example:
---   { ["diagnostic"] = { ["my_diag"] = true },   -- my_diag inherits diagnostic
---     ["git.branch"] = { ["ext"] = true },        -- ext ref.events = "git.branch"
---   }
--- TimerGraph example:
---   { ["diagnostic"] = { ["my_diag"] = true },   -- my_diag inherits diagnostic
---     ["battery"] = { ["ext"] = true },           -- ext ref.timing = "battery"
---   }
--- VisibleGraph example:
---   { ["hidden_base"] = { ["child"] = true },     -- child ref.hidden = "hidden_base"
---   }
---
---@type table<DepGraphKind, table<CompId, table<CompId, true>>>
local DepGraph = {
    [DepGraphKind.Event] = {},
    [DepGraphKind.Timer] = {},
    [DepGraphKind.Visible] = {},
}


---@type table<CompId, ManagedComponent>
local ManagedComps = {}

--- @type CompId[]
local EmergencyIds = {}

M.get_emergency_ids = function()
    return EmergencyIds
end

M.mark_emergency = function(id)
    EmergencyIds[#EmergencyIds + 1] = id
end

M.iterate_comps = function()
    return pairs(ManagedComps)
end

M.register = function(comp)
    local id = Component.setup(comp)
    ManagedComps[id] = comp
    return comp
end

M.is_existed = function(id)
    return ManagedComps[id] ~= nil
end

--- Get the component for the given id, if it exists.
--- @param id CompId The component id to retrieve.
--- @return ManagedComponent|nil The component, or `nil` if not found.
M.get_comp = function(id)
    return ManagedComps[id]
end

--- Register a dependency edge: when `source_id` fires, `dependent_id` is also queued.
--- @param kind DepGraphKind The kind of graph to link in.
--- @param source_id CompId The id of the component that depends on `dependent_id`.
--- @param dependent_id CompId The id of the component that is depended on by `source_id`.
M.link_dependency = function(kind, source_id, dependent_id)
    local graph = DepGraph[kind]
    local deps = graph[source_id] or {}
    deps[dependent_id] = true
    graph[source_id] = deps
end

--- Iterate over registered dependents of `comp_id` in the given graph kind.
--- @param kind DepGraphKind The kind of graph to iterate over.
--- @param comp_id CompId The id of the component to iterate dependents of.
--- @return fun(): CompId|nil A function that returns the next dependent id, or `nil` when done.
M.iterate_dependents = function(kind, comp_id)
    local map = DepGraph[kind][comp_id] or {}
    local dependent_id = nil
    return function()
        dependent_id = next(map, dependent_id)
        return dependent_id
    end
end


M.inspect = function(target)
    local notifier = require("witch-line.utils.notifier")
    if target == "dep_graph" then
        notifier.info("DepGraph:\n" .. vim.inspect(DepGraph))
    elseif target == "comps" then
        notifier.info("ManagedComps:\n" .. vim.inspect(ManagedComps))
    else
        notifier.info(vim.inspect({
            DepGraph = DepGraph,
            EmergencyIds = EmergencyIds,
            Comps = ManagedComps,
        }))
    end
end

return M
