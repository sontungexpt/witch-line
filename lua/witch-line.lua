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

	local CacheMod = require("witch-line.cache")
	local ConfMod = require("witch-line.config")

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
					undos[i] = require(CACHE_MODS[i]).load_cache(CacheMod)
				end
				-- use cache first
				require("witch-line.core.handler").setup(nil, true)
				if not ConfMod.user_configs_changed(user_configs) then
					return
				end

				-- if user_configs is changed, clear cache and run undos
				CacheMod.clear()
				for i = 1, #undos do
					undos[i]()
				end
			end
			local configs = ConfMod.set_user_config(user_configs)
			require("witch-line.core.handler").setup(configs, false)
		end)
	else
		local configs = ConfMod.set_user_config(user_configs)
		require("witch-line.core.handler").setup(configs, false)
	end

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if not CacheMod.loaded() then
				for i = 1, #CACHE_MODS do
					require(CACHE_MODS[i]).on_vim_leave_pre(CacheMod)
				end
				CacheMod.save()
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
