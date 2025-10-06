local M            = {}

local Prefix       = "WLClickable"

--- Assign a function name to a clickable component value.
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
--- @param comp DefaultComponent The component to register the click event for.
M.register_click_event = function(comp)
  local func_name = Prefix .. comp.id
  if not _G[func_name] then
    _G[func_name] = function(...)
      comp.on_click(comp, ...)
    end
  end
  return "v:lua." .. func_name
end



return M
