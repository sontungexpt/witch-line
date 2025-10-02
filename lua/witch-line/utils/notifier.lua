local M = {}

local levels = vim.log.levels
local notify = vim.notify
local schedule = vim.schedule

M.info = function(msg, opts)
	schedule(function()
		notify(msg, levels.INFO, opts or { title = "WitchLine Information" })
	end)
end

M.warn = function(msg, opts)
	schedule(function()
		notify(msg, levels.WARN, opts or { title = "WitchLine Warning" })
	end)
end

M.error = function(msg, opts)
	schedule(function()
		notify(msg, levels.ERROR, opts or { title = "WitchLine Error" })
	end)
end

return M
