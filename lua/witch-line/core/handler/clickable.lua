local M            = {}

local PREFIX       = "WL_Clickable_"

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
--- @param comp Component The component to register the click event for.
--- @return string The function name to be used in the component's value. If no valid function is found, returns an empty string.
M.register_click_event = function(comp)
  local on_click=  comp.on_click
  local func_name =  PREFIX .. comp.id

  if type(on_click) == "table" then
    func_name = on_click.name or func_name
    on_click = on_click.callback
  end

  local t = type(on_click)
  if t == "string" then
    return "v:lua." .. on_click
  elseif t == "function"  and not _G[func_name] then
    _G[func_name] = function(...)
      on_click(comp, ...)
    end
    return "v:lua." .. func_name
  end

  require("witch-line.utils.notifier").error("on_click must be a function or a table with callback method")
  return ""
end

return M
