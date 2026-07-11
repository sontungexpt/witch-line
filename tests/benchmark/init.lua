-- Cold-start benchmark: run ONE plugin per Neovim invocation.
-- Run via:
--   nvim --headless -u tests/benchmark/init.lua -- -plugin witch-line
--   nvim --headless -u tests/benchmark/init.lua -- -plugin lualine
--   nvim --headless -u tests/benchmark/init.lua -- -plugin heirline

local function parse_args()
  for i, arg in ipairs(vim.v.argv) do
    if arg == "-plugin" and vim.v.argv[i + 1] then
      return vim.v.argv[i + 1]
    end
  end
  return vim.env.BENCH_PLUGIN or "witch-line"
end

local plugin = parse_args()

local lazy_dir = vim.fn.stdpath("data") .. "/lazy"
vim.opt.rtp:append(vim.fn.getcwd())
vim.opt.rtp:append(lazy_dir .. "/lualine.nvim")
vim.opt.rtp:append(lazy_dir .. "/heirline.nvim")
vim.opt.rtp:append(lazy_dir .. "/heirline-components.nvim")
vim.opt.rtp:append(lazy_dir .. "/catppuccin")

local uv = vim.uv or vim.loop
local results_path = vim.fn.getcwd() .. "/tests/benchmark/results.txt"

local function append(label, elapsed_ms)
  local fd = uv.fs_open(results_path, "a", 438)
  uv.fs_write(fd, string.format("%-30s %s\n", label,
    elapsed_ms >= 0 and string.format("%8.3fms", elapsed_ms) or "ERROR"))
  uv.fs_close(fd)
end

local start
local function bench(name, fn)
  start = uv.hrtime()
  local ok = pcall(fn)
  if ok then
    append(name, (uv.hrtime() - start) / 1e6)
  else
    append(name, -1)
  end
end

if plugin == "witch-line" then
  bench("witch-line", function()
    vim.o.statusline = " "
    require("witch-line").setup({ auto_theme = false, cache = { enabled = false } })
  end)
elseif plugin == "lualine" then
  bench("lualine", function()
    vim.o.statusline = " "
    require("lualine").setup({
      options = {
        theme = "auto",
        section_separators = { left = "", right = "" },
        component_separators = { left = "", right = "" },
        globalstatus = true,
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "filename", "branch" },
        lualine_c = { "diff" },
        lualine_x = { "diagnostics", "lsp", "encoding", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    })
  end)
elseif plugin == "heirline" then
  bench("heirline", function()
    vim.o.statusline = " "
    local heirline = require("heirline")
    local ok, hc = pcall(require, "heirline-components.all")
    if not ok then error("heirline-components not found") end
    hc.init.subscribe_to_events()
    heirline.load_colors(hc.hl.get_colors())
    heirline.setup({
      statusline = {
        hl = { fg = "fg", bg = "bg" },
        hc.component.mode(),
        hc.component.git_branch(),
        hc.component.file_info(),
        hc.component.git_diff(),
        hc.component.diagnostics(),
        hc.component.fill(),
        hc.component.cmd_info(),
        hc.component.fill(),
        hc.component.lsp(),
        hc.component.virtual_env(),
        hc.component.nav(),
        hc.component.mode { surround = { separator = "right" } },
      },
    })
  end)
else
  append("unknown-plugin", -2)
end

vim.cmd("qa!")
