local vim, next, type, ipairs, pairs = vim, next, type, ipairs, pairs
local api, uv = vim.api, vim.uv or vim.loop

local M = {}

local TIMER_TICK = 1000 -- 1 second

local renderer = require("witch-line.core.renderer")
local Component = require("witch-line.core.Comp")

local components, comps_size = {}, 0

local main_timer, sub_timers = nil, nil
local augroup, events, user_events = nil, {}, {}

local function registry_events(comp)
	local es, ues = comp.events, comp.user_events
	if es then
		for e, enabled in pairs(es) do
			if enabled then
				events[e] = true
			end
		end
	end
	if ues then
		for e, enabled in pairs(ues) do
			if enabled then
				user_events[e] = true
			end
		end
	end
end

local function on_timer()
	for i = 1, comps_size do
		local comp = components[i]
		renderer.update_comp(comp)
	end
end

local function registry_timer(comp)
	local timing = comp.timing
	if not timing then
		return
	elseif type(timing) == "number" and timing ~= TIMER_TICK then
		sub_timers = sub_timers or {}
		local new_len = #sub_timers + 1
		---@diagnostic disable-next-line: undefined-field
		sub_timers[new_len] = uv.new_timer()
		sub_timers[new_len]:start(0, timing, vim.schedule_wrap(on_timer))
	elseif not main_timer then
		---@diagnostic disable-next-line: undefined-field
		main_timer = uv.new_timer()
		main_timer:start(0, TIMER_TICK, vim.schedule_wrap(on_timer))
	end
end
--- Handle events for components.
--- @param event string The event name.
--- @param key "events" | "user_events"  The key to access the events table.
local function on_event(event, key)
	for i = 1, comps_size do
		local comp = components[i]
		local es = comp[key]
		if es and es[event] then
			renderer.update_comp(comp)
		end
	end
end

local function init_autocmd()
	local tbl_keys = require("witch-line.utils.tbl").tbl_keys
	local es, eslen = tbl_keys(events)
	if eslen > 0 then -- has nvim events
		augroup = augroup or api.nvim_create_augroup("WitchLine", { clear = true })
		api.nvim_create_autocmd(es, {
			group = augroup,
			callback = function(e)
				on_event(e.event, "events")
			end,
		})
	end
	local ues, ueslen = tbl_keys(user_events)
	if ueslen > 0 then -- has user events
		augroup = augroup or api.nvim_create_augroup("WitchLineUser", { clear = true })
		api.nvim_create_autocmd("User", {
			pattern = ues,
			group = augroup,
			callback = function(e)
				on_event(e.match, "user_events")
			end,
		})
	end
end

---
---@param comp Component|string
local function registry_comp(comp)
	local comp_type = type(comp)
	if comp_type == "table" then
		Component.new(comp, function(node)
			-- just manage the updatable Component
			if type(node.update) == "function" then
				comps_size = comps_size + 1
				components[comps_size] = node
				registry_timer(comp)
				registry_events(comp)
			end
		end)
	end
	init_autocmd()
end

M.setup = function(configs)
	for _, c in ipairs(configs.components) do
		registry_comp(c)
	end
	init_autocmd()
end

return M
