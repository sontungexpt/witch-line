local M = {}

M.setup = function(user_configs)
	local configs = require("witch-line.config").set_user_config(user_configs)
	require("witch-line.core.flat.handler").setup(configs)
end

return M
