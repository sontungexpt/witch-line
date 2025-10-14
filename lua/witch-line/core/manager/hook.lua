local require, type = require, type
local Manager = require("witch-line.core.manager")
local lookup_ref_value, lookup_inherited_value = Manager.lookup_ref_value, Manager.lookup_inherited_value

--- @class Hook
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

--- Hook to get event info for a component
--- @param comp Component The component to get the event info for
--- @return vim.api.keyset.create_autocmd.callback_args|nil event_info The event info for the component. Nil if not updated by any event
Hook.use_event_info = function(comp, session_id)
  -- Not use frequently, so require here for lazy load
  return require("witch-line.core.manager.event").get_event_info(comp, session_id)
end

--- Hook to get style for a component
--- When the style is updated, it will automatically update the highlight too.
--- @param comp Component The component to get the style for
--- @param session_id SessionId The session id to get the style for
--- @return CompStyle style The style for the component
Hook.use_style = function(comp, session_id)
  local style = lookup_ref_value(comp, "style", session_id, {})
  return setmetatable({}, {
    __index = style,
    __newindex = function(_, k, v)
        style[k] = v
        local hl_name = comp._hl_name
        if hl_name then
          require("witch-line.core.highlight").highlight(hl_name, style)
        end
    end,
  })
end

return Hook
