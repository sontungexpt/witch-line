local vim, type, ipairs, pairs = vim, type, ipairs, pairs
local api, uv = vim.api, vim.uv or vim.loop

---@alias DepStore table<Id, table<Id, true>>

local M = {}

local TIMER_TICK = 1000 -- 1 second

local statusline = require("witch-line.core.statusline")
local FlatComponent = require("witch-line.core.flat.FlatComponent")
local Session = require("witch-line.core.flat.Session")
local highlight = require("witch-line.utils.highlight")
local add_hl_name, gen_hl_name_by_id = highlight.add_hl_name, highlight.gen_hl_name_by_id

---@type table<Id|integer, FlatComponent>
local CompIdMap = {}

---@type {events: table<string, Id[]>|nil, user_events: table<string, Id[]>|nil, refs: DepStore}
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

	refs = {
		-- [id] = {
		--   [dep_id] = true, -- Stores component dependencies for other components
		-- }
	}, -- Stores component dependencies for other references
}

---@type table<uinteger , Id[]|{timer: any}>|{refs: table<Id, table<Id, boolean>>}
local TimerStore = {
	-- Stores component IDs for timers
	-- Stores component IDs for timers with a specific interval
	-- [interval] = {
	-- timer = uv.new_timer(), -- Timer object for the interval
	-- comp_id1,
	-- comp_id2,
	-- ...
	-- }
	-- [interval].timer = uv.new_timer() -- Timer object for the interval

	-- Stores component dependencies for other references
	-- refs = {
	--  [id] = {
	--    [dep_id] = true, -- Stores component dependencies for other components
	--  }
	-- },
}

---@type DepStore
local DisplayRefs = {
	-- Stores component dependencies for display
	-- [id] = {
	--   [dep_id] = true, -- Stores component dependencies for other components
	-- }
}

--- Add a dependency for a component.
--- @param comp FlatComponent The component to add the dependency for.
--- @param on Id The event or component ID that this component depends on.
--- @param store DepStore Optional. The store to add the dependency to. Defaults to EventRefs.
local function add_dependency(comp, on, store)
	store = store or EventStore.refs
	local deps = store[on] or {}
	deps[comp.id] = true
	store[on] = deps
end
M.add_dependency = add_dependency

--- Recursively get a value from a component.
--- @param comp FlatComponent The component to get the value from.
--- @param key string The key to look for in the component.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param seen table<string, boolean> A table to keep track of already seen values to avoid infinite recursion.
local function get_value_recursive(comp, key, session_id, seen, ...)
	local value = comp[key]
	local value_type = type(value)

	if value_type == "string" then
		if seen[value] then
			return nil, value
		end
		seen[value] = true

		local store = Session.get_or_init(session_id, key, {})
		if store[value] then
			return store[value], value
		end

		local ref_comp = CompIdMap[value]
		if not ref_comp then
			return nil, value
		end

		local ref_value = ref_comp[key]
		local ref_value_type = type(ref_value)

		-- Reduce recursive calls by checking if the value is already seen
		if ref_value_type == "string" then
			if seen[ref_value] then
				return nil, value
			end
			seen[ref_value] = true
			return get_value_recursive(ref_comp, key, session_id, seen)
		elseif ref_value_type == "function" then
			ref_value = value(comp, ...)
		end
		store[value] = ref_value
		return ref_value, value
	elseif value_type == "function" then
		value = value(comp, ...)
	end

	return value, nil
end

--- Get the context for a component.
--- @param comp FlatComponent The component to get the context for.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param ... any Additional arguments to pass to the context function.
M.get_context = function(comp, session_id, ...)
	return get_value_recursive(comp, "context", session_id, {}, ...)
end

--- Get the style for a component.
--- @param comp FlatComponent The component to get the context for.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param ... any Additional arguments to pass to the style function.
M.get_style = function(comp, session_id, ...)
	return get_value_recursive(comp, "style", session_id, {}, ...)
end

--- Check if a component should be displayed.
--- @param comp FlatComponent The component to check.
--- @param session_id SessionId The ID of the process to use for this check.
--- @param ... any Additional arguments to pass to the should_display function.
M.should_display = function(comp, session_id, ...)
	local displayed, _ = get_value_recursive(comp, "should_display", session_id, {}, ...)
	return displayed ~= false
end

--- Get the static value for a component by recursively checking its dependencies.
--- @param comp FlatComponent The component to get the static value for.
--- @param key string The key to look for in the component.
--- @return NotString value The static value of the component.
--- @return FlatComponent|nil inherited The component that provides the static value.
local function get_inherit_value(comp, key)
	if not comp then
		error("Component is nil or not found in CompIdMap")
	end

	local node, static = comp, comp[key]
	while type(static) == "string" do
		node = CompIdMap[static]
		if not node then
			break
		else
			static = node[key]
		end
	end

	return static, node
end

--- Get the static value for a component.
--- @param comp FlatComponent The component to get the static value for.
--- @return NotString value The static value of the component.
--- @return FlatComponent|nil inherited The component that provides the static value.
function M.get_static(comp)
	return get_inherit_value(comp, "static")
end

--- Update a component and its dependencies.jj
--- @param comp FlatComponent The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
local function update_comp(comp, session_id)
	local ctx = M.get_context(comp, session_id)
	local static = M.get_static(comp)

	local should_display = M.should_display(comp, session_id, ctx, static)

	if should_display then
		local style, ref_id = M.get_style(comp, session_id, ctx, static)
		if type(style) == "table" then
			if ref_id then
				local ref_comp = CompIdMap[ref_id]
				if ref_comp then
					if not comp._hl_name then
						ref_comp._hl_name = ref_comp._hl_name or gen_hl_name_by_id(ref_comp.id)
						comp._hl_name = ref_comp._hl_name
						highlight.hl(comp._hl_name, style)
					elseif type(ref_comp.style) == "function" then
						highlight.hl(comp._hl_name, style)
					end
				end
			elseif not comp._hl_name then
				comp._hl_name = gen_hl_name_by_id(comp.id)
				highlight.hl(comp._hl_name, style)
			end
			if type(comp.style) == "function" then
				highlight.hl(comp._hl_name, style)
			end
		end
	end

	local value = FlatComponent.evaluate(comp, ctx, static)
	if value ~= "" then
		local indices = comp._indices
		if not indices then
			return
		end
		statusline.bulk_set(indices, add_hl_name(value, comp._hl_name))
		if comp._hidden then
			local left, right = comp.left, comp.right
			if type(left) == "string" then
				statusline.bulk_set_sep(indices, add_hl_name(left, gen_hl_name_by_id(comp.id, false)), true)
			end
			if type(right) == "string" then
				statusline.bulk_set_sep(indices, add_hl_name(right, gen_hl_name_by_id(comp.id, true)), false)
			end
		end
		comp._hidden = false
	else
		local clear_value = function(comp)
			local indices = comp._indices
			statusline.bulk_set(indices, "")
			if type(comp.left) == "string" then
				statusline.bulk_set_sep(indices, "", true)
			end
			if type(comp.right) == "string" then
				statusline.bulk_set_sep(indices, "", false)
			end
			comp._hidden = true
		end
		clear_value(comp._indices)
		local ids = DisplayRefs[comp.id]
		if ids then
			for dep_id, _ in pairs(ids) do
				local dep_comp = CompIdMap[dep_id]
				if dep_comp then
					clear_value(dep_comp._indices)
				end
			end
		end
	end
end
M.update_comp = update_comp

--- Update a component and its dependencies.
--- @param comp FlatComponent The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_ids table<Id,boolean>|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_and_deps = function(comp, session_id, dep_ids, seen)
	if not comp then
		error("Component is nil or not found in CompIdMap")
	end

	seen = seen or {}
	if not seen[comp.id] then
		update_comp(comp, session_id)
		seen[comp.id] = true
	end

	if dep_ids then
		for dep_id, _ in pairs(dep_ids) do
			local dep_comp = CompIdMap[dep_id]
			if dep_comp and not seen[dep_comp.id] then
				update_comp(dep_comp, session_id)
			end
		end
	end
end

--- Update multiple components by their IDs.
--- @param ids Id[] The IDs of the components to update.
--- @param process_id SessionId The ID of the process to use for this update.
--- @param dep_store DepStore Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comps_deps_by_id = function(ids, process_id, dep_store, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		local comp = CompIdMap[id]
		if comp then
			M.update_comp_and_deps(comp, process_id, dep_store[id], seen)
		end
	end
end

--- Get a component by its ID.
--- @param id Id The ID of the component to get.
--- @return FlatComponent|nil comp The component with the given ID, or nil if not found.
M.get_comp = function(id)
	return CompIdMap[id]
end

--- Register events for components.
---@param comp FlatComponent
---@param key "events" | "user_events"
local function registry_events(comp, key)
	local es = comp[key]
	local type_es = type(es)
	if type_es == "table" then
		if type(es.refs) == "table" then
			for _, dep in ipairs(es.refs) do
				add_dependency(comp, dep, EventStore.refs)
			end
		end

		local store = EventStore[key]
		if not store then
			store = {}
			EventStore[key] = store
		end

		for _, e in ipairs(es) do
			local store_e = store[e]
			if not store_e then
				store[e] = { comp.id }
			else
				store_e[#store_e + 1] = comp.id
			end
		end
	end
end

--- Register a timer for a component.
--- @param comp FlatComponent The component to register the timer for.
local function registry_timer(comp)
	local timing = comp.timing
	local timing_type = type(timing)
	if timing_type == "string" then
		TimerStore.refs = TimerStore.refs or {}
		add_dependency(comp, timing, TimerStore.refs)
	elseif timing_type == "table" then
		TimerStore.refs = TimerStore.refs or {}
		for _, on in ipairs(timing) do
			add_dependency(comp, on, TimerStore.refs)
		end
	elseif timing_type == true then
		timing = TIMER_TICK
	end

	if type(timing) == "number" and timing > 0 then
		local ids = TimerStore[timing]
		if not ids then
			ids = { comp.id }
			TimerStore[timing] = ids

			---@diagnostic disable-next-line: undefined-field
			ids.timer = uv.new_timer()
			ids.timer:start(
				0,
				timing,
				vim.schedule_wrap(function()
					local process_id = Session.new()
					M.update_comps_deps_by_id(ids, process_id, TimerStore.refs)
					Session.remove(process_id)
					statusline.render()
				end)
			)
		else
			ids[#ids + 1] = comp.id
		end
	end
end
--- Handle events for components.
--- @param event string The event name.
--- @param key "events" | "user_events"  The key to access the events table.
--- @param session_id SessionId The ID of the process to use for this event handling.
--- @param seen table<string, boolean> A table to keep track of already seen components to avoid infinite recursion.
local function on_event(event, key, session_id, seen)
	local store = EventStore[key]
	if not store then
		return
	end

	local ids = store[event]
	if ids then
		M.update_comps_deps_by_id(ids, session_id, EventStore.refs, seen)
	end
end

local function init_autocmd()
	local events, user_events = EventStore.events, EventStore.user_events
	local on_event_debounce = require("witch-line.utils").debounce(function(queue, key)
		local seen = {}
		for i = 1, #queue do
			local session_id = Session.new()
			on_event(queue[i], key, session_id, seen)
			queue[i] = nil
			Session.remove(session_id)
			statusline.render()
		end
	end, 100)

	local group = nil
	if events and next(events) ~= nil then
		group = group or api.nvim_create_augroup("WitchLineUserEvents", { clear = true })
		local queue = {}
		api.nvim_create_autocmd(vim.tbl_keys(events), {
			group = group,
			callback = function(e)
				queue[#queue + 1] = e.event
				on_event_debounce(queue, "events")
			end,
		})
	end

	if user_events and next(user_events) ~= nil then
		group = group or api.nvim_create_augroup("WitchLineUserEvents", { clear = true })
		local queue = {}
		api.nvim_create_autocmd("User", {
			pattern = vim.tbl_keys(user_events),
			group = group,
			callback = function(e)
				queue[#queue + 1] = e.match
				on_event_debounce(queue, "user_events")
			end,
		})
	end

	return group
end

--
--- Register a component in the statusline.
--- @param comp FlatComponent|string
--- @param id Id|integer The ID to assign to the component.
--- @param urgents table<FlatComponent> The list of components that should be updated immediately.
--- @return nil
local function registry_comp(comp, id, urgents)
	local comp_type = type(comp)
	if comp_type == "string" then
		statusline.push(comp)
	elseif comp_type == "table" then
		if comp.init then
			comp.init(comp)
		end

		id = comp.id or id
		CompIdMap[id] = comp

		---@diagnostic disable-next-line: assign-type-mismatch
		comp.id = id

		local left = comp.left
		if type(left) == "string" then
			statusline.push(add_hl_name(left, gen_hl_name_by_id(id, false)))
		end

		local update = comp.update
		local st_idx = type(update) == "string" and statusline.push(update) or statusline.push("")
		local indices = statusline.indices
		if not indices then
			comp._indices = { st_idx }
		else
			indices[#indices + 1] = st_idx
		end

		local right = comp.right
		if type(right) == "string" then
			statusline.push(add_hl_name(right, gen_hl_name_by_id(id, true)))
		end

		if comp.lazy == false then
			urgents[#urgents + 1] = comp
		end

		local should_display = comp.should_display
		if type(should_display) == "string" then
			add_dependency(comp, should_display, DisplayRefs)
		end

		if comp.timing then
			registry_timer(comp)
		end

		if comp.events then
			registry_events(comp, "events")
		end

		if comp.user_events then
			registry_events(comp, "user_events")
		end
	end
end

M.setup = function(configs)
	local urgents = {}
	local components = configs.components
	for i = 1, #components do
		local c = components[i]
		registry_comp(c, i, urgents)
	end

	init_autocmd()

	if urgents[1] then
		local process_id = Session.new()
		for i = 1, #urgents do
			local comp = urgents[i]
			M.update_comp_and_deps(comp, process_id)
		end
		Session.remove(process_id)
	end
	statusline.render()
end

return M
