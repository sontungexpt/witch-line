local require, type = require, type
local nvim_create_autocmd = vim.api.nvim_create_autocmd

local M = {}

--- @class UserConfig.Cache
--- @field enabled? boolean Enable cache. Default false.
--- @field full_scan? boolean Perform full plugin scan for cache expiration. Default false.
--- @field notification? boolean Show notification when cache is cleared. Default true.
--- @field func_strip? boolean Strip debug info when caching dumped functions. Default false.

--- @class UserConfig.Disabled
--- @field filetypes? string[] The filetypes where statusline is disabled.
--- @field buftypes? string[] The buftypes where statusline is disabled.
---
--- @class UserConfig.Statusline
--- @field global CombinedComponent The global statusline components.
--- @field win? fun(winid: integer): CombinedComponent|nil The per-window statusline components.
---
--- The full user configuration for Witch-Line.
--- @class UserConfig : table
---
--- Abstract components that are **not directly rendered**,
--- but may be inherited or referenced by other components.
--- Typically used to define shared layouts or reusable base definitions.
--- @field abstracts? CombinedComponent[]
--- @field statusline UserConfig.Statusline The final statusline configuration.
--- @field disabled UserConfig.Disabled Filetypes/buftypes where statusline is disabled.
--- @field cache UserConfig.Cache Configuration for the cache.
--- @field auto_theme? boolean Whether to automatically adjust the theme. If it is set to false the `auto_theme` field of the component will be ignored.

--- Apply missing default configuration values to the user-provided config.
--- Ensures required fields exist (such as `disabled` and `components`)
--- and fills them with the default values when absent or invalid.
---
--- @param user_configs UserConfig|nil The user configuration table to normalize.
--- @return UserConfig normalized The user config with defaults safely applied.
local use_default_config = function(user_configs)
	user_configs = type(user_configs) == "table" and user_configs or {}
	if type(user_configs.disabled) ~= "table" then
		user_configs.disabled = {
			buftypes = {
				"terminal",
			},
		}
	end

	if type(user_configs.statusline) ~= "table" then
		---@diagnostic disable-next-line: missing-fields
		user_configs.statusline = {}
	end

	return user_configs
end

--- Apply default components to the statusline if it doesn't exist.
--- @param statusline UserConfig.Statusline the statusline
--- @return UserConfig.Statusline statusline the changed statusline
local apply_statusline_default_components = function(statusline)
	local global = statusline.global
	if type(global) ~= "table" then
		statusline.global = require("witch-line.constant.default")
	end
	return statusline
end

--- @param user_configs? UserConfig user_configs
M.setup = function(user_configs)
	local cache_opts = type(user_configs) == "table" and user_configs.cache
	local CacheDataAccessor
	if type(cache_opts) == "table" and cache_opts.enabled then
		local Cache = require("witch-line.cache")
		local conf_checksum = Cache.config_checksum(user_configs)

		-- Read cache
		CacheDataAccessor = Cache.read(conf_checksum, cache_opts.full_scan, cache_opts.notification)

		-- Capture initial context of component so that when it is cached, the context can be restored
		require("witch-line.core.manager").set_captured_initial_context(true)

		local CACHE_MODS = {
			"witch-line.core.manager.event",
			"witch-line.core.manager.timer",
			"witch-line.core.manager",
			"witch-line.core.statusline",
			"witch-line.core.highlight",
		}

		nvim_create_autocmd("VimLeavePre", {
			once = true,
			callback = function()
				if not Cache.loaded() then
					CacheDataAccessor = Cache.DataAccessor
					for i = 1, #CACHE_MODS do
						require(CACHE_MODS[i]).on_vim_leave_pre(CacheDataAccessor)
					end

					Cache.save(conf_checksum, cache_opts.func_strip)
				end
			end,
		})

		if CacheDataAccessor then
			for i = 1, #CACHE_MODS do
				require(CACHE_MODS[i]).load_cache(CacheDataAccessor)
			end
		end
	end
	user_configs = use_default_config(user_configs)

	-- Cached is disabled or no cached data
	if not CacheDataAccessor then
		apply_statusline_default_components(user_configs.statusline)
	end

	-- Set auto theme
	if user_configs.auto_theme == false then
		require("witch-line.core.highlight").set_auto_theme(false)
	end

	-- Set up statusline
	require("witch-line.core.statusline").setup(user_configs.disabled)
	require("witch-line.core.handler").setup(user_configs, CacheDataAccessor)

	nvim_create_autocmd("CmdlineEnter", {
		once = true,
		callback = function()
			require("witch-line.command")
		end,
	})
end

return M
