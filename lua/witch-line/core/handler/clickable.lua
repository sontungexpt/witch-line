local M            = {}

local PREFIX       = "WL_Clickable_"

--- Assign a function name to a clickable component value.
M.assign_func_name = function(value, fun_name, minwid)
  if minwid then
    return value ~= "" and "%%<" .. minwid .. "@" .. fun_name .. "@" .. value .. "%X" or ""
  else
    return value ~= "" and "%@" .. fun_name .. "@" .. value .. "%X" or ""
  end
end

-- --- This handler does nothing, just for placeholder
-- --- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the highlight cache.
-- M.on_vim_leave_pre = function(CacheDataAccessor)
--     -- do nothing
-- end

-- --- Loads the data from cache  from the persistent storage.
-- --- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the highlight cache.
-- --- @return function undo function to restore the previous state
-- M.load_cache       = function(CacheDataAccessor)
--     -- do nothing
--     return function() end
-- end


--- Register a function to be called when a clickable component is clicked.
--- @param comp Component The component to register the click event for.
--- @return string fun_name The function name to be used in the component's value. If no valid function is found, returns an empty string.
--- @return integer|nil minwid The minwid to be used in the component's value. If no minwid is found, returns nil.
M.register_click_event = function(comp)
  local on_click = comp.on_click
  local func_name = PREFIX .. comp.id


  --- @type  integer|nil|fun(self: ManagedComponent): integer|nil
  local minwid = nil


  if type(on_click) == "table" then
    func_name = on_click.name or func_name
    on_click = on_click.callback
    minwid = on_click.minwid
    if type(minwid) == "function" then
      minwid = minwid(comp)
    end
  end

  local t = type(on_click)
  if t == "string" and _G[on_click] then
    return "v:lua." .. on_click, minwid
  elseif t == "function" then
    if not _G[func_name] then
      _G[func_name] = function(...)
        on_click(comp, ...)
      end
    end
    return "v:lua." .. func_name, minwid
  end

  require("witch-line.utils.notifier").error(
    string.format(
      "Invalid on_click handler for component id '%s'. Expected function or existed function name string, got %s.",
      comp.id,
      t)
  )
  return ""
end

return M
