local vim, type, ipairs, pairs, rawset, require = vim, type, ipairs, pairs, rawset, require

local CacheMod = require("witch-line.cache")
local Timer = require("witch-line.core.handler.timer")
local Event = require("witch-line.core.handler.event")

local M = {}

---@enum DepStoreKey
local DepStoreKey = {
	Display = 1,
	Event = 2,
	EventInfo = 3,
	Timer = 4,
}

local statusline = require("witch-line.core.statusline")
local CompManager = require("witch-line.core.CompManager")


--- Clear the value of a component in the statusline.
--- @param c Component The component to clear.
local clear_comp_value = function(c)
	local indices = c._indices
	if not indices then
		return
	end

	statusline.bulk_set(indices, "")
	if type(c.left) == "string" then
		statusline.bulk_set_sep(indices, "", -1)
	end
	if type(c.right) == "string" then
		statusline.bulk_set_sep(indices, "", 1)
	end
	rawset(c, "_hidden", true) -- Reset hidden state
end

--- Update a component and its value in the statusline.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
local function update_comp(comp, session_id)
	local Component = require("witch-line.core.Component")

	if comp.inherit and not Component.has_parent(comp) then
		local parent = CompManager.get_comp(comp.inherit)
		if parent then
			Component.inherit_parent(comp, parent)
		end
	end

	local static = CompManager.get_static(comp)
	local ctx = CompManager.get_context(comp, session_id, static)

	if type(comp.pre_update) == "function" then
		comp.pre_update(comp, ctx, static, session_id)
	end

	local min_screen_width = CompManager.get_min_screen_width(comp, session_id, ctx, static)
	local hidden = type(min_screen_width) == "number" and vim.o.columns > min_screen_width
		or CompManager.should_hidden(comp, session_id, ctx, static)

	if hidden then
		clear_comp_value(comp)
		return ""
	end

	local value = Component.evaluate(comp, ctx, static)
	if value == "" then
		clear_comp_value(comp)
		return ""
	end

	Component.update_style(comp, session_id, ctx, static)

	local indices = comp._indices
	if not indices then
		require("witch-line.utils.notifier").
			error("Component " .. comp.id .. " has no indices set. Ensure it has been registered properly.")
		return
	end

	local add_hl_name = require("witch-line.core.highlight").add_hl_name
	statusline.bulk_set(indices, add_hl_name(value, comp._hl_name))

	local left, right = Component.evaluate_left_right(comp, ctx, static)
	if left then
		statusline.bulk_set_sep(indices, add_hl_name(left, comp._left_hl_name), -1)
	end
	if right then
		statusline.bulk_set_sep(indices, add_hl_name(right, comp._right_hl_name), 1)
	end
	rawset(comp, "_hidden", false) -- Reset hidden state

	if type(comp.post_update) == "function" then
		comp.post_update(comp, ctx, static, session_id)
	end
	return value
end
M.update_comp = update_comp

--- Update a component and its dependencies.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_store_ids DepGraphId|DepGraphId[]|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
function M.update_comp_graph(comp, session_id, dep_store_ids, seen)
	seen = seen or {}
	local id = comp.id
	if seen[id] then
		return -- Avoid infinite recursion
	end
	seen[id] = true
	local updated_value = update_comp(comp, session_id)

	if updated_value == "" then
		for dep_id, dep_comp in CompManager.iterate_dependencies(DepStoreKey.Display, id) do
			seen[dep_id] = true
			clear_comp_value(dep_comp)
		end
	end

	if dep_store_ids then
		if type(dep_store_ids) ~= "table" then
			dep_store_ids = { dep_store_ids }
		end
		for _, ds_id in ipairs(dep_store_ids) do
			for dep_id, dep_comp in CompManager.iterate_dependencies(ds_id, id) do
				if not seen[dep_id] then
					M.update_comp_graph(dep_comp, session_id, dep_store_ids, seen)
				end
			end
		end
	end
end

--- Update multiple components by their IDs.
--- @param ids CompId[] The IDs of the components to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_store_ids DepGraphId|DepGraphId[]|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_graph_by_ids = function(ids, session_id, dep_store_ids, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		if not seen[id] then
			local comp = CompManager.get_comp(id)
			if comp then
				M.update_comp_graph(comp, session_id, dep_store_ids, seen)
			end
		end
	end
end

--- Link dependencies for a component based on its ref and inherit fields.
--- @param comp Component The component to link dependencies for.
local function bind_dependencies(comp)
	local link_ref_field = CompManager.link_ref_field
	local ref = comp.ref

	if type(ref) == "table" then
		if ref.events then
			link_ref_field(comp, ref.events, DepStoreKey.Event)
		end

		if ref.user_events then
			link_ref_field(comp, ref.user_events, DepStoreKey.Event)
		end

		if ref.timing then
			link_ref_field(comp, ref.timing, DepStoreKey.Timer)
		end

		if ref.hide then
			link_ref_field(comp, ref.hide, DepStoreKey.Display)
		end

		if ref.min_screen_width then
			link_ref_field(comp, ref.min_screen_width, DepStoreKey.Display)
		end
	end

	local inherit = comp.inherit
	if inherit then
		link_ref_field(comp, inherit, DepStoreKey.Event)
		link_ref_field(comp, inherit, DepStoreKey.Timer)
		link_ref_field(comp, inherit, DepStoreKey.Display)
	end
end




--- Register conditions for a component.
--- @param comp Component The component to register conditions for.
local function bind_update_conditions(comp)
	if comp.timing then
		Timer.register_timer(comp)
	end

	if comp.events then
		Event.register_events(comp, "events")
	end

	if comp.min_screen_width then
		Event.register_vim_resized(comp)
	end

	if comp.user_events then
		Event.register_events(comp, "user_events")
	end
end

--- Register an abstract component that is not directly rendered in the statusline.
--- These components can be used as dependencies for other components.
--- @param comp Component The abstract component to register.
--- @return CompId The ID of the registered component.
function M.register_abstract_component(comp)
	if not comp._abstract then
		local id = CompManager.register(comp)

		if comp.init then
			CompManager.queue_initialization(id)
		end

		bind_update_conditions(comp)
		bind_dependencies(comp)

		-- Pull missing dependencies from the component's ref field
		local Component = require("witch-line.core.Component")
		for dep_id in CompManager.iterate_all_dependency_ids(id) do
			if not CompManager.is_existed(dep_id) then
				local c = Component.require_by_id(dep_id)
				if c then
					M.register_abstract_component(c)
				end
			end
		end

		rawset(comp, "_abstract", true)
		return id
	end
	return comp.id
end

--- Register a component node, which may include nested components.
--- @param comp Component The component to register.
--- @return Component The registered component. Nil if registration failed.
local function register_component(comp)
	-- Avoid recursion for already loaded components
	if comp._loaded then
		return comp
	end


	-- Example for this case: comp = {
	--  [0] = "mode",
	--  events = { "VimLeavePre" },
	-- }
	-- And the mode component is {
	--   id = "mode",
	--   events = { "ModeChanged" },
	--   update = function() ... end,
	-- 	...}
	-- So the final component will be {
	--   id = "mode",
	--   events = { "VimLeavePre" },
	--   update = function() ... end,
	--   ...
	-- }
	-- If a component is made base on other component with some overrided fields
	local comp_path = comp[0]
	if type(comp_path) == "string" then
		local c = require("witch-line.core.Component").require(comp_path)
		-- If c is nil, assume that the user is trying to add the [0] field for other purpose
		-- so we just ignore it
		if c then
			comp = require("witch-line.core.Component").overrides(c, comp)
		end
	end

	-- If is a list it just a wrapper for a list components
	-- so we just register its children
	-- Example: { "MyComponent", { child1, child2, ... } }
	-- Example: { { child1, child2, ... } }
	-- Example: { child1, child2, ... }
	if not vim.islist(comp) then
		-- Every component is treat as an abstract component
		-- The difference is that abstract components are not rendered directly
		-- but they can be dependencies of other components
		-- while normal components are rendered in the statusline
		-- This allows users to define components that are not rendered directly
		-- but can be used as dependencies for other components

		-- Abstract registration
		local id = M.register_abstract_component(comp)

		-- Add to statusline if renderable
		local update = comp.update
		if update then
			if comp.lazy == false then
				CompManager.mark_emergency(id)
			end

			if comp.left then
				statusline.push("")
			end

			local st_idx = type(update) == "string" and statusline.push(update) or statusline.push("")
			local indices = comp._indices
			if not indices then
				rawset(comp, "_indices", { st_idx })
			else
				indices[#indices + 1] = st_idx
			end

			if comp.right then
				statusline.push("")
			end
		end
		rawset(comp, "_loaded", true) -- Mark the component as loaded
	end

	return comp
end

--- Register a literal string component in the statusline.
--- @param comp LiteralComponent The string component to register.
local function register_literal_comp(comp)
	if comp ~= "" then
		statusline.freeze(statusline.push(comp))
	end
	return comp
end

--- Register a component by its type.
--- @param comp Component The component to register.
--- @param parent_id CompId|nil The ID of the parent component, if any.
--- @return Component|LiteralComponent|nil comp The registered component. Nil if registration failed.
function M.register_combined_component(comp, parent_id)
	local kind = type(comp)
	if kind == "string" then
		local c = require("witch-line.core.Component").require(comp)
		if c then
			comp = register_component(c)
		end
		return register_literal_comp(comp)
	elseif kind == "table" and next(comp) then
		comp = register_component(comp)
	else
		-- Invalid component type
		return nil
	end

	-- If the component is not a literal component then it will drop by here

	-- Set parent inheritance if applicable
	if parent_id and not comp.inherit then
		rawset(comp, "inherit", parent_id)
	end

	for i, child in ipairs(comp) do
		M.register_combined_component(child, comp.id)
		comp[i] = nil -- Remove child to avoid duplication
	end
	return comp
end

--- Setup the statusline with the given configurations.
--- @param configs Config|nil  The configurations for the statusline.
--- @param cached boolean|nil Whether the setup is from a cached state.
M.setup = function(configs, cached)
	if not cached then
		local abstract = configs.abstract
		for i = 1, #abstract do
			local c = abstract[i]
			if type(c) == "string" then
				---@diagnostic disable-next-line
				c = require("witch-line.core.Component").require(c)
			end
			if type(c) == "table" and c.id then
				M.register_abstract_component(c)
			else
				error("Abstract component must be a component with an 'id' field: " .. tostring(c))
			end
		end

		local comps = configs.components
		for i = 1, #comps do
			M.register_combined_component(comps[i])
		end
	end

	for _, comp in CompManager.iter_pending_init_components() do
		comp.init(comp)
	end

	local Session = require("witch-line.core.Session")
	Session.run_once(function(session_id)
		local Session = require("witch-line.core.Session")
		Session.run_once(function(session_id)
			M.update_comp_graph_by_ids(urgents, session_id, {
				DepStoreKey.Event,
				DepStoreKey.Timer,
			}, {})
		end)
	end)


	Event.on_event(function(session_id, ids)
		M.update_comp_graph_by_ids(ids, session_id, DepStoreKey.Event, {})
		statusline.render()
	end, DepStoreKey.EventInfo)

	Timer.on_timer_trigger(function(session_id, ids)
		M.update_comp_graph_by_ids(ids, session_id, DepStoreKey.Timer, {})
		statusline.render()
	end)

	statusline.render()
end

return M
