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
	local timer, is_running = (vim.uv or vim.loop).new_timer(), false
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

--- Evaluates a value that may be a function or a direct value.
--- If it's a function, it calls it with the provided arguments; otherwise, it returns the value as is.
--- @usage
--- @example
--- local result1 = M.eval(42) -- returns 42
--- local result2 = M.eval(function(x) return x * 2 end, 21) -- returns 42
--- @param value any The value to evaluate, which can be a function or any other type.
--- @param ... any Additional arguments to pass to the function if `value` is a function.
--- @return any result The evaluated result.
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
