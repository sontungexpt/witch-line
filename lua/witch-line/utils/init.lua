local M = {}
local vim = vim
local uv = vim.uv or vim.loop

M.debounce = function(func, delay)
	---@diagnostic disable-next-line: undefined-field
	local timer = uv.new_timer()
	local is_running = false
	return function(...)
		if is_running then
			timer:stop()
		end
		is_running = true
		local args = { ... }
		timer:start(
			delay,
			0,
			vim.schedule_wrap(function()
				is_running = false
				---@diagnostic disable-next-line: deprecated
				func(unpack(args))
			end)
		)
	end
end

return M
