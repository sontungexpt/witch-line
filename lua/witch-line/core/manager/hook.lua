local require, type = require, type
local Manager = require("witch-line.core.manager")
local lookup_ref_value, lookup_inherited_value = Manager.lookup_ref_value, Manager.lookup_inherited_value

local Hook = {}

--- Hook to get a context for a component
--- @param comp Component The component to get the context for
--- @param session_id SessionId The session id to get the context for
--- @return table context The context for the component
Hook.use_context = function(comp, session_id)
  local context = lookup_ref_value(comp, "context", session_id, {})
  if type(context) == "string" then
    return require(context)
  end
  return context
end

--- Hook to get static data for a component
--- @param comp Component The component to get the static data for
--- @return table static The static data for the component
Hook.use_static = function(comp)
  local static = lookup_inherited_value(comp, "static", {})
  if type(static) == "string" then
    return require(static)
  end
  return static
end

return Hook
