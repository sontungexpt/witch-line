--- Benchmark utility.
--- Measures execution time of a callback and logs it.
---@param cb fun()  The function to benchmark.
---@param name string  Label for the benchmark.
---@param file_path? string  If set, appends result to file; otherwise uses vim.notify.
---@return integer elapsed_ns  Nanoseconds elapsed.
return function(cb, name, file_path)
	local uv = vim.uv or vim.loop
	local start = uv.hrtime()
	cb()
	local elapsed_ns = uv.hrtime() - start -- nanoseconds

	local text = string.format("%s took %d ns\n", name, elapsed_ns)

	if file_path then
		local file = io.open(file_path, "a")
		if file then
			file:write(text)
			file:close()
		end
	else
		vim.defer_fn(function()
			require("witch-line.util.notifier").info(text)
		end, 1000)
	end
end
