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

M.inspect = function()
    local notifier = require("witch-line.util.notifier")
    notifier.info(vim.inspect(ManagedComps))
    return ManagedComps
end

return M
