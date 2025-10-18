local M = {}

--- Creates a debounced version of the given function.
--- The debounced function will only execute after the specified delay has passed since the last invocation.
--- If the debounced function is called again before the delay has passed, the timer resets.
--- @usage
--- @example
--- local debounced_func = M.debounce(function() print("Hello, World!") end, 200)
--- debounced_func() -- Will print "Hello, World!" after 200ms if not called again within that time.
--- @param func function The function to debounce.
--- @param delay number The delay in milliseconds.
--- @return function debounced_func A debounced version of the input function.
M.debounce = function(func, delay)
	local timer, running = nil, false
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

M.benchmark = function(cb, name, file_path)
  local uv = vim.uv or vim.loop
	local start = uv.hrtime()
	cb()
	local elapsed = (uv.hrtime() - start) / 1e6 -- Convert to milliseconds
  local text = string.format("%s took %.2f ms\n", name, elapsed)
  if file_path then
    local file = io.open(file_path, "a")
    if file then
      --- get ms from elapsed
      file:write(text)
      file:close()
    end
  else
    require("witch-line.utils.notifier").info(text)
  end
end


return M
