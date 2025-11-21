local M = {}

local levels = vim.log.levels
local notify = vim.notify
local schedule = vim.schedule

--- Displays an information message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts table|nil Optional options for the notification.
M.info = function(msg, opts)
	schedule(function()
		notify(msg, levels.INFO, opts or { title = "WitchLine Information" })
	end)
end

--- Displays a warning message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts table|nil Optional options for the notification.
M.warn = function(msg, opts)
	schedule(function()
		notify(msg, levels.WARN, opts or { title = "WitchLine Warning" })
	end)
end

--- Displays an error message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts table|nil Optional options for the notification.
M.error = function(msg, opts)
	schedule(function()
		notify(msg, levels.ERROR, opts or { title = "WitchLine Error" })
	end)
end

return M
