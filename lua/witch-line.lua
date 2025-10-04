local require, vim = require, vim
local M = {}

---@alias BufDisabled {filetypes: string[], buftypes: string[]}
---@class UserConfig : table
---@field abstract CombinedComponent[]|nil Abstract components that are not rendered directly.
---@field components CombinedComponent[] Components that are rendered in the statusline.
---@field disabled BufDisabled|nil A table containing filetypes and buftypes where the statusline is disabled.

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
	local tbl_utils = require("witch-line.utils.tbl")
	local checksum = tostring(tbl_utils.fnv1a32_hash(user_configs, "version"))

	user_configs = use_default_config(user_configs)


	local Cache = require("witch-line.cache")

	local CACHE_MODS = {
		"witch-line.core.handler.event",
		"witch-line.core.handler.timer",
		"witch-line.core.statusline",
		"witch-line.core.CompManager",
		"witch-line.core.highlight",
	}

	local DataAccessor = Cache.read(checksum)

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
				Cache.save(checksum)
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
