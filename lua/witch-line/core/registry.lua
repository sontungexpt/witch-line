local M = {}

---@type table<CompId, ManagedComponent>
local ManagedComps = {}

---External access is read-only via proxy.
---@type table<CompId, ManagedComponent>
M.ManagedComps = setmetatable({}, { __index = ManagedComps })

--- @param cid CompId
--- @param comp Component
--- @return ManagedComponent
M.register = function(cid, comp)
    comp.___loaded = true
    --- @cast comp ManagedComponent
    ManagedComps[cid] = comp
    return comp
end

---@param target "dep_graph"|"comps"
M.inspect = function(target)
    local notifier = require("witch-line.util.notifier")
    if target == "dep_graph" then
        Dependency.inspect(target)
    elseif target == "comps" then
        notifier.info(vim.inspect(ManagedComps))
    else
        notifier.info(vim.inspect({
            DepGraph = "(see dep_graph)",
            Comps = ManagedComps,
        }))
    end
end

return M
