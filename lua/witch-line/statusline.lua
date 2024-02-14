local vim = vim
local api = vim.api
local opt = vim.opt
local uv = vim.uv or vim.loop
local schedule = vim.schedule
local autocmd = api.nvim_create_autocmd
local augroup = api.nvim_create_augroup

local cache_module = require("witch-line.cache")

local Statusline = {}

local type = type
local ipairs = ipairs
local concat = table.concat

local PLUG_NAME = "witch-line"
local COMP_DIR = "witch-line.components."

local values_len = 0
local values = {}

local length = 0
local components = {}

local is_hidden = false
local group_id = augroup(PLUG_NAME, { clear = true })
local timer_ids = {}
local cached, cache = cache_module.read()

local inherit_attrs = {
	styles = true,
	configs = true,
	static = true,
	padding = true,
}

local function get_global_augroup()
	return group_id or (function()
		group_id = augroup(PLUG_NAME, { clear = true })
		return group_id
	end)()
end

--- Search up the component tree for a key
--- If the nearest parent has the key, return the value and the parent
--- @param comp table : component to search from
function Statusline.search_up(comp, key)
	while comp do
		if comp[key] then
			return comp[key], comp
		end
		comp = comp.__parent
	end
end

---
-- Searches for a specified set of keys deeply within a component and its parent components.
-- @param comp The starting component to search from.
-- @param ... A list of keys to search deeply for.
-- @return The component containing the keys if found, along with its parent component.
function Statusline.deep_search_up(comp, ...)
	local keys = { ... }
	local left = #keys
	while comp do
		local found = comp
		for _, key in ipairs(keys) do
			if not type(found[key]) == "table" then
				break
			end
			found = found[key]
		end
		if found and left == 0 then
			return found, comp
		end
		comp = comp.__parent
	end
end

local function call(func, ...)
	return type(func) == "function" and func(...)
end

local function call_comp_func(func, comp, ...)
	local get_shared = function(key)
		while comp do
			local shared = comp.shared
			if shared == "table" and shared[key] then
				return shared[key]
			end
			comp = comp.__parent
		end
	end

	if type(func) == "function" then
		return func(comp.configs, comp.__state, get_shared, comp, ...)
	end
end

local function tbl_contains(tbl, value)
	return tbl[value] or require("witch-line.util").arr_contains(tbl, value)
end

local function should_hidden(excluded, bufnr)
	return tbl_contains(excluded.filetypes, api.nvim_buf_get_option(bufnr or 0, "filetype"))
		or tbl_contains(excluded.buftypes, api.nvim_buf_get_option(bufnr or 0, "buftype"))
end

local function handle_comp_highlight(update_value, comp)
	local highlight = require("witch-line.highlight")

	local styles = comp.styles

	local force = type(styles) == "function"
	if force then
		styles = call_comp_func(comp.styles, comp)
	end

	if highlight.is_hl_name(styles) then
		return highlight.add_hl_name(update_value, comp.styles)
	end

	comp.__hl_name = comp.__hl_name or highlight.gen_hl_name(PLUG_NAME)
	highlight.hl(comp.__hl_name, styles, force)

	return highlight.add_hl_name(update_value, comp.__hl_name)
end

local compile = function(configs)
	local cleared = cache_module.clear()

	if cleared then
		api.nvim_del_augroup_by_id(get_global_augroup())
		group_id = nil
		for _, timer in ipairs(timer_ids) do
			timer:stop()
		end

		length = 0
		components = {}

		values_len = 0
		values = {}

		cached, cache = cache_module.read()

		Statusline.setup(configs)
		Statusline.update_all()
		Statusline.render()
	end
end
local function add_padding(update_value, comp)
	local padding = comp.padding
	if update_value == "" then
		return ""
	elseif not padding then
		return " " .. update_value .. " "
	elseif type(padding) == "number" then
		if padding < 1 then
			return update_value
		end
		local space = string.rep(" ", math.floor(padding))
		return space .. update_value .. space
	elseif type(padding) == "table" then
		local left_padding = type(padding.left) == "number" and string.rep(" ", math.floor(padding.left)) or ""
		local right_padding = type(padding.right) == "number" and string.rep(" ", math.floor(padding.right)) or ""
		return left_padding .. update_value .. right_padding
	elseif type(padding) == "function" then
		local new_value = call_comp_func(padding, comp)
		if type(new_value) == "string" then
			return new_value
		end
		return update_value
	end
end

--- Update the component
--- @param comp table : component to update
--- @param traverse boolean|nil : If true, go through all the components and return a flat list of updated values instead of updating the pos in statusline
--- @param flat_tree table|nil : table to store the flat list of updated values
local function update(comp, traverse, flat_tree)
	if type(comp) ~= "table" then -- make sure that the component is valid and not a special component
		if comp == nil then
			compile(require("witch-line.config").get_config())
		end
		return
	end

	local should_display = call_comp_func(comp.condition, comp)

	if should_display == false then
		values[comp.__pos or -1] = ""
		return
	end

	call_comp_func(comp.pre_update, comp)

	for _, child in ipairs(comp) do -- update children first
		update(child, traverse, flat_tree)
	end

	if comp.update then
		local update_value = call_comp_func(comp.update, comp)
		if type(update_value) == "string" then -- plugin do
			if traverse then
				flat_tree[#flat_tree + 1] = handle_comp_highlight(add_padding(update_value, comp), comp)
			else
				values[comp.__pos or -1] = handle_comp_highlight(add_padding(update_value, comp), comp)
			end
		elseif type(update_value) == "function" then -- user defined update function
			update_value = call_comp_func(update_value, comp)
			if type(update_value) == "string" then
				if traverse then
					flat_tree[#flat_tree + 1] = update_value
				else
					values[comp.__pos or -1] = update_value
				end
			end
		else
			if type(update_value) ~= "string" then
				require("witch-line.util.notify").error(
					string.format(
						"component %s update() must return string or table of string or table of {string, table}",
						type(comp) == "string" and comp or comp.name or ""
					)
				)
				return
			end
		end
	end

	call_comp_func(comp.post_update, comp)
end

--- Get the first group component
--- @param comp table : component to search from
--- @return table|nil : component has group
local function found_group_comp(comp)
	while comp do
		if comp.group then
			return comp
		end
		comp = comp.__parent
	end
end

function Statusline.update_comp(comp)
	local group_comp = found_group_comp(comp)

	if group_comp then -- component is part of a group so update the group instead
		local update_values = {}
		update(group_comp, true, update_values)
		values[group_comp.__pos or -1] = concat(update_values)
		return
	end
	update(comp)
end

function Statusline.update_all()
	for i = 1, length do
		Statusline.update_comp(components[i])
	end
end

local function cache_event(event, index, cache_key)
	local events_dict = cache.events[cache_key]
	local indexes = events_dict[event]
	if indexes == nil then
		events_dict[event] = { index }
		events_dict.keys_len = events_dict.keys_len + 1
		events_dict.keys[events_dict.keys_len] = event
	else
		indexes[#indexes + 1] = index
	end
end

local function handle_comp_events(comp, index)
	local nvim_event = comp.event
	if type(nvim_event) == "table" then
		for _, e in ipairs(nvim_event) do
			cache_event(e, index, "nvim")
		end
	elseif type(nvim_event) == "string" then
		cache_event(nvim_event, index, "nvim")
	end

	local user_event = comp.user_event
	if type(user_event) == "string" then
		cache_event(user_event, index, "user")
	elseif type(user_event) == "table" then
		for _, e in ipairs(user_event) do
			cache_event(e, index, "user")
		end
	end
end

local function handle_comp_timing(comp, index)
	if comp.timing == true then
		cache.timer[#cache.timer + 1] = index
	elseif type(comp.timing) == "number" then
		if timer_ids[index] == nil then
			timer_ids[index] = uv.new_timer()
		end
		timer_ids[index]:start(
			0,
			comp.timing,
			vim.schedule_wrap(function()
				Statusline.update_comp(comp)
				Statusline.render()
			end)
		)
	end
end

local function init_cached_autocmds()
	local nvim = cache.events.nvim
	local user = cache.events.user

	local group = get_global_augroup()

	if nvim.keys_len > 0 then -- has nvim events
		autocmd(nvim.keys, {
			group = group,
			callback = function(e)
				Statusline.run(e.event)
			end,
		})
	end
	if user.keys_len > 0 then -- has user events
		autocmd("User", {
			pattern = user.keys,
			group = group,
			callback = function(e)
				Statusline.run(e.match, true)
			end,
		})
	end
end

local function init_cached_timers()
	if cache.timer[1] ~= nil then -- has timing components
		if timer_ids[PLUG_NAME] == nil then
			timer_ids[PLUG_NAME] = uv.new_timer()
		end
		timer_ids[PLUG_NAME]:start(0, 1000, vim.schedule_wrap(Statusline.run))
	end
end

local auto_hidden = function(configs)
	local event_trigger = false
	autocmd({ "BufEnter", "WinEnter" }, {
		group = get_global_augroup(),
		callback = function()
			if not event_trigger then
				event_trigger = true
				schedule(function()
					if should_hidden(configs.disabled) then
						is_hidden = true
					end
					Statusline.render()
				end, 20)
			end
		end,
	})

	autocmd({ "BufLeave", "WinLeave" }, {
		group = get_global_augroup(),
		callback = function()
			event_trigger = false
			if is_hidden then
				is_hidden = false
				Statusline.update_all()
			end
		end,
	})
end

--- Add a component to the statusline
--- @param comp table|string|number : component to add
--- @param seen table : table to keep track of seen components
--- @param parent table|nil : parent component
--- @param group boolean|nil : whether the component is part of a group
local function add_comp(comp, seen, parent, group)
	if type(comp) ~= "table" then
		if type(comp) == "string" then
			if comp == "%=" then -- special component
				values_len = values_len + 1
				values[values_len] = "%="
				return
			else
				local ok = false
				ok, comp = pcall(require, COMP_DIR .. comp)
				if not ok then
					return -- invalid component
				end
			end
		elseif type(comp) == "number" then -- special component
			values_len = values_len + 1
			values[values_len] = string.rep(" ", math.floor(comp))
			return
		end
	elseif comp.from ~= nil then
		local ok, default = pcall(require, COMP_DIR .. tostring(comp.from))
		if not ok then
			return -- invalid component
		end
		comp = require("witch-line.config").merge_config(default, comp.ovveride, true)
	end

	-- make a copy of the component if it has been seen before
	if seen[comp] then
		comp = require("witch-line.config").merge_config({}, comp, true)
	else
		seen[comp] = true
	end

	if parent then
		comp.__parent = parent

		-- inherit attributes from the parent
		setmetatable(comp, {
			__index = function(_, key)
				if inherit_attrs[key] then
					return parent[key]
				end
			end,
		})
	end

	-- initialize the component
	comp.__state = call(comp.init, comp.configs, comp)

	length = length + 1

	if not cached then
		handle_comp_events(comp, length)
		handle_comp_timing(comp, length)
	end

	components[length] = comp

	group = group or comp.group

	for _, child in ipairs(comp) do
		add_comp(child, seen, comp, group)
	end

	if not parent or not group then
		values_len = values_len + 1
		values[values_len] = comp.lazy == false and Statusline.update_comp(comp) or ""
		comp.__pos = values_len
	else
		comp.__pos = -1 -- make sure that the update function doesn't meet errors
	end
end

function Statusline.run(event_name, is_user_event)
	if is_hidden then
		return
	end

	schedule(function()
		local event_dict = is_user_event and cache.events.user or cache.events.nvim
		local indexes = event_name and event_dict[event_name] or cache.timer

		---@diagnostic disable-next-line: param-type-mismatch
		for _, index in ipairs(indexes) do
			Statusline.update_comp(components[index])
		end

		Statusline.render()
	end, 0)
end

function Statusline.render()
	if is_hidden then
		opt.statusline = " "
	else
		local str = concat(values)
		opt.statusline = str ~= "" and str or " "
	end
end

function Statusline.setup(configs)
	local seen = {}

	for _, comp in ipairs(configs.components) do
		add_comp(comp, seen)
	end

	init_cached_autocmds()
	init_cached_timers()

	auto_hidden(configs)

	autocmd("VimLeavePre", {
		group = get_global_augroup(),
		callback = function()
			cache_module.cache(cache)
		end,
	})

	autocmd("Colorscheme", {
		group = get_global_augroup(),
		callback = function()
			require("witch-line.highlight").colorscheme()
		end,
	})

	api.nvim_create_user_command("WitchLineCompile", function()
		compile(configs)
	end, {
		nargs = 0,
	})
end

return Statusline
