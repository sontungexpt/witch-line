local CacheMod = require("witch-line.cache")
local type, ipairs = type, ipairs
local bo = vim.bo

local M = {}

---@class Config
---@field abstract Component[] Abstract components that are not rendered directly.
---@field components Component[] Components that are rendered in the statusline.
---@field disabled {filetypes: string[], buftypes: string[]} A table containing filetypes and buftypes where the statusline is disabled.

---@type Config
local default_configs = {
	abstract = {},
	components = require("witch-line.constant.default"),
	disabled = {
		filetypes = {},
		buftypes = {
			"terminal",
		},
	},
}

--- Converts component objects in a table to their IDs.
--- @param components Component[] A table of components, which can be either strings or tables with an `id` field.
--- @return Id[] A table of component IDs.
local components_to_ids = function(components)
	local ids = {}
	for i, comp in ipairs(components) do
		local comp_type = type(comp)
		if comp_type == "table" then
			ids[i] = comp.id
		elseif comp_type == "string" then
			ids[i] = comp
		end
	end
	return ids
end

local simplyfy_configs = function(configs)
	if type(configs) ~= "table" then
		return configs
	end

	local simplified = vim.deepcopy(configs)
	if type(simplified.components) == "table" then
		simplified.components = components_to_ids(simplified.components)
	end
	if type(simplified.abstract) == "table" then
		simplified.abstract = components_to_ids(simplified.abstract)
	end
	return simplified
end

M.on_vim_leave_pre = function()
	CacheMod.cache(default_configs.disabled, "Disabled")
end

M.load_cache = function()
	local before_configs = default_configs

	local DisabledCache = require("witch-line.cache").get("Disabled")
	default_configs.disabled = DisabledCache or default_configs.disabled

	return function()
		default_configs = before_configs
	end
end

local same_type = function(a, b)
	return type(a) == type(b)
end

local same_comps = function(uc_comps, cache_comps)
	for i, comp in ipairs(uc_comps) do
		local comp_type = type(comp)
		if
			(comp_type == "string" and comp ~= cache_comps[i])
			or (comp_type == "table" and comp.id ~= cache_comps[i])
		then
			return true
		end
	end
end

--- @param cache Config
--- @param user_configs Config
M.user_configs_changed = function(cache, user_configs)
	return false
end

function M.is_buf_disabled(bufnr)
	local buf_o = bo[bufnr]
	local filetype = buf_o.filetype
	local buftype = buf_o.buftype
	local disabled = default_configs.disabled

	for _, ft in ipairs(disabled.filetypes) do
		if filetype == ft then
			return true
		end
	end

	for _, bt in ipairs(disabled.buftypes) do
		if buftype == bt then
			return true
		end
	end
	return false
end

local function merge_user_config(defaults, overrides)
	-- Handle nil cases immediately
	if overrides == nil then
		return defaults
	elseif defaults == nil then
		return overrides
	end

	local default_type = type(defaults)
	local override_type = type(overrides)

	-- Handle type mismatch
	if default_type ~= override_type then
		return defaults
	-- Handle non-tables
	elseif default_type ~= "table" then
		return overrides
	end

	--- Utilize the available table
	if next(defaults) == nil then
		return overrides
	end

	-- Deep merge dictionary-like tables
	for key, value in pairs(overrides) do
		defaults[key] = merge_user_config(defaults[key], value)
	end

	return defaults
end

--- Sets user configurations by merging them with the default configurations.
--- This function allows users to override the default settings with their own configurations.
--- It merges the user-provided configurations with the default configurations, ensuring that any missing keys in the user configuration will retain their default values.
--- @param user_configs Config A table containing user-defined configurations to be merged with the default configurations.
--- @return Config merged_configs The merged configuration table, which includes both default and user-defined settings.
M.set_user_config = function(user_configs)
	CacheMod.cache(simplyfy_configs(user_configs or {}), "UserConfigs")
	return merge_user_config(default_configs, user_configs)
end

--- Returns a read-only table containing the default configurations.
--- This table can be used to access the default components and other configurations.
--- @return Config configurations table
M.get = function()
	return default_configs
end

M.get_components = function()
	return default_configs.components
end

return M
