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
--- @param dep_store_ids DepStoreId|DepStoreId[]|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
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
--- @param dep_store_ids DepStoreId|DepStoreId[]|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
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
local function registry_refs(comp)
	local link_ref_field = CompManager.link_ref_field
	local ref = comp.ref

	local ref_ids = {}
	if type(ref) == "table" then
		if ref.events then
			link_ref_field(comp, ref.events, DepStoreKey.Event, ref_ids)
		end

		if ref.user_events then
			link_ref_field(comp, ref.user_events, DepStoreKey.Event, ref_ids)
		end

		if ref.timing then
			link_ref_field(comp, ref.timing, DepStoreKey.Timer, ref_ids)
		end

		if ref.hide then
			link_ref_field(comp, ref.hide, DepStoreKey.Display, ref_ids)
		end

		if ref.min_screen_width then
			link_ref_field(comp, ref.min_screen_width, DepStoreKey.Display, ref_ids)
		end
	end

	local inherit = comp.inherit
	if inherit then
		link_ref_field(comp, inherit, DepStoreKey.Event, ref_ids)
		link_ref_field(comp, inherit, DepStoreKey.Timer, ref_ids)
		link_ref_field(comp, inherit, DepStoreKey.Display, ref_ids)
	end

	-- Pull missing dependencies from the component's ref field
	local Component = require("witch-line.core.Component")
	for id, _ in pairs(ref_ids) do
		if not CompManager.is_existed(id) then
			local c = Component.require_by_id(id)
			if c then
				M.registry_abstract_component(c, id)
			end
		end
	end
end

--- Register conditions for a component.
--- @param comp Component The component to register conditions for.
local function registry_update_conditions(comp)
	if comp.timing then
		Timer.registry_timer(comp)
	end

	if comp.events then
		Event.registry_events(comp, "events")
	end

	if comp.min_screen_width then
		Event.registry_vim_resized(comp)
	end

	if comp.user_events then
		Event.registry_events(comp, "user_events")
	end

	registry_refs(comp)
end

--- Register a component by its type.
--- @param comp Component|string The component to register.
--- @param i integer The index of the component in the registry.
--- @param urgents Id[] The list of components that should be updated immediately.
--- @param parent_id Id|nil The ID of the component to inherit from, if any.
function M.registry_comp_by_type(comp, i, urgents, parent_id)
	local type_c = type(comp)
	if type_c == "string" then
		-- special case for string components
		if comp == "%=" then
			M.registry_str_comp(comp, i, urgents)
			return
		elseif comp == "" then
			return
		end
		local c = require("witch-line.core.Component").require(comp)
		if not c then
			M.registry_str_comp(comp, i, urgents)
			return
		elseif parent_id and not c.inherit then
			rawset(c, "inherit", parent_id)
		end
		M.registry_comp(c, i, urgents)
	elseif type_c == "table" and next(comp) then
		-- support user configs
		local comp_path = comp[0]
		if type(comp_path) == "string" then
			local c = require("witch-line.core.Component").require(comp_path)
			if not c then
				return
			else
				---@diagnostic disable-next-line: param-type-mismatch
				comp = require("witch-line.core.Component").overrides(c, comp[1])
			end
		end

		if parent_id and not comp.inherit then
			rawset(comp, "inherit", parent_id)
		end

		M.registry_comp(comp, i, urgents)
	end
end

--- Register a component in the statusline.
--- @param comp Component
--- @param id Id|integer The ID to assign to the component.
--- @param urgents Id[] The list of components that should be updated immediately.
--- @return nil
function M.registry_comp(comp, id, urgents)
	if comp._loaded then
		return comp.id
	end

	-- If is a list it just a wrapper for a list components
	if not vim.islist(comp) then
		-- Every component is treat as an abstract component
		-- The difference is that abstract components are not registered in the statusline
		id = M.registry_abstract_component(comp, id)

		local update = comp.update
		if update then
			if comp.lazy == false then
				urgents[#urgents + 1] = id
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

	for i, child in ipairs(comp) do
		M.registry_comp_by_type(child, i, urgents, comp.id)
		comp[i] = nil -- Clear the child to avoid memory leaks
	end

	return comp.id
end

--- Compare two strings for sorting in the registry.
--- @param comp string The string to compare.
--- @param i integer The index of the string in the registry.
--- @param urgents table<Component> The list of components that should be updated immediately.
---@diagnostic disable-next-line: unused-local
function M.registry_str_comp(comp, i, urgents)
	if comp ~= "" then
		statusline.freeze(statusline.push(comp))
	end
	return comp
end

--- Register a component in the statusline.
--- @param comp Component
--- @param id Id The ID to assign to the component.
--- @return Id The ID of the registered component.
function M.registry_abstract_component(comp, id)
	if not comp._abstract then
		id = CompManager.register(comp, id)

		if comp.init then
			comp.init(comp)
		end

		registry_update_conditions(comp)
		rawset(comp, "_abstract", true)
	end

	return comp.id
end

--- Setup the statusline with the given configurations.
--- @param configs Config|nil  The configurations for the statusline.
--- @param cached boolean|nil Whether the setup is from a cached state.
M.setup = function(configs, cached)
	local urgents = CacheMod.get("Urgents") or {}

	if not cached then
		configs = configs or require("witch-line.config").get()

		local abstract = configs.abstract

		for i = 1, #abstract do
			--- @type Component|string|nil
			local c = abstract[i]
			if type(c) == "string" then
				c = require("witch-line.core.Component").require(c)
			end

			if type(c) == "table" and c.id then
				M.registry_abstract_component(c, i)
			else
				error("Abstract component must be a table with an 'id' field: " .. tostring(c))
			end
		end

		local comps = configs.components
		---@cast comps NestedComponent
		for i = 1, #comps do
			M.registry_comp_by_type(comps[i], i, urgents)
		end
	else
		for _, comp in CompManager.iterate_comps() do
			if comp.init then
				comp.init(comp)
			end
		end
	end


	Event.on_event(function(session_id, ids)
		M.update_comp_graph_by_ids(ids, session_id, DepStoreKey.Event, {})
		statusline.render()
	end, DepStoreKey.EventInfo)

	Timer.on_timer_trigger(function(session_id, ids)
		M.update_comp_graph_by_ids(ids, session_id, DepStoreKey.Timer, {})
		statusline.render()
	end)



	if urgents[1] then
		local Session = require("witch-line.core.Session")
		Session.run_once(function(session_id)
			M.update_comp_graph_by_ids(urgents, session_id, {
				DepStoreKey.Event,
				DepStoreKey.Timer,
			}, {})
		end)
	end

	if not cached then
		CompManager.cache_ugent_comps(urgents)
	end
	statusline.render()
end

return M
