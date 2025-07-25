local M = {}

M.setup = function(user_configs)
	local uv = vim.uv or vim.loop
	local locked = true
	local CacheMod = require("witch-line.cache")

	local cache_mods = {
		"witch-line.core.handler",
		"witch-line.core.statusline",
		"witch-line.core.CompManager",
		"witch-line.utils.highlight",
	}

	-- CacheMod.read_async(function(data)
	-- 	error(vim.inspect(data or nil))
	-- 	locked = false

	-- 	for _, mod in ipairs(cache_mods) do
	-- 		require(mod).load_cache(data)
	-- 	end

	-- 	-- if CacheMod.has_cached() then
	-- 	-- 	-- error(vim.inspect(data or nil))
	-- 	-- 	-- error(vim.inspect(data or nil))
	-- 	-- end
	-- end)
	local struct = CacheMod.read()
	local configs = require("witch-line.config").set_user_config(user_configs)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			-- if CacheMod.has_cached() then
			-- 	return
			-- end
			for _, mod in ipairs(cache_mods) do
				require(mod).cache()
			end
			CacheMod.save()
		end,
	})

	-- local timer = uv.new_timer()
	-- if timer then
	-- 	timer:start(
	-- 		0,
	-- 		100,
	-- 		vim.schedule_wrap(function()
	-- 			if not locked then
	-- 				require("witch-line.core.handler").setup(configs)
	-- 				timer:stop()
	-- 				timer:close()
	-- 				timer = nil
	-- 			end
	-- 		end)
	-- 	)
	-- end

	require("witch-line.core.handler").setup(configs)
end

return M
