--- Component factory for building test components with unique IDs.
--- Avoids cache collisions between tests via auto-incrementing counters.

local M = {}

local _counter = 0

--- Build a minimal component with unique ID.
---@param overrides? table Fields to merge onto the default.
---@return ManagedComponent
function M.make_comp(overrides)
    _counter = _counter + 1
    return vim.tbl_extend("force", {
        id = "test.comp." .. _counter,
        ___builtin = true,
        update = function() return "" end,
        renderable = true,
    }, overrides or {})
end

--- Build a parent-child component pair.
---@param parent_fields? table Fields for the parent.
---@param child_fields? table Fields for the child.
---@return ManagedComponent parent, ManagedComponent child
function M.make_pair(parent_fields, child_fields)
    local parent = M.make_comp(parent_fields)
    local child = M.make_comp(vim.tbl_extend("force", {
        ___parent_id = parent.id,
    }, child_fields or {}))
    return parent, child
end

--- Build a 3-level chain: grandparent → parent → child.
---@param gp_fields? table
---@param mid_fields? table
---@param leaf_fields? table
---@return ManagedComponent gp, ManagedComponent mid, ManagedComponent leaf
function M.make_chain(gp_fields, mid_fields, leaf_fields)
    local gp = M.make_comp(gp_fields)
    local mid = M.make_comp(vim.tbl_extend("force", {
        ___parent_id = gp.id,
    }, mid_fields or {}))
    local leaf = M.make_comp(vim.tbl_extend("force", {
        ___parent_id = mid.id,
    }, leaf_fields or {}))
    return gp, mid, leaf
end

--- Build a deep chain of n components.
---@param depth number Number of components in the chain.
---@param base_fields? table Fields applied to every component.
---@return ManagedComponent[] components Array from root to leaf.
function M.make_deep_chain(depth, base_fields)
    local comps = {}
    for i = 1, depth do
        local fields = vim.tbl_extend("force", base_fields or {}, {})
        if i > 1 then
            fields.___parent_id = comps[i - 1].id
        end
        comps[i] = M.make_comp(fields)
    end
    return comps
end

--- Reset the internal counter (useful for deterministic test IDs).
function M.reset_counter()
    _counter = 0
end

return M
