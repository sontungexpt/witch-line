local M = {}

local levels = vim.log.levels
local notify = vim.notify
local schedule_wrap = vim.schedule_wrap

--- Displays an information message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts table|nil Optional options for the notification.
M.info = schedule_wrap(function(msg, opts)
    notify(msg, levels.INFO, opts or { title = "WitchLine Information" })
end)

--- Displays a warning message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts table|nil Optional options for the notification.
M.warn = schedule_wrap(function(msg, opts)
    notify(msg, levels.WARN, opts or { title = "WitchLine Warning" })
end)

--- Displays an error message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts table|nil Optional options for the notification.
M.error = schedule_wrap(function(msg, opts)
    notify(msg, levels.ERROR, opts or { title = "WitchLine Error" })
end)

return M
