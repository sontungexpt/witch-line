vim.opt.swapfile = false
vim.o.laststatus = 3
vim.opt.rtp:append("/home/stilux/Data/Workspace/neovim-plugins/witch-line")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/lualine.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline-components.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline.nvim")

local base_dir = "/home/stilux/Data/Workspace/neovim-plugins/witch-line/tests/benchmark/"
local bench_file = base_dir .. "benchmarks.txt"

local uv = vim.uv or vim.loop
local function ensure_file(p)
	if uv.fs_stat(p) == nil then
		local fd = uv.fs_open(p, "w", 438)
		uv.fs_close(fd)
	end
end

ensure_file(bench_file)

-- Read all benchmarks from file: <name> <count> <total> <avg>
local function read_all_stats()
	local fd = uv.fs_open(bench_file, "r", 438)
	if not fd then
		return {}
	end

	local content = uv.fs_read(fd, 4096)
	uv.fs_close(fd)

	local stats = {}
	if not content or content == "" then
		return stats
	end

	for name, count, total, avg in content:gmatch("(%S+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)") do
		stats[name] = {
			count = tonumber(count),
			total = tonumber(total),
			avg = tonumber(avg),
		}
	end

	return stats
end

-- Write all stats back to file
local function write_all_stats(stats)
	local out = {}
	for name, s in pairs(stats) do
		out[#out + 1] = string.format("%s %d %.4f %.4f", name, s.count, s.total, s.avg)
	end

	local fd = uv.fs_open(bench_file, "w", 438)
	uv.fs_write(fd, table.concat(out, "\n"))
	uv.fs_close(fd)
end

--- Measure a function and update benchmark
local function measure(callback, name)
	local stats = read_all_stats()
	local entry = stats[name] or { count = 0, total = 0.0, avg = 0.0 }

	local start = uv.hrtime()
	callback()
	local elapsed = (uv.hrtime() - start) / 1e6 -- ms

	-- Update stats
	entry.count = entry.count + 1
	entry.total = entry.total + elapsed
	entry.avg = entry.total / entry.count

	stats[name] = entry
	write_all_stats(stats)

	-- Print for debugging
	vim.defer_fn(function()
		print(
			string.format(
				"%s loaded in %.2f ms | avg %.2f ms (%d runs)",
				name,
				elapsed,
				entry.avg,
				entry.count
			)
		)
	end, 300)

	return elapsed
end

-- BENCHMARKS -------------------------------------------------------

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
		statusline = {
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
