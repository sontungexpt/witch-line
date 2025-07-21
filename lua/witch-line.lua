local M = {}

M.setup = function(user_configs)
	local configs = require("witch-line.config").set_user_config(user_configs)

	require("witch-line.ui.renderer").setup(configs)

	-- local core = require("witch-line.statusline")
	-- core.setup(opts)
end

return M
