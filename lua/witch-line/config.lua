local type, ipairs = type, ipairs
local bo = vim.bo

local M = {}

local default_configs = {
	-- components
	components = require("witch-line.constant.default"),
	disabled = {
		filetypes = {},
		buftypes = {
			"terminal",
		},
	},
}

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

M.set_user_config = function(user_configs)
	return merge_user_config(default_configs, user_configs)
end

M.get_config = function()
	return setmetatable({}, {
		__index = default_configs,
		__newindex = function()
			error("Attempt to modify read-only table")
		end,
	})
end

M.get_components = function()
	return default_configs.components
end

return M
