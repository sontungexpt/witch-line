local vim, type, ipairs, require = vim, type, ipairs, require

local Lifecycle = require("witch-line.runtime.lifecycle")
local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps
local Dependency = require("witch-line.core.dependency")
local DepGraphKind = Dependency.DepGraphKind
local iterate_dependent_ids = Dependency.iterate_dependent_ids

local Proxy = require("witch-line.runtime.proxy")


local M = {}

local update_comp
local update_comp_by_ids



--- Update a component and its dependencies recursively.
--- Hides Visible dependents when the component becomes hidden.
---@param comp ManagedComponent The component to update.
---@param session Session The session to update in.
---@param dep_graph_kind DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
update_comp = function(comp, session, dep_graph_kind, seen)
    seen = seen or {}
    local cid = comp.id
    if seen[cid] then return end
    seen[cid] = true

    local hidden = Lifecycle.update_comp(Proxy.bind(comp, session), session)

    if hidden then
        -- for dep_id in iterate_dependent_ids(DepGraphKind.Visible, cid) do
        --     if not seen[dep_id] then
        --         seen[dep_id] = true
        --         local dep = ManagedComps[dep_id]
        --         if dep then
        --             hide_single_comp(dep)
        --         end
        --     end
        -- end
    end

    --- Update dependent components based on the dependency graph kind.

    --- Special case: always walk All dependents first, then walk the requested kinds.
    -- for dep_id in iterate_dependent_ids(DepGraphKind.All, cid) do
    --     if not seen[dep_id] then
    --         local dep = ManagedComps[dep_id]
    --         if dep then
    --             update_comp(dep, session, DepGraphKind.All, seen)
    --         end
    --     end
    -- end
    -- --- @type DepGraphKind[]
    -- local kinds = type(dep_graph_kind) == "table" and dep_graph_kind or { dep_graph_kind }
    -- for i = 1, #kinds do
    --     local kind = kinds[i]
    --     if kind ~= DepGraphKind.All then
    --         for dep_id in iterate_dependent_ids(kind, cid) do
    --             if not seen[dep_id] then
    --                 local dep = ManagedComps[dep_id]
    --                 if dep then
    --                     update_comp(dep, session, kind, seen)
    --                 end
    --             end
    --         end
    --     end
    -- end
end


--- Update multiple components by IDs through the dep graph.
---@param ids CompId[] The IDs of the components to update.
---@param session Session The session to update in.
---@param dep_graph_kind DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
update_comp_by_ids = function(ids, session, dep_graph_kind, seen)
    seen = seen or {}
    for i = 1, #ids do
        local id = ids[i]
        if not seen[id] then
            local comp = ManagedComps[id]
            if comp then
                update_comp(comp, session, dep_graph_kind, seen)
            end
        end
    end
end

M.update_comp = update_comp
M.update_comp_by_ids = update_comp_by_ids

return M
