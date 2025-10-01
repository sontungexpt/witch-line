local require = require
local M = {}

---@alias BufDisabled {filetypes: string[], buftypes: string[]}
---@class UserConfig : table
---@field abstract CombinedComponent[]|nil Abstract components that are not rendered directly.
---@field components CombinedComponent[] Components that are rendered in the statusline.
---@field disabled BufDisabled|nil A table containing filetypes and buftypes where the statusline is disabled.

--- @param user_configs UserConfig|nil user_configs
M.setup = function(user_configs)
	local tbl_utils = require("witch-line.utils.tbl")
	local checksum = tostring(tbl_utils.fnv1a32_hash(user_configs, "version"))


	if type(user_configs) ~= "table" then
		user_configs = {
			components = require("witch-line.constant.default"),
		}
	elseif type(user_configs.components) ~= "table" or not next(user_configs.components) then
		user_configs.components = require("witch-line.constant.default")
	end


	local Cache = require("witch-line.cache")

	local CACHE_MODS = {
		"witch-line.core.handler",
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
		require("witch-line.core.handler").setup(user_configs, true)
		local disabled = DataAccessor.get("Disabled")
		require("witch-line.core.statusline").setup(disabled)
		goto FINALIZE
	end

	require("witch-line.core.handler").setup(user_configs, false)
	require("witch-line.core.statusline").setup(user_configs.disabled)

	::FINALIZE::


	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if not Cache.loaded() then
				local DataAccessor = Cache.DataAccessor
				for i = 1, #CACHE_MODS do
					require(CACHE_MODS[i]).on_vim_leave_pre(DataAccessor)
				end

				if type(user_configs.disabled) == "table" then
					DataAccessor.set("Disabled", user_configs.disabled)
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
