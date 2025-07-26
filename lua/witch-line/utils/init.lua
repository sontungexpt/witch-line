local M = {}
local vim = vim
local uv = vim.uv or vim.loop

M.debounce = function(func, delay)
	local timer, is_running = uv.new_timer(), false
	return function(...)
		if is_running then
			---@diagnostic disable-next-line: need-check-nil
			timer:stop()
		end
		is_running = true

		local args = { ... }
		---@diagnostic disable-next-line: need-check-nil
		timer:start(
			delay,
			0,
			vim.schedule_wrap(function()
				is_running = false
				func(unpack(args))
			end)
		)
	end
end

return M
