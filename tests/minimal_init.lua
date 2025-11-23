vim.opt.swapfile = false
vim.o.laststatus = 3
vim.opt.rtp:append("/home/stilux/Data/Workspace/neovim-plugins/witch-line")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/lualine.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline-components.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/catppuccin")

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
	vim.notify(
		string.format("%s loaded in %.2f ms | avg %.2f ms (%d runs)", name, elapsed, entry.avg, entry.count),
		vim.log.levels.DEBUG,
		{ title = "WitchLine Benchmark" }
	)

	return elapsed
end

-- BENCHMARKS -------------------------------------------------------

measure(function()
	-- vim.o.statusline = " "
	-- local colors = require("catppuccin.palettes").get_palette("macchiato")
	-- local color_map = {
	-- 	n = colors.blue,
	-- 	i = colors.green,
	-- 	v = colors.mauve,
	-- 	V = colors.peach,
	-- 	["\22"] = colors.pink,
	-- 	c = colors.red,
	-- 	R = colors.teal,
	-- 	t = colors.yellow,
	-- }

	-- require("witch-line").setup {
	-- 	statusline = {
	-- 		global = {
	-- 			-- Mode
	-- 			{
	-- 				id = "short_mode",
	-- 				events = { "UIEnter", "ModeChanged" },
	-- 				update = function()
	-- 					local modes = {
	-- 						n = "N",
	-- 						i = "I",
	-- 						v = "V",
	-- 						V = "L",
	-- 						["\22"] = "B",
	-- 						c = "C",
	-- 						R = "R",
	-- 						t = "T",
	-- 					}
	-- 					local mode = vim.fn.mode()
	-- 					return modes[mode]
	-- 				end,
	-- 				padding = { left = 1, right = 0 },
	-- 				style = function()
	-- 					local mode = vim.fn.mode()
	-- 					return { fg = colors.mantle, bg = color_map[mode] }
	-- 				end,
	-- 				right = "",
	-- 				right_style = function()
	-- 					local mode = vim.fn.mode()
	-- 					return { fg = color_map[mode], bg = colors.surface2 }
	-- 				end,
	-- 			},

	-- 			{
	-- 				id = "mode_separator",
	-- 				events = { "UIEnter" },
	-- 				update = "",
	-- 				padding = 0,
	-- 				style = { fg = colors.surface2, bg = colors.surface0 },
	-- 			},

	-- 			-- File
	-- 			{
	-- 				[0] = "file.icon",
	-- 				padding = { left = 2, right = 1 },
	-- 				style = function(self, sid)
	-- 					local ctx = require("witch-line.core.manager.hook").use_context(self, sid)
	-- 					return { fg = ctx.color, bg = colors.surface0 }
	-- 				end,
	-- 			},
	-- 			{
	-- 				[0] = "file.name",
	-- 				style = { fg = colors.text, bg = colors.surface0 },
	-- 				-- padding = { left = 1, right = 0 }
	-- 			},
	-- 			{
	-- 				[0] = "file.modifier",
	-- 				style = { fg = colors.text, bg = colors.surface0 },
	-- 				padding = { left = 0, right = 1 },
	-- 			},
	-- 			{
	-- 				id = "file_separator",
	-- 				events = { "UIEnter" },
	-- 				update = "",
	-- 				padding = 0,
	-- 				style = { fg = colors.surface0, bg = colors.base },
	-- 			},

	-- 			-- Git
	-- 			{
	-- 				[0] = "git.branch",
	-- 				style = { fg = colors.subtext0, bg = colors.base },
	-- 				static = {
	-- 					icon = "",
	-- 				},
	-- 			},
	-- 			{
	-- 				[0] = "git.diff.added",
	-- 				static = { icon = "󰐙 " },
	-- 				style = { fg = colors.subtext0, bg = colors.base },
	-- 			},
	-- 			{
	-- 				[0] = "git.diff.removed",
	-- 				static = { icon = "󰍷 " },
	-- 				style = { fg = colors.subtext0, bg = colors.base },
	-- 			},
	-- 			{
	-- 				[0] = "git.diff.modified",
	-- 				static = { icon = " " },
	-- 				style = { fg = colors.subtext0, bg = colors.base },
	-- 			},

	-- 			"%=",

	-- 			-- Diagnostics
	-- 			"diagnostic.error",
	-- 			"diagnostic.warn",
	-- 			"diagnostic.info",
	-- 			"diagnostic.hint",

	-- 			-- LSP
	-- 			{
	-- 				id = "lsp_icon",
	-- 				events = { "UIEnter" },
	-- 				update = "",
	-- 				padding = { left = 0, right = 2 },
	-- 				style = { fg = colors.text, bg = colors.surface0 },
	-- 				left = "",
	-- 				left_style = { fg = colors.surface0, bg = colors.base },
	-- 			},
	-- 			{
	-- 				id = "lsp_clients",
	-- 				events = { "LspAttach", "LspDetach", "BufWritePost" },
	-- 				style = { fg = colors.text, bg = colors.surface0 },
	-- 				padding = { left = 0, right = 1 },
	-- 				update = function()
	-- 					local clients = vim.lsp.get_clients()
	-- 					if next(clients) == nil then
	-- 						return ""
	-- 					end

	-- 					local c = {}
	-- 					for _, client in pairs(clients) do
	-- 						table.insert(c, client.name)
	-- 					end
	-- 					return table.concat(c, " | ")
	-- 				end,
	-- 			},
	-- 			{
	-- 				id = "right_end",
	-- 				events = { "UIEnter", "ModeChanged" },
	-- 				update = "█",
	-- 				padding = 0,
	-- 				style = function()
	-- 					local mode = vim.fn.mode()
	-- 					return { fg = color_map[mode], bg = colors.surface2 }
	-- 				end,
	-- 				left = "",
	-- 				left_style = { fg = colors.surface2, bg = colors.surface0 },
	-- 			},
	-- 		},
	-- 	},
	-- 	cache = {
	-- 		enabled = true,
	-- 	},
	-- }

	require("witch-line").setup {
		auto_theme = false,
		-- cache = {
		-- 	func_strip = true,
		-- 	enabled = true,
		-- },
	}
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
