local require = require
local M = {}

M.setup = function(user_configs)
	local CacheMod = require("witch-line.cache")

	local cache_modules = {
		"witch-line.core.handler",
		"witch-line.core.statusline",
		"witch-line.core.CompManager",
		"witch-line.utils.highlight",
	}

	CacheMod.read()
	for i = 1, #cache_modules do
		require(cache_modules[i]).load_cache()
	end

	local configs = require("witch-line.config").set_user_config(user_configs)
	require("witch-line.core.handler").setup(configs)

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if not CacheMod.has_cached() then
				for _, mod in ipairs(cache_modules) do
					require(mod).cache()
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
