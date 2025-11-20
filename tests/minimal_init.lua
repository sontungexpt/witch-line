vim.opt.swapfile = false
vim.o.laststatus = 3
-- vim.opt.rtp:append({ ".", vim.fn.stdpath("share") .. "/lazy/plenary.nvim" })
-- vim.opt.rtp:append("C:/Users/HP/Downloads/witch-line")
vim.opt.rtp:append("/home/stilux/Data/Workspace/neovim-plugins/witch-line")
-- vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/lualine.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline-components.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/heirline.nvim")

local uv = vim.uv or vim.loop
local start = uv.hrtime()
-- require("lualine").setup()
require("witch-line").setup()

-- local heirline = require("heirline")
-- local heirline_components = require("heirline-components.all")
-- heirline_components.init.subscribe_to_events()
-- heirline.load_colors(heirline_components.hl.get_colors())
-- heirline.setup({
-- 	statusline = { -- UI statusbar
-- 		hl = { fg = "fg", bg = "bg" },
-- 		heirline_components.component.mode(),
-- 		heirline_components.component.git_branch(),
-- 		heirline_components.component.file_info(),
-- 		heirline_components.component.git_diff(),
-- 		heirline_components.component.diagnostics(),
-- 		heirline_components.component.fill(),
-- 		heirline_components.component.cmd_info(),
-- 		heirline_components.component.fill(),
-- 		heirline_components.component.lsp(),
-- 		heirline_components.component.compiler_state(),
-- 		heirline_components.component.virtual_env(),
-- 		heirline_components.component.nav(),
-- 		heirline_components.component.mode({ surround = { separator = "right" } }),
-- 	},
-- })

local elapsed = (uv.hrtime() - start) / 1e6

vim.defer_fn(function()
	print(string.format("witch-line loaded in %.2f ms", elapsed))
end, 1000)
