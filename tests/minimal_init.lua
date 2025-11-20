vim.opt.swapfile = false
vim.o.laststatus = 3
vim.opt.rtp:append("/home/stilux/Data/Workspace/neovim-plugins/witch-line")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/lualine.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline-components.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline.nvim")

local base_dir = "/home/stilux/Data/Workspace/neovim-plugins/witch-line/tests/benchmark/"
local uv = vim.uv or vim.loop

-- Benchmark file path

-- Read numbers from file
local function read_stats(bench_file)
	local fd = uv.fs_open(bench_file, "r", 438) -- 438 = 0o666
	if not fd then
		return 0, 0.0, 0.0 -- count, total, avg
	end

	local data = uv.fs_read(fd, 1024)
	uv.fs_close(fd)

	if not data or data == "" then
		return 0, 0.0, 0.0
	end

	local count, total, avg = data:match("^(%d+)%s+(%d+%.?%d*)%s+(%d+%.?%d*)$")
	return tonumber(count), tonumber(total), tonumber(avg)
end

-- Write numbers to file
local function write_stats(count, total, avg, bench_file)
	local out = string.format("%d %.4f %.4f", count, total, avg)
	uv.fs_write(uv.fs_open(bench_file, "w", 438), out)
end

--- Measure a function and record benchmark
--- @param callback fun(): any
local measure = function(callback, name)
	local bench_file = base_dir .. "witch-line-bench.txt"
	if name == "lualine" then
		bench_file = base_dir .. "lualine-bench.txt"
	elseif name == "heirline" then
		bench_file = base_dir .. "heirline-bench.txt"
	end

	local start = uv.hrtime()

	callback() -- run your setup()

	local elapsed = (uv.hrtime() - start) / 1e6 -- ms

	-- Read previous stats
	local count, total = read_stats(bench_file)

	count = count + 1
	total = total + elapsed
	local avg = total / count

	-- Save new stats
	write_stats(count, total, avg, bench_file)

	-- Print for debugging
	vim.defer_fn(function()
		print(string.format(name .. " loaded in %.2f ms | avg %.2f ms (%d runs)", elapsed, avg, count))
	end, 300)

	return elapsed
end

measure(function()
	vim.o.statusline = " "
	require("witch-line").setup()
end, "witch-line")

measure(function()
	vim.o.statusline = " "
	require("lualine").setup()
end, "lualine")

measure(function()
	vim.o.statusline = " "

	local heirline = require("heirline")
	local heirline_components = require("heirline-components.all")
	heirline_components.init.subscribe_to_events()
	heirline.load_colors(heirline_components.hl.get_colors())
	heirline.setup {
		statusline = { -- UI statusbar
			hl = { fg = "fg", bg = "bg" },
			heirline_components.component.mode(),
			heirline_components.component.git_branch(),
			heirline_components.component.file_info(),
			heirline_components.component.git_diff(),
			heirline_components.component.diagnostics(),
			heirline_components.component.fill(),
			heirline_components.component.cmd_info(),
			heirline_components.component.fill(),
			heirline_components.component.lsp(),
			heirline_components.component.compiler_state(),
			heirline_components.component.virtual_env(),
			heirline_components.component.nav(),
			heirline_components.component.mode { surround = { separator = "right" } },
		},
	}
end, "heirline")
