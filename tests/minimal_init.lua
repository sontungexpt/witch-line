vim.opt.swapfile = false
vim.o.laststatus = 3
-- vim.opt.rtp:append({ ".", vim.fn.stdpath("share") .. "/lazy/plenary.nvim" })
-- vim.opt.rtp:append("C:/Users/HP/Downloads/witch-line")
vim.opt.rtp:append("/home/stilux/Data/Workspace/neovim-plugins/witch-line")
-- vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/lualine.nvim")

local uv = vim.uv or vim.loop
local start = uv.hrtime()
-- require("lualine").setup()
require("witch-line").setup()

local elapsed = (uv.hrtime() - start) / 1e6

vim.defer_fn(function()
	print(string.format("witch-line loaded in %.2f ms", elapsed))
end, 1000)
