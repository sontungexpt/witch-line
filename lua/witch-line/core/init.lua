local vim, type, ipairs, pairs, rawset, require = vim, type, ipairs, pairs, rawset, require
local api, uv = vim.api, vim.uv or vim.loop

local CacheMod = require("witch-line.cache")
local M = {}

local TIMER_TICK = 1000 -- 1 second

---@enum DepStoreKey
local DepStoreKey = {
	Display = 1,
	Event = 2,
	Timer = 3,
}

local statusline = require("witch-line.core.statusline")
local CompManager = require("witch-line.core.CompManager")

local manage, get_comp, link_ref_field, get_dep_store, get_raw_dep_store, get_context, get_static, should_hidden =
	CompManager.register,
	CompManager.get_comp,
	CompManager.link_ref_field,
	CompManager.get_dep_store,
	CompManager.get_raw_dep_store,
	CompManager.get_context,
	CompManager.get_static,
	CompManager.should_hidden

---@alias es nil|table<string, Id[]>
---@alias EventStore {events: es, user_events: es}
---@type EventStore
local EventStore = {
	-- Stores component dependencies for events
	-- Only init if needed
	-- events = {
	-- 	-- [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for nvim events
	-- },

	-- -- -- Stores component dependencies for user events
	-- Only init if needed
	-- user_events = {
	-- 	-- [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for user-defined events
	-- },
}

---@alias TimerStore table<uinteger , Id[] | {timer: any}>
---@type TimerStore
local TimerStore = {
	-- Stores component IDs for timers
	-- Stores component IDs for timers with a specific interval
	-- [interval] = {
	--   [timer] = uv.new_timer(), -- Timer object for the interval
	--   comp_id1,
	--   comp_id2,
	--   ...
	--   ...
	-- }
}

M.on_vim_leave_pre = function()
	CacheMod.cache(EventStore, "EventStore")
	CacheMod.cache(TimerStore, "TimerStore")
end

--- Load the event and timer stores from the persistent storage.
--- @return function undo function to restore the previous state of the stores
M.load_cache = function()
	local before_event_store = EventStore
	local before_timer_store = TimerStore

	EventStore = CacheMod.get("EventStore") or EventStore
	TimerStore = CacheMod.get("TimerStore") or TimerStore

	return function()
		EventStore = before_event_store

		for _, ids in pairs(TimerStore) do
			if ids.timer then
				ids.timer:stop() -- Stop the timer if it exists
				ids.timer:close() -- Close the timer to free resources
			end
		end

		TimerStore = before_timer_store
	end
end

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

--- Update a component and its dependencies.jj
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
local function update_comp(comp, session_id)
	local Component = require("witch-line.core.Component")

	if comp.inherit and not Component.has_parent(comp) then
		local parent = get_comp(comp.inherit)
		if parent then
			Component.inherit_parent(comp, parent)
		end
	end

	local static = get_static(comp)
	local ctx = get_context(comp, session_id, static)
	local min_screen_width = Component.min_screen_width(comp, ctx, static)
	local hidden = min_screen_width and vim.o.columns > min_screen_width or should_hidden(comp, session_id, ctx, static)

	if hidden then
		clear_comp_value(comp)
		return ""
	end

	-- local value = Component.evaluate(comp, ctx, static)
	local value = Component.evaluate(comp, ctx, static)
	if value == "" then
		clear_comp_value(comp)
		return ""
	end

	-- Component.update_style(comp, ctx, static, session_id)
	Component.update_style(comp, session_id, ctx, static)

	local indices = comp._indices
	if not indices then
		error("Component " .. comp.id .. " has no indices set. Ensure it has been registered properly.")
		return
	end

	local add_hl_name = require("witch-line.utils.highlight").add_hl_name
	statusline.bulk_set(indices, add_hl_name(value, comp._hl_name))
	local left, right = Component.evaluate_left_right(comp, ctx, static)
	if left then
		statusline.bulk_set_sep(indices, add_hl_name(left, comp._left_hl_name), -1)
	end
	if right then
		statusline.bulk_set_sep(indices, add_hl_name(right, comp._right_hl_name), 1)
	end
	rawset(comp, "_hidden", false) -- Reset hidden state
	return value
end
M.update_comp = update_comp

--- Update a component and its dependencies.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_stores DepStore|DepStore[]|nil Optional. The store to use for dependencies.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
function M.update_comp_graph(comp, session_id, dep_stores, seen)
	seen = seen or {}
	local id = comp.id
	if seen[id] then
		return -- Avoid infinite recursion
	end

	local updated_value = update_comp(comp, session_id)
	if updated_value == "" then
		local refs = CompManager.get_raw_dep_store(DepStoreKey.Display)
		if refs then
			local ids = refs[id]
			if ids then
				for dep_id, _ in pairs(ids) do
					local dep_comp = get_comp(dep_id)
					if dep_comp then
						clear_comp_value(dep_comp._indices)
					else
						ids[dep_id] = nil -- Clean up if the component is not found
					end
				end
			end
		end
	end

	---@cast id Id
	seen[id] = true
	if dep_stores then
		if not vim.islist(dep_stores) then
			dep_stores = { dep_stores }
		end
		---@cast dep_stores DepStore[]
		for _, dep_store in ipairs(dep_stores) do
			local dep_ids = dep_store[id]
			if dep_ids then
				for dep_id, _ in pairs(dep_ids) do
					local dep_comp = get_comp(dep_id)
					if not dep_comp then
						dep_ids[dep_id] = nil -- Clean up if the component is not found
					elseif not seen[dep_comp.id] then
						M.update_comp_graph(dep_comp, session_id, dep_store, seen)
					end
				end
			end
		end
	end
end

--- Update multiple components by their IDs.
--- @param ids Id[] The IDs of the components to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_stores DepStore|DepStore[]|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_graph_by_ids = function(ids, session_id, dep_stores, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		if not seen[id] then
			local comp = get_comp(id)
			if comp then
				M.update_comp_graph(comp, session_id, dep_stores, seen)
			end
		end
	end
end

--- Register events for components.
---@param comp Component
---@param key "events" | "user_events"
local function registry_events(comp, key)
	local es = comp[key]
	if type(es) == "table" then
		local es_size = #es
		if es_size > 0 then
			local store = EventStore[key] or {}
			EventStore[key] = store
			for i = 1, es_size do
				local e = es[i]
				local store_e = store[e] or {}
				store_e[#store_e + 1] = comp.id
				store[e] = store_e
			end
		end
	end
end

--- Register a timer for a component.
--- @param comp Component The component to register the timer for.
local function registry_timer(comp)
	local timing = comp.timing == true and TIMER_TICK or comp.timing
	if type(timing) == "number" and timing > 0 then
		local ids = TimerStore[timing] or {}
		ids[#ids + 1] = comp.id
		TimerStore[timing] = ids
	end
end

--- Initialize the autocmd for events and user events.
--- @return integer|nil group The ID of the autocmd group created.
--- @return integer|nil events_id The ID of the autocmd for events.
--- @return integer|nil user_events_id The ID of the autocmd for user events.
local function init_autocmd()
	local events, user_events = EventStore.events, EventStore.user_events
	local on_event_debounce = require("witch-line.utils").debounce(function(stack, key)
		local store = EventStore[key]
		if not store then
			return
		end
		local seen = {}
		local stack_size = #stack
		if stack_size > 0 then
			local Session = require("witch-line.core.Session")
			Session.run_once(function(id)
				for i = stack_size, 1, -1 do
					local ids = store[stack[i]]
					stack[i] = nil

					if ids then
						local refs = CompManager.get_raw_dep_store(DepStoreKey.Event)
						M.update_comp_graph_by_ids(ids, id, refs, seen)
					end
				end
			end)
			statusline.render()
		end
	end, 100)

	local group, id1, id2 = nil, nil, nil

	if events and next(events) then
		group = group or api.nvim_create_augroup("WitchLineUserEvents", { clear = true })
		local stack = {}
		id1 = api.nvim_create_autocmd(vim.tbl_keys(events), {
			group = group,
			callback = function(e)
				stack[#stack + 1] = e.event
				on_event_debounce(stack, "events")
			end,
		})
	end

	if user_events and next(user_events) then
		group = group or api.nvim_create_augroup("WitchLineUserEvents", { clear = true })
		local stack = {}
		id2 = api.nvim_create_autocmd("User", {
			pattern = vim.tbl_keys(user_events),
			group = group,
			callback = function(e)
				stack[#stack + 1] = e.match
				on_event_debounce(stack, "user_events")
			end,
		})
	end

	return group, id1, id2
end

--- Initialize the timer for components that have timers registered.
local function init_timer()
	local timers = TimerStore
	if not timers then
		return
	end

	for interval, ids in pairs(timers) do
		ids.timer = uv.new_timer()
		ids.timer:start(
			0,
			interval,
			vim.schedule_wrap(function()
				local Session = require("witch-line.core.Session")
				Session.run_once(function(session_id)
					M.update_comp_graph_by_ids(ids, session_id, CompManager.get_raw_dep_store(DepStoreKey.Timer), {})
					statusline.render()
				end)
			end)
		)
	end
end

--- Link dependencies for a component.
--- @param comp Component The component to link dependencies for.
local function registry_refs(comp)
	local ref = comp.ref
	local ref_ids = {}
	if type(ref) == "table" then
		if ref.events then
			link_ref_field(comp, ref.events, get_dep_store(DepStoreKey.Event), ref_ids)
		end

		if ref.min_screen_width then
			link_ref_field(comp, ref.min_screen_width, get_dep_store(DepStoreKey.Event), ref_ids)
		end

		if ref.user_events then
			link_ref_field(comp, ref.user_events, get_dep_store(DepStoreKey.Event), ref_ids)
		end

		if ref.timing then
			link_ref_field(comp, ref.timing, get_dep_store(DepStoreKey.Timer), ref_ids)
		end

		if ref.hide then
			link_ref_field(comp, ref.hide, get_dep_store(DepStoreKey.Display), ref_ids)
		end
	end

	local inherit = comp.inherit
	if inherit then
		link_ref_field(comp, inherit, get_dep_store(DepStoreKey.Event), ref_ids)
		link_ref_field(comp, inherit, get_dep_store(DepStoreKey.Timer), ref_ids)
		link_ref_field(comp, inherit, get_dep_store(DepStoreKey.Display), ref_ids)
	end

	-- Pull missing dependencies from the component's ref field
	local Component = require("witch-line.core.Component")
	for id, _ in pairs(ref_ids) do
		if not CompManager.id_exists(id) then
			local c = Component.require_by_id(id)
			if c then
				M.registry_abstract_component(c, id)
			end
		end
	end
end

--- Register the component for VimResized event if it has a minimum screen width.
---@param comp Component
local function registry_vim_resized(comp)
	local store = EventStore["events"] or {}
	EventStore["events"] = store
	local es = store["VimResized"] or {}
	es[#es + 1] = comp.id
	store["VimResized"] = es
end

--- Register conditions for a component.
--- @param comp Component The component to register conditions for.
local function registry_update_conditions(comp)
	if comp.timing then
		registry_timer(comp)
	end

	if comp.events then
		registry_events(comp, "events")
	end

	if comp.min_screen_width then
		registry_vim_resized(comp)
	end

	if comp.user_events then
		registry_events(comp, "user_events")
	end

	registry_refs(comp)
end

--- Register a component by its type.
--- @param comp Component|string The component to register.
--- @param i integer The index of the component in the registry.
--- @param urgents Id[] The list of components that should be updated immediately.
--- @param inherit_comp_id Id|nil The ID of the component to inherit from, if any.
function M.registry_comp_by_type(comp, i, urgents, inherit_comp_id)
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
		elseif inherit_comp_id and not c.inherit then
			rawset(c, "inherit", inherit_comp_id)
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

		if inherit_comp_id and not comp.inherit then
			rawset(comp, "inherit", inherit_comp_id)
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
		statusline.static(statusline.push(comp))
	end
	return comp
end
--- Register a component in the statusline.
--- @param comp Component
--- @param id Id The ID to assign to the component.
--- @return Id The ID of the registered component.
function M.registry_abstract_component(comp, id)
	if not comp._abstract then
		id = manage(comp, id)

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
		---@cast comps ConfigComps
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

	init_autocmd()
	init_timer()

	if urgents[1] then
		local Session = require("witch-line.core.Session")
		Session.run_once(function(session_id)
			M.update_comp_graph_by_ids(urgents, session_id, {
				get_raw_dep_store(DepStoreKey.Event),
				get_raw_dep_store(DepStoreKey.Timer),
			}, {})
		end)
	end

	if not cached then
		CompManager.cache_ugent_comps(urgents)
	end
	statusline.render()
end

return M
