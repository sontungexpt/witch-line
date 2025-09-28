local CacheMod = require("witch-line.cache")
local type, ipairs = type, ipairs
local bo = vim.bo

local M = {}

---@class Config : table
---@field abstract Component[] Abstract components that are not rendered directly.
---@field components Component[] Components that are rendered in the statusline.
---@field disabled nil|{filetypes: string[], buftypes: string[]} A table containing filetypes and buftypes where the statusline is disabled.

---@type Config
local default_configs = {
	abstract = {},
	components = {},
	disabled = {
		filetypes = {},
		buftypes = {
			"terminal",
		},
	},
}

---  Called before Vim exits.
---  This function sets the disabled configurations in the DataAccessor to ensure that the statusline is
---  disabled for the specified filetypes and buftypes when Vim is closed.
---  @param DataAccessor Cache.DataAccessor An object that provides access to configuration data.
M.on_vim_leave_pre = function(DataAccessor)
	DataAccessor.set("Disabled", default_configs.disabled)
end

--- Loads cached configurations and updates the default configurations accordingly.
--- This function retrieves the cached disabled configurations and updates the default configurations.
--- It returns a function that, when called, restores the default configurations to their state before loading the cache.
--- @param DataAccessor Cache.DataAccessor An object that provides access to configuration data.
--- @return function undo A function that restores the default configurations to their previous state.
M.load_cache = function(DataAccessor)
	local before_configs = default_configs

	default_configs.disabled = DataAccessor.get("Disabled") or default_configs.disabled

	return function()
		default_configs = before_configs
	end
end

function M.is_buf_disabled(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local disabled = default_configs.disabled
	if not disabled then
		return false
	end
	local buf_o = bo[bufnr]
	local filetype = buf_o.filetype
	local buftype = buf_o.buftype

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

		-- both are table from here
	elseif next(overrides) == nil then
		return defaults
	elseif next(defaults) == nil then
		--- Utilize the available table
		return overrides
	elseif vim.islist(defaults) and vim.islist(overrides) then
		return vim.list_extend(defaults, overrides)
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
	local configs = merge_user_config(default_configs, user_configs)
	if not next(configs.components) then
		configs.components = require("witch-line.constant.default")
	end
	return configs
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
