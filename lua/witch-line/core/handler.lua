local vim, type, ipairs, pairs, rawset, require, setmetatable = vim, type, ipairs, pairs, rawset, require, setmetatable
local api, uv = vim.api, vim.uv or vim.loop

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

local manage, get_comp_by_id, link_ref_field, get_dep_store, get_context, get_static, should_display =
	CompManager.register,
	CompManager.get_comp_by_id,
	CompManager.link_ref_field,
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
	--   [timer] = uv.new_timer(), -- Timer object for the interval
	--   comp_id1,
	--   comp_id2,
	--   ...
	--   ...
	-- }
}

M.cache = function(force)
	local CacheMod = require("witch-line.cache")
	CacheMod.cache(EventStore, "EventStore", force)
	CacheMod.cache(TimerStore, "TimerStore", force)
end

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
	local displayed = true

	local min_screen_width = comp.min_screen_width
	if type(min_screen_width) == "number" and min_screen_width > 0 then
		displayed = vim.o.columns >= min_screen_width
	end

	displayed = displayed and should_display(comp, session_id, ctx, static)

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
					statusline.bulk_set_sep(indices, add_hl_name(left, comp._left_hl_name), -1)
				end
				if type(right) == "string" then
					statusline.bulk_set_sep(indices, add_hl_name(right, comp._right_hl_name), 1)
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
			statusline.bulk_set_sep(indices, "", -1)
		end
		if type(c.right) == "string" then
			statusline.bulk_set_sep(indices, "", 1)
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
--- @param dep_store DepStore|nil Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
function M.update_comp_graph(comp, session_id, dep_store, seen)
	seen = seen or {}
	local id = comp.id
	if seen[id] then
		return -- Avoid infinite recursion
	end

	update_comp(comp, session_id)
	---@cast id Id
	seen[id] = true

	if dep_store then
		local dep_ids = dep_store[id]
		for dep_id, _ in pairs(dep_ids) do
			local dep_comp = get_comp_by_id(dep_id)
			if not dep_comp then
				dep_ids[dep_id] = nil -- Clean up if the component is not found
			elseif not seen[dep_comp.id] then
				M.update_comp_graph(dep_comp, session_id, dep_store, seen)
			end
		end
	end
end

--- Update multiple components by their IDs.
--- @param ids Id[] The IDs of the components to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_store DepStore Optional. The store to use for dependencies. Defaults to EventStore.refs.
--- @param seen table<Id, boolean>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_graphs_by_id = function(ids, session_id, dep_store, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		local comp = get_comp_by_id(id)
		if comp and not seen[id] then
			M.update_comp_graph(comp, session_id, dep_store, seen)
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
				local store_e = store[e]
				if not store_e then
					store[e] = { comp.id }
				else
					store_e[#store_e + 1] = comp.id
				end
			end
		end
	end
end

--- Register a timer for a component.
--- @param comp Component The component to register the timer for.
local function registry_timer(comp)
	local timing = comp.timing == true and TIMER_TICK or comp.timing

	if type(timing) == "number" and timing > 0 then
		local ids = TimerStore[timing]
		if ids then
			ids[#ids + 1] = comp.id
			return
		end

		ids = { comp.id }
		TimerStore[timing] = ids

		---@diagnostic disable-next-line: undefined-field
		ids.timer = uv.new_timer()
		ids.timer:start(
			0,
			timing,
			vim.schedule_wrap(function()
				local Session = require("witch-line.core.Session")
				local session_id = Session.new()
				M.update_comp_graphs_by_id(ids, session_id, CompManager.get_raw_dep_store(DepStoreKey.Timer), {})
				Session.remove(session_id)
				statusline.render()
			end)
		)
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
				M.update_comp_graphs_by_id(ids, session_id, refs, seen)
				Session.remove(session_id)
			end
		end
		statusline.render()
	end, 100)

	local group, id1, id2 = nil, nil, nil
	local tbl_keys = require("witch-line.utils.tbl").tbl_keys

	if events then
		events = tbl_keys(events)
		if events[1] then
			group = group or api.nvim_create_augroup("WitchLineUserEvents", { clear = true })
			local queue = {}
			id1 = api.nvim_create_autocmd(events, {
				group = group,
				callback = function(e)
					queue[#queue + 1] = e.event
					on_event_debounce(queue, "events")
				end,
			})
		end
	end

	if user_events then
		user_events = tbl_keys(user_events)
		if user_events[1] then
			group = group or api.nvim_create_augroup("WitchLineUserEvents", { clear = true })
			local queue = {}
			id2 = api.nvim_create_autocmd("User", {
				pattern = user_events,
				group = group,
				callback = function(e)
					queue[#queue + 1] = e.match
					on_event_debounce(queue, "user_events")
				end,
			})
		end
	end

	return group, id1, id2
end

--- Link dependencies for a component.
--- @param comp Component The component to link dependencies for.
local function link_refs(comp)
	local ref = comp.ref
	if type(ref) ~= "table" then
		return
	end

	local inherit = comp.inherit
	if ref.events then
		link_ref_field(comp, ref.events, get_dep_store(DepStoreKey.Event))
	elseif inherit then
		link_ref_field(comp, inherit, get_dep_store(DepStoreKey.Event))
	end

	if ref.user_events then
		link_ref_field(comp, ref.user_events, get_dep_store(DepStoreKey.Event))
	elseif inherit then
		link_ref_field(comp, inherit, get_dep_store(DepStoreKey.Event))
	end

	if ref.timing then
		link_ref_field(comp, ref.timing, get_dep_store(DepStoreKey.Timer))
	elseif inherit then
		link_ref_field(comp, inherit, get_dep_store(DepStoreKey.Timer))
	end

	if ref.should_display then
		link_ref_field(comp, ref.should_display, get_dep_store(DepStoreKey.Display))
	elseif inherit then
		link_ref_field(comp, inherit, get_dep_store(DepStoreKey.Display))
	end
end

---@param comp Component
local function registry_vim_resized(comp)
	if type(comp.min_screen_width) == "number" and comp.min_screen_width > 0 then
		local store = EventStore["events"] or {}
		EventStore["events"] = store
		local es = store["VimResized"]
		if not es then
			store["VimResized"] = { comp.id }
		else
			es[#es + 1] = comp.id
		end
	end
end

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

		if comp.ref then
			link_refs(comp)
		end

		rawset(comp, "_loaded", true) -- Mark the component as loaded
	end
end

--- Register a component in the statusline.
--- @param comp Component
--- @param id Id The ID to assign to the component.
--- @return nil
local function registry_abstract_comp(comp)
	CompManager.fast_register(comp)

	if comp.init then
		comp.init(comp)
	end

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

	if comp.ref then
		link_refs(comp)
	end
end

--- Setup the statusline with the given configurations.
--- @param configs Config  The configurations for the statusline.
M.setup = function(configs)
	local abstract = configs.abstract
	for i = 1, #abstract do
		local c = abstract[i]
		if type(c) == "table" and c.id then
			registry_abstract_comp(c)
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
			M.update_comp_graph(comp, session_id, nil, {})
		end
		Session.remove(session_id)
	end
	statusline.render()
end

return M
