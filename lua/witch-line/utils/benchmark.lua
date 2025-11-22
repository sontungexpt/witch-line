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
			require("witch-line.utils.notifier").info(text)
		end, 1000)
	end
end
