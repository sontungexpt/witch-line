local noop = function() end
local next = next

local M = {}

--- @enum DepGraphKind
local DepGraphKind = {
    Event = 1,
    Visible = 2,
    Timer = 3,
    All = 4,
}
M.DepGraphKind = DepGraphKind

---@type table<DepGraphKind, table<CompId, table<CompId, true>>>
local DepGraph = {
    [DepGraphKind.Event] = {},
    [DepGraphKind.Timer] = {},
    [DepGraphKind.Visible] = {},
    [DepGraphKind.All] = {},
}

---@type table<CompId, ManagedComponent>
local ManagedComps = {}

---External access is read-only via proxy.
---@type table<CompId, ManagedComponent>
M.ManagedComps = setmetatable({}, { __index = ManagedComps })

local GLOBAL = 0

--- @type table<integer, CompId[]>
--- Example
--- ```
--- {
---     [GLOBAL] = {  }
---     [winid] = {  }
--- }
--- ```
local Layout = {
    [GLOBAL] = {},
}

--- Removes the layout for a given window ID.
--- @param winid integer
M.remove_layout = function(winid)
    Layout[winid] = nil
end

--- Returns the layout for a given window ID.
--- @param winid? integer
--- @return CompId[]
M.get_layout = function(winid)
    if winid == nil then
        return Layout[GLOBAL]
    end
    return Layout[winid] or Layout[GLOBAL]
end

---@param cid CompId
---@param comp Component
---@return ManagedComponent
M.register = function(cid, comp, winid)
    comp.___loaded = true
    --- @cast comp ManagedComponent
    ManagedComps[cid] = comp

    --- Registers the component in the layout for the given window ID.
    local layout_key = winid or GLOBAL
    local layout = Layout[layout_key]
    if layout == nil then
        Layout[layout_key] = { cid }
    else
        layout[#layout + 1] = cid
    end

    return comp
end



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
    if graph then
        local map = graph[comp_id]
        if map then
            local id = nil
            return function()
                id, _ = next(map, id)
                return id
            end
        end
    end
    return noop
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
