local require = require
local M = {}

--- @param user_configs Config user_configs
M.setup = function(user_configs)
	local CacheMod = require("witch-line.cache")

	local CACHE_MODS = {
		"witch-line.core.handler",
		"witch-line.core.statusline",
		"witch-line.core.CompManager",
		"witch-line.utils.highlight",
		"witch-line.config",
	}

	if CacheMod.cache_readable() then
		CacheMod.read_async(function(struct)
			if struct then
				local undos = {}
				for i = 1, #CACHE_MODS do
					undos[i] = require(CACHE_MODS[i]).load_cache()
				end

				-- use cache first
				require("witch-line.core.handler").setup(nil, true)

				local ConfMod = require("witch-line.config")

				-- check if user_configs is changed
				if ConfMod.user_configs_changed(struct.UserConfigs, user_configs) then
					CacheMod.clear()
					for i = 1, #undos do
						undos[i]()
					end
					local configs = ConfMod.set_user_config(user_configs)
					require("witch-line.core.handler").setup(configs, false)
				end
				return
			end

			local ConfMod = require("witch-line.config")
			local configs = ConfMod.set_user_config(user_configs)
			require("witch-line.core.handler").setup(configs, false)
		end)
	else
		local ConfMod = require("witch-line.config")
		local configs = ConfMod.set_user_config(user_configs)
		require("witch-line.core.handler").setup(configs, false)
	end

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			for i = 1, #CACHE_MODS do
				require(CACHE_MODS[i]).on_vim_leave_pre()
			end
			CacheMod.save()
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
