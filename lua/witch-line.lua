local config = require("witch-line.config")
local core = require("witch-line.statusline")

local M = {}

M.setup = function(user_opts)
	local opts = config.setup(user_opts)
	core.setup(opts)
end

return M
