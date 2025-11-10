local require, type = require, type
local Manager = require("witch-line.core.manager")
local lookup_dynamic_value, lookup_plain_value, plain_inherit =
	Manager.lookup_dynamic_value, Manager.lookup_plain_value, Manager.plain_inherit

--- @class Hook
local Hook = {}

--- Hook to get a context for a component
--- @param comp Component The component to get the context for
--- @param session_id SessionId The session id to get the context for
--- @return table|nil context The context for the component
Hook.use_context = function(comp, session_id)
	local result = lookup_dynamic_value(comp, "context", session_id)
	if not result then
		return nil
	end
	local context = result[1]
	if type(context) == "string" then
		return require(context)
	end
	return context
end

do
	local merge_static = function(child, parent)
		return vim.tbl_deep_extend("keep", child or {}, parent)
	end

	--- Hook to get static data for a component
	--- @param comp Component The component to get the static data for
	--- @return nil|table static The static data for the component
	Hook.use_static = function(comp)
		return plain_inherit(comp, "static", merge_static)
	end
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
	local style = lookup_dynamic_value(comp, "style", session_id, {})
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

Hook.use_plain_field = function(comp_id, field_name)
	local comp = Manager.get_comp(comp_id)
	if comp then
		return lookup_plain_value(comp, field_name, {})
	end
	return nil
end

Hook.use_dynamic_field = function(comp_id, field_name, sid)
	local comp = Manager.get_comp(comp_id)
	if comp then
		return lookup_dynamic_value(comp, field_name, sid, {})
	end
	return nil
end

return Hook
