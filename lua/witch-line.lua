local require = require
local M = {}

--- @param user_configs Config|nil user_configs
M.setup = function(user_configs)
	-- temp for test user_configs
	if not user_configs or (type(user_configs) == "table" and not next(user_configs)) then
		user_configs = {
			components = {
				"mode",
				"file.name",
				"file.icon",
				"%=",
				"copilot",
				"diagnostic.error",
				"diagnostic.warn",
				"diagnostic.info",
				"encoding",
				"cursor.pos",
				"cursor.progress",
			},
		}
	end

	local Cache = require("witch-line.cache")
	local ConfMod = require("witch-line.config")

	local CACHE_MODS = {
		"witch-line.core.handler",
		"witch-line.core.handler.timer",
		"witch-line.core.statusline",
		"witch-line.core.CompManager",
		"witch-line.core.highlight",
		"witch-line.config",
	}
	local tbl_utils = require("witch-line.utils.tbl")
	local checksum = tostring(tbl_utils.fnv1a32_hash(user_configs))

	if Cache.cache_file_readable() then
		local DataAccessor = Cache.read(checksum)
		if DataAccessor then
			for i = 1, #CACHE_MODS do
				require(CACHE_MODS[i]).load_cache(DataAccessor)
			end
			require("witch-line.core.handler").setup(nil, true)
		else
			local configs = ConfMod.set_user_config(user_configs)
			require("witch-line.core.handler").setup(configs, false)
		end
	end

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if not Cache.loaded() then
				for i = 1, #CACHE_MODS do
					require(CACHE_MODS[i]).on_vim_leave_pre(Cache.DataAccessor)
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
