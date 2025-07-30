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

--- Calls a function or returns a value.
--- If the value is a function, it calls it with the provided arguments.
--- If the value is not a function, it simply returns the value.
--- @param value any The value to call or return.
--- @param ... any Additional arguments to pass to the function if `value` is a function.
--- @return any The result of calling the function or the value itself.
M.call_or_get = function(value, ...)
	return type(value) == "function" and value(...) or value
end

return M
