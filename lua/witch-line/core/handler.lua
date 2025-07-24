local vim, type, ipairs, pairs, rawset, require, setmetatable = vim, type, ipairs, pairs, rawset, require, setmetatable
local api, uv = vim.api, vim.uv or vim.loop

local M = {}

local TIMER_TICK = 1000 -- 1 second

---@enum DepStoreKey
local DepStoreKey = {
	Display = 1,
	Event = 2,
	Timer = 3,
	Inherited = 4,
}

local statusline = require("witch-line.core.statusline")

local CompManager = require("witch-line.core.CompManager")

local IdHelper, manage, get_comp_by_id, link_dep, get_dep_store, get_context, get_static, should_display =
	CompManager.Id,
	CompManager.register,
	CompManager.get_comp_by_id,
	CompManager.link_dep,
	CompManager.get_dep_store,
	CompManager.get_context,
	CompManager.get_static,
	CompManager.should_display

---@type {events: nil|table<string, Id[]>, user_events: nil|table<string, Id[]>}
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

---@type table<uinteger , Id[]|{timer: any}>
local TimerStore = {
	-- Stores component IDs for timers
	-- Stores component IDs for timers with a specific interval
	-- [interval] = {
	-- timer = uv.new_timer(), -- Timer object for the interval
	-- comp_id1,
	-- comp_id2,
	-- ...
	-- ...
	-- }
	-- [interval].timer = uv.new_timer() -- Timer object for the interval

	-- Stores component dependencies for other references
	-- }
	-- [interval].timer = uv.new_timer() -- Timer object for the interval

	-- Stores component dependencies for other references
}

--- Update a component and its dependencies.jj
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
local function update_comp(comp, session_id)
	if comp.inherit then
		local parent = get_comp_by_id(comp.inherit)
		if parent then
			setmetatable(comp, {
				__index = function(t, key)
					if vim.startswith(key, "_") then
						return rawget(t, key)
					end
					return parent[key]
				end,
			})
		end
	end

	local static = get_static(comp)
	local ctx = get_context(comp, session_id, static)

	local displayed = should_display(comp, session_id, ctx, static)

	if displayed then
		local Component = require("witch-line.core.Component")
		Component.update_style(comp, ctx, static, session_id)
		local value = Component.evaluate(comp, ctx, static)

		if value ~= "" then
			local indices = comp._indices
			if not indices then
				return
			end
			local add_hl_name = require("witch-line.utils.highlight").add_hl_name

			statusline.bulk_set(indices, add_hl_name(value, comp._hl_name))
			if comp._hidden ~= false then
				local left, right = comp.left, comp.right

				if type(left) == "string" then
					statusline.bulk_set_sep(indices, add_hl_name(left, comp._left_hl_name), true)
				end
				if type(right) == "string" then
					statusline.bulk_set_sep(indices, add_hl_name(right, comp._right_hl_name), false)
				end
			end
			rawset(comp, "_hidden", false) -- Reset hidden state
			return
		end
	end

	local clear_value = function(c)
		local indices = c._indices
		if not indices then
			return
		end

		statusline.bulk_set(indices, "")
		if type(c.left) == "string" then
			statusline.bulk_set_sep(indices, "", true)
		end
		if type(c.right) == "string" then
			statusline.bulk_set_sep(indices, "", false)
		end
		rawset(c, "_hidden", true) -- Reset hidden state
	end
	clear_value(comp)

	local refs = CompManager.get_raw_dep_store(DepStoreKey.Display)
	if refs then
		local ids = refs[comp.id]
		if ids then
			for dep_id, _ in pairs(ids) do
				local dep_comp = get_comp_by_id(dep_id)
				if dep_comp then
					clear_value(dep_comp._indices)
				else
					ids[dep_id] = nil -- Clean up if the component is not found
				end
			end
		end
	end
end
M.update_comp = update_comp

--- Update a component and its dependencies.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_ids table<Id,boolean>|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param inherited_key string|nil Optional. The key to use for inherited dependencies.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_and_deps = function(comp, session_id, dep_ids, inherited_key, seen)
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
			local dep_comp = get_comp_by_id(dep_id)
			if dep_comp and not seen[dep_comp.id] then
				update_comp(dep_comp, session_id)
			else
				dep_ids[dep_id] = nil -- Clean up if the component is not found
			end
		end
	end

	if inherited_key then
		local inherited_dep_store = CompManager.get_raw_dep_store(DepStoreKey.Inherited)
		if not inherited_dep_store then
			return
		end
		local inherited_dep_ids = inherited_dep_store[comp.id]
		if inherited_dep_ids then
			for dep_id, _ in pairs(inherited_dep_ids) do
				local dep_comp = get_comp_by_id(dep_id)
				if
					dep_comp
					and not seen[dep_comp.id]
					-- no private key already
					and not rawget(dep_comp, inherited_key)
				then
					update_comp(dep_comp, session_id)
				end
			end
		end
	end
end

--- Update multiple components by their IDs.
--- @param ids Id[] The IDs of the components to update.
--- @param process_id SessionId The ID of the process to use for this update.
--- @param dep_store DepStore Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param inherited_key string|nil Optional. The key to use for inherited dependencies.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comps_deps_by_id = function(ids, process_id, dep_store, inherited_key, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		local comp = get_comp_by_id(id)
		if comp then
			M.update_comp_and_deps(comp, process_id, dep_store and dep_store[id] or nil, inherited_key, seen)
		end
	end
end

--- Register events for components.
---@param comp Component
---@param key "events" | "user_events"
local function registry_events(comp, key)
	local es = comp[key]
	local type_es = type(es)
	if type_es == "table" then
		if type(es.refs) == "table" then
			local dep_store = get_dep_store(DepStoreKey.Event)
			for _, dep in ipairs(es.refs) do
				link_dep(comp, dep, dep_store)
			end
		end

		local store = EventStore[key] or {}
		EventStore[key] = store

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
--- @param comp Component The component to register the timer for.
local function registry_timer(comp)
	local timing = comp.timing == true and TIMER_TICK or comp.timing

	local timing_type = type(timing)
	if timing_type == "number" and timing > 0 then
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
					local Session = require("witch-line.core.Session")
					local process_id = Session.new()
					M.update_comps_deps_by_id(
						ids,
						process_id,
						CompManager.get_raw_dep_store(DepStoreKey.Timer),
						"timing",
						{}
					)
					Session.remove(process_id)
					statusline.render()
				end)
			)
		else
			ids[#ids + 1] = comp.id
		end
	elseif timing_type == "string" or timing_type == "function" then
		local refs = get_dep_store(DepStoreKey.Timer)
		link_dep(comp, timing, refs)
	elseif timing_type == "table" then
		local refs = get_dep_store(DepStoreKey.Timer)
		for _, on in ipairs(timing) do
			link_dep(comp, on, refs)
		end
	end
end

--- Initialize the autocmd for events and user events.
--- @return integer|nil group The ID of the autocmd group created.
--- @return integer|nil events_id The ID of the autocmd for events.
--- @return integer|nil user_events_id The ID of the autocmd for user events.
local function init_autocmd()
	local events, user_events = EventStore.events, EventStore.user_events
	local on_event_debounce = require("witch-line.utils").debounce(function(queue, key)
		local store = EventStore[key]
		if not store then
			return
		end
		local seen = {}
		for i = 1, #queue do
			local ids = store[queue[i]]
			queue[i] = nil

			if ids then
				local Session = require("witch-line.core.Session")
				local session_id = Session.new()
				local refs = CompManager.get_raw_dep_store(DepStoreKey.Event)
				M.update_comps_deps_by_id(ids, session_id, refs, key, seen)
				Session.remove(session_id)
			end
		end
		statusline.render()
	end, 100)

	local group, id1, id2 = nil, nil, nil
	if events and next(events) ~= nil then
		group = group or api.nvim_create_augroup("WitchLineUserEvents", { clear = true })
		local queue = {}
		id1 = api.nvim_create_autocmd(vim.tbl_keys(events), {
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
		id2 = api.nvim_create_autocmd("User", {
			pattern = vim.tbl_keys(user_events),
			group = group,
			callback = function(e)
				queue[#queue + 1] = e.match
				on_event_debounce(queue, "user_events")
			end,
		})
	end

	return group, id1, id2
end

--
--- Register a component in the statusline.
--- @param comp Component|string
--- @param id Id|integer The ID to assign to the component.
--- @param urgents table<Component> The list of components that should be updated immediately.
--- @return nil
local function registry_comp(comp, id, urgents)
	local comp_type = type(comp)
	if comp_type == "string" then
		statusline.push(comp)
	elseif comp_type == "table" then
		id = manage(comp, id)
		if comp.lazy == false then
			urgents[#urgents + 1] = comp
		end

		if comp.init then
			comp.init(comp)
		end

		if comp.inherit then
			link_dep(comp, comp.inherit, get_dep_store(DepStoreKey.Inherited))
		end

		if comp.left then
			statusline.push("")
		end

		local update = comp.update
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

		local displayed = comp.should_display
		if displayed and (IdHelper.is_fun_id(displayed) or type(displayed) ~= "function") then
			---@diagnostic disable-next-line: param-type-mismatch
			link_dep(comp, displayed, get_dep_store(DepStoreKey.Display))
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

--- Setup the statusline with the given configurations.
--- @param configs Config  The configurations for the statusline.
M.setup = function(configs)
	local abstract = configs.abstract
	for i = 1, #abstract do
		local c = abstract[i]
		if type(c) == "table" and c.id then
			manage(c, c.id)
		else
			error("Abstract component must be a table with an 'id' field: " .. tostring(c))
		end
	end

	local urgents = {}
	local components = configs.components
	for i = 1, #components do
		local c = components[i]
		registry_comp(c, i, urgents)
	end

	init_autocmd()

	if urgents[1] then
		local Session = require("witch-line.core.Session")
		local session_id = Session.new()
		for i = 1, #urgents do
			local comp = urgents[i]
			M.update_comp_and_deps(comp, session_id, nil, "lazy", {})
		end
		Session.remove(session_id)
	end
	statusline.render()
end

return M
