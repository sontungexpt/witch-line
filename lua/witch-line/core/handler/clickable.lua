local M            = {}

local Prefix       = "WLClickable"
local FuncStore    = {

}

M.assign_func_name = function(value, fun_name)
    return value ~= "" and "%@" .. fun_name .. "@" .. value .. "%X" or ""
end

--- This handler does nothing, just for placeholder
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the highlight cache.
M.on_vim_leave_pre = function(CacheDataAccessor)
    -- do nothing
end

--- Loads the data from cache  from the persistent storage.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the highlight cache.
--- @return function undo function to restore the previous state
M.load_cache       = function(CacheDataAccessor)
    -- do nothing
    return function() end
end


--- Register a function to be called when a clickable component is clicked.
--- @param id CompId string The unique identifier for the clickable component.
--- @param func function The function to be called when the component is clicked.
M.register_on_click = function(id, func)
    FuncStore[id] = func
end

M.init = function()
    for id, func in pairs(FuncStore) do
        _G[Prefix .. id] = func
    end
end


return M
