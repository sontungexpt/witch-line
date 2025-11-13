local require, vim = require, vim

local M = {}

---@alias UserConfig.Disabled {filetypes: string[], buftypes: string[]}
--- The full user configuration for Witch-Line.
--- This table defines how the statusline is structured, behaves, and cached.
--- Each field corresponds to a part of the plugin’s behavior or data model.
---@class UserConfig : table
--- Abstract components that are **not directly rendered**,
--- but may be inherited or referenced by other components.
--- Typically used to define shared layouts or reusable base definitions.
---@field abstract CombinedComponent[]|nil
---
--- Components that are **actually rendered** in the statusline.
--- These can inherit or reference abstract components to build complex layouts.
---@field components CombinedComponent[]
---
--- Defines which filetypes and buftypes should disable the statusline completely.
--- Useful for temporary, floating, or special-purpose buffers.
---@field disabled UserConfig.Disabled|nil
---
--- Enables deep scanning of the plugin directory for detecting cache expiration.
--- When `true`, Witch-Line will perform a full recursive scan (slower but more accurate).
--- When `false` or `nil`, only the main plugin folder’s timestamp and size are checked (faster).
---@field cache_full_scan boolean|nil
---@field cache_cleared_notification boolean|nil

--- Use default configs if missing
--- @param user_configs UserConfig|nil user_configs to check
--- @return UserConfig user_configs with defaults applied
local use_default_config = function(user_configs)
	if type(user_configs) ~= "table" then
		user_configs = {}
	end

	if type(user_configs.components) ~= "table" or not next(user_configs.components) then
		user_configs.components = require("witch-line.constant.default")
	end
	if type(user_configs.disabled) ~= "table" then
		user_configs.disabled = {
			buftypes = {
				"terminal",
			},
		}
	end
	return user_configs
end

--- @param user_configs UserConfig|nil user_configs
M.setup = function(user_configs)
	local Cache = require("witch-line.cache")
	local DataAccessor = Cache.read(user_configs)
	user_configs = use_default_config(user_configs)

	local CACHE_MODS = {
		"witch-line.core.manager.event",
		"witch-line.core.manager.timer",
		"witch-line.core.manager",
		"witch-line.core.statusline",
		"witch-line.core.highlight",
	}

	if DataAccessor then
		for i = 1, #CACHE_MODS do
			require(CACHE_MODS[i]).load_cache(DataAccessor)
		end
	end

	require("witch-line.core.handler").setup(user_configs, DataAccessor)
	require("witch-line.core.statusline").setup(user_configs.disabled)

	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		callback = function()
			if not Cache.loaded() then
				DataAccessor = Cache.DataAccessor
				for i = 1, #CACHE_MODS do
					require(CACHE_MODS[i]).on_vim_leave_pre(DataAccessor)
				end
				Cache.save()
			end
		end,
	})

	vim.api.nvim_create_autocmd("CmdlineEnter", {
		once = true,
		callback = function()
			require("witch-line.command")
		end,
	})
end

return M
