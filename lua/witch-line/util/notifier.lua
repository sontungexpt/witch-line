local vim = vim
local levels = vim.log.levels

local M = {}


--- Displays an information message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts? table Optional options for the notification.
M.info = vim.schedule_wrap(function(msg, opts)
    vim.notify(msg, levels.INFO, opts or { title = "WitchLine Info" })
end)

--- Displays a warning message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts? table Optional options for the notification.
M.warn = vim.schedule_wrap(function(msg, opts)
    vim.notify(msg, levels.WARN, opts or { title = "WitchLine Warn" })
end)

--- Displays an error message using `vim.notify`.
--- @param msg string The message to display.
--- @param opts? table Optional options for the notification.
M.error = vim.schedule_wrap(function(msg, opts)
    vim.notify(msg, levels.ERROR, opts or { title = "WitchLine Error" })
end)

return M
