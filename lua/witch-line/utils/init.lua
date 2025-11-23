local unpack, type = unpack, type
local M = {}

--- Creates a debounced version of the given function.
---
--- The returned function forwards **all arguments** to the original `func`
--- after the specified delay has passed without further calls.
---
--- If the debounced function is invoked again before the delay elapses,
--- the timer is reset and only the latest arguments are used.
---
--- @generic A...  -- generic varargs for LSP
--- @param func fun(...: A...) The function to debounce. All arguments will be passed through.
--- @param delay number Delay in milliseconds before invoking `func`.
--- @return fun(...: A...)   debounced_func A debounced version of `func`.
M.debounce = function(func, delay)
	local timer, running = nil, false

	--- @param ... any Arguments to pass to `func`.
	return function(...)
		if not timer then
			timer = (vim.uv or vim.loop).new_timer()
		elseif running then
			---@diagnostic disable-next-line: need-check-nil
			timer:stop()
		end
		running = true

		local args = { ... }
		---@diagnostic disable-next-line: need-check-nil
		timer:start(
			delay,
			0,
			vim.schedule_wrap(function()
				running = false
				func(unpack(args))
			end)
		)
	end
end

--- Resolves a value that may be a function or a direct value.
--- If `value` is a function, it is called with the provided arguments and its return result(s) are returned.
--- Otherwise, the `value` itself is returned as-is.
---
--- This helper is used to transparently handle fields or configs that may be static values
--- or lazily evaluated functions.
---
--- @generic T
--- @param value T | fun(...): T|any Function or direct value to resolve.
--- @param ... any Arguments to pass if `value` is a function.
--- @return T|any result The resolved result; if `value` is a function, returns its result; otherwise returns `value`.
--- @example
--- -- Returns 42
--- local result1 = M.resolve(42)
---
--- -- Returns 42 (function result)
--- local result2 = M.resolve(function(x) return x * 2 end, 21)
M.resolve = function(value, ...)
	--- Why don't use 3 opearator expression?
	--- Because when a value is a function and returns more than one value,
	--- the 3 operator expression will only return the first value.
	--- So we have to use if statement here.
	if type(value) == "function" then
		return value(...)
	end
	return value
end

return M
