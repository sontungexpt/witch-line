local vim, type, ipairs, pairs = vim, type, ipairs, pairs
local api, uv = vim.api, vim.uv or vim.loop

local M = {}

local TIMER_TICK = 1000 -- 1 second

local statusline = require("witch-line.core.statusline")
local highlight = require("witch-line.utils.highlight")
local FlatComponent = require("witch-line.core.flat.FlatComponent")

local IdMap, Dependencies, HiddenDependencies, ProcessCache = {}, {}, {}, {}

local MainTimer, MainTimerStore, SubTimers = nil, nil, nil

local Augroup, RegisteredEvents = nil, {}

local function add_dependency(comp, on, store)
	local deps = (store or Dependencies)[on] or {}
	deps[comp.id] = true
	Dependencies[on] = deps
end
M.add_dependency = add_dependency

do
	local counter = 0
	M.create_process = function()
		if counter > 1000000 then
			counter = 0
		end
		counter = counter + 1
		return counter
	end
	M.clear_process = function(id)
		for store, _ in pairs(ProcessCache) do
			store[id] = nil
		end
	end
end

do
	local function get_value_recursive(comp, key, process_id, seen, ...)
		local value = comp[key]
		local value_type = type(value)

		if value_type == "string" then
			seen[value] = true
			local ref_comp = IdMap[value]
			if not ref_comp then
				return nil, value
			end

			local process_cache = ProcessCache[process_id] or {}
			local store = process_cache[key] or {}
			if store[value] then
				return store[value], value
			end
			ProcessCache[process_id], process_cache[key] = process_cache, store

			if ref_comp then
				local ref_value = ref_comp[key]
				local ref_value_type = type(ref_value)
				if ref_value_type == "string" and not seen[ref_value] then
					value, ref_value = get_value_recursive(ref_comp, key, process_id, seen)
					-- always return true because it already recursive
					return value, ref_value
				elseif ref_value_type == "function" then
					ref_value = value(comp, ...)
				end
				store[value] = ref_value
				return ref_value, value
			end
			return nil, value
		elseif value_type == "function" then
			value = value(comp, ...)
		end

		return value, nil
	end

	M.get_context = function(comp, process_id, ...)
		return get_value_recursive(comp, "context", process_id, {}, ...)
	end

	M.get_style = function(comp, process_id, ...)
		return get_value_recursive(comp, "style", process_id, {}, ...)
	end

	M.should_display = function(comp, process_id, ...)
		local value, _ = get_value_recursive(comp, "should_display", process_id, {}, ...)
		return value ~= nil
	end

	function M.get_static(comp)
		local static = comp.static
		if type(static) == "string" then
			local ref_comp = IdMap[static]
			if ref_comp then
				return M.get_static(ref_comp)
			end
			return nil
		end
		return static
	end
end

do
	local function _update_comp(comp, process_id, dep_store, seen)
		if not comp or seen[comp.id] then
			return
		end
		seen[comp.id] = true

		local ctx = M.get_context(comp, process_id)
		local static = M.get_static(comp)
		local should_display = M.should_display(comp, process_id, ctx, static)

		if should_display then
			local value = FlatComponent.evaluate(comp, ctx, static)

			if value ~= "" then
				local style, ref_id = M.get_style(comp, process_id, ctx, static)
				if type(style) == "table" then
					if ref_id then
						local ref_comp = IdMap[ref_id]
						if ref_comp then
							if not comp._hl_name then
								ref_comp._hl_name = ref_comp._hl_name or highlight.gen_hl_name_by_id(ref_comp.id)
								comp._hl_name = ref_comp._hl_name
								highlight.hl(comp._hl_name, style)
							elseif type(ref_comp.style) == "function" then
								highlight.hl(comp._hl_name, style)
							end
						end
					elseif not comp._hl_name then
						comp._hl_name = highlight.gen_hl_name_by_id(comp.id)
						highlight.hl(comp._hl_name, style)
					end
					if type(comp.style) == "function" then
						highlight.hl(comp._hl_name, style)
					end
				end
			end

			statusline.bulk_set(comp._indices, highlight.add_hl_name(value, comp._hl_name))
		else
			statusline.bulk_set(comp._indices, "")
			local deps = HiddenDependencies[comp.id]
			if deps then
				for dep_id, _ in pairs(deps) do
					local dep_comp = IdMap[dep_id]
					if dep_comp then
						statusline.bulk_set(dep_comp._indices, "")
					end
				end
			end
		end

		-- Handle dependencies
		local deps = (dep_store or Dependencies)[comp.id]
		if deps then
			for dep_id, _ in pairs(deps) do
				local dep_comp = IdMap[dep_id]
				if dep_comp then
					_update_comp(dep_comp)
				end
			end
		end
	end

	M.update_comp = function(comp, process_id)
		_update_comp(comp, process_id, Dependencies, {})
	end
end

M.get_comp = function(id)
	return IdMap[id]
end

--- Register events for components.
---@param comp FlatComponent
---@param key "events" | "user_events"
local function registry_events(comp, key)
	local store = RegisteredEvents[key]
	if not store then
		store = {}
		RegisteredEvents[key] = store
	end

	local es = comp[key]
	local type_es = type(es)
	if type_es == "table" then
		if type(es.following) == "table" then
			for _, dep in ipairs(es.following) do
				add_dependency(comp, dep, Dependencies)
			end
		end
		for _, e in ipairs(es) do
			local store_e = store[e] or {}
			store_e[comp.id] = true
			store[e] = store_e
		end
	end
end

local function registry_timer(comp)
	local timing = comp.timing
	local timing_type = type(timing)
	if timing_type == "string" then
		add_dependency(comp, timing, Dependencies)
	elseif timing_type == "table" then
		for _, dep in ipairs(timing) do
			add_dependency(comp, dep, Dependencies)
		end
	elseif timing_type == "number" and timing ~= TIMER_TICK then
		SubTimers = SubTimers or {}
		local new_len = #SubTimers + 1
		---@diagnostic disable-next-line: undefined-field
		SubTimers[new_len] = uv.new_timer()
		SubTimers[new_len]:start(
			0,
			timing,
			vim.schedule_wrap(function()
				local process_id = M.create_process()
				M.update_comp(comp, process_id)
				M.clear_process(process_id)
				statusline.render()
			end)
		)
	elseif not MainTimer then
		if not MainTimerStore then
			MainTimerStore = {}
		end

		MainTimerStore[comp.id] = true

		---@diagnostic disable-next-line: undefined-field
		MainTimer = uv.new_timer()

		MainTimer:start(
			0,
			TIMER_TICK,
			vim.schedule_wrap(function()
				local process_id = M.create_process()
				for id, _ in pairs(MainTimerStore) do
					local c = IdMap[id]
					if c then
						M.update_comp(c, process_id)
					end
				end
				M.clear_process(process_id)
				statusline.render()
			end)
		)
	end
end
--- Handle events for components.
--- @param event string The event name.
--- @param key "events" | "user_events"  The key to access the events table.
local function on_event(event, key)
	local store = RegisteredEvents[key]
	if not store then
		return
	end

	local ids = store[event]
	if not ids then
		return
	end

	local process_id = M.create_process()

	for id, _ in pairs(ids) do
		M.update_comp(IdMap[id], process_id)
	end

	M.clear_process(process_id)
	statusline.render()
end

local function init_autocmd()
	local tbl_keys = require("witch-line.utils.tbl").tbl_keys
	local events, user_events = RegisteredEvents.events, RegisteredEvents.user_events

	if events then
		local es, eslen = tbl_keys(events)
		if eslen > 0 then -- has nvim events
			Augroup = Augroup or api.nvim_create_augroup("WitchLine", { clear = true })
			api.nvim_create_autocmd(es, {
				group = Augroup,
				callback = function(e)
					on_event(e.event, "events")
				end,
			})
		end
	end
	if user_events then
		local ues, ueslen = tbl_keys(user_events)
		if ueslen > 0 then -- has user events
			Augroup = Augroup or api.nvim_create_augroup("WitchLineUser", { clear = true })
			api.nvim_create_autocmd("User", {
				pattern = ues,
				group = Augroup,
				callback = function(e)
					on_event(e.match, "user_events")
				end,
			})
		end
	end
end

--
---@param comp FlatComponent|string
local function registry_comp(comp, id, urgents)
	local comp_type = type(comp)
	if comp_type == "string" then
		statusline.push(comp)
	elseif comp_type == "table" then
		id = comp.id or id
		IdMap[id] = comp
		comp.id = id

		local statusline_idx = statusline.push("")
		local indices = statusline.indices
		if not indices then
			comp._indices = { statusline_idx }
		else
			indices[#indices + 1] = statusline_idx
		end

		if comp.lazy == false then
			urgents[#urgents + 1] = comp
		end

		if type(comp.should_display) == "string" then
			add_dependency(comp, comp.should_display, HiddenDependencies)
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
		for i = 1, #urgents do
			local comp = urgents[i]
			local process_id = M.create_process()
			M.update_comp(comp, process_id)
			M.clear_process(process_id)
		end
	end
	statusline.render()
end

return M
