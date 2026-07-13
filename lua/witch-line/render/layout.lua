local M = {}

local GLOBAL = 0

---@type table<integer, CompId[]>
local Layout = {
    [GLOBAL] = {},
}

--- Removes the layout for a given window ID.
--- @param winid integer
M.remove_layout = function(winid)
    Layout[winid] = nil
end

--- Adds a component to the layout for a given window ID.
--- @param cid CompId
--- @param winid? integer
M.add_to_layout = function(cid, winid)
    local layout_key = winid or GLOBAL
    local layout = Layout[layout_key]
    if layout == nil then
        Layout[layout_key] = { cid }
    else
        layout[#layout + 1] = cid
    end
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

return M
