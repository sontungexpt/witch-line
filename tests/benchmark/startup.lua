--- Startup time benchmark: cold-start cost per plugin.
--- Usage:
---   nvim --headless -u tests/benchmark/startup.lua -- -plugin witch-line -n 20
---   nvim --headless -u tests/benchmark/startup.lua -- -plugin lualine  -n 20
---   nvim --headless -u tests/benchmark/startup.lua -- -plugin heirline -n 20
---
--- Environment variable alternative:
---   BENCH_PLUGIN=witch-line BENCH_N=20 nvim --headless -u tests/benchmark/startup.lua

local uv = vim.uv or vim.loop

-- ── Argument parsing ──────────────────────────────────────────────────
local function parse_args()
    local plugin, n
    for i, arg in ipairs(vim.v.argv) do
        if arg == "-plugin" and vim.v.argv[i + 1] then plugin = vim.v.argv[i + 1] end
        if arg == "-n" and vim.v.argv[i + 1] then n = tonumber(vim.v.argv[i + 1]) end
    end
    return plugin or vim.env.BENCH_PLUGIN or "witch-line",
        n or tonumber(vim.env.BENCH_N) or 20
end

local plugin, N = parse_args()

-- ── RTP setup ─────────────────────────────────────────────────────────
local lazy_dir = vim.fn.stdpath("data") .. "/lazy"
vim.opt.rtp:append(vim.fn.getcwd())
vim.opt.rtp:append(lazy_dir .. "/lualine.nvim")
vim.opt.rtp:append(lazy_dir .. "/heirline.nvim")
vim.opt.rtp:append(lazy_dir .. "/heirline-components.nvim")
vim.opt.rtp:append(lazy_dir .. "/catppuccin")

-- ── Helpers ───────────────────────────────────────────────────────────
local function median(t)
    local s = {}
    for _, v in ipairs(t) do s[#s + 1] = v end
    table.sort(s)
    local mid = math.floor(#s / 2) + 1
    return s[mid]
end

local function stddev(t, mean)
    local sum = 0
    for _, v in ipairs(t) do sum = sum + (v - mean) ^ 2 end
    return math.sqrt(sum / #t)
end

local function percentile(t, p)
    local s = {}
    for _, v in ipairs(t) do s[#s + 1] = v end
    table.sort(s)
    local idx = math.ceil(#s * p / 100)
    return s[math.max(idx, 1)]
end

local function fmt_ms(ms)
    return string.format("%7.3f ms", ms)
end

-- ── Bench functions: one Neovim process per iteration ─────────────────
--- We cannot truly cold-start multiple times in a single process.
--- Instead we measure: require + setup overhead per call.
--- To simulate cold-start, we nil out all cached modules before each run.

local setups = {
    ["witch-line"] = function()
        require("witch-line").setup({ auto_theme = false, cache = { enabled = false } })
    end,
    ["lualine"] = function()
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
    end,
    ["heirline"] = function()
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
    end,
}

local setup_fn = setups[plugin]
if not setup_fn then
    io.stderr:write("Unknown plugin: " .. tostring(plugin) .. "\n")
    io.stderr:write("Available: " .. table.concat(vim.tbl_keys(setups), ", ") .. "\n")
    vim.cmd("cq!")
end

-- ── Run benchmark ─────────────────────────────────────────────────────
print(string.format("\n=== Startup Benchmark: %s (%d runs) ===\n", plugin, N))

local times = {}

-- Warmup
setup_fn()
setup_fn()

for i = 1, N do
    -- Nil out all cached modules for this plugin to simulate fresh require
    for key in pairs(package.loaded) do
        if key:match("^witch%-line") or key:match("^lualine") or key:match("^heirline") then
            package.loaded[key] = nil
            package.preload[key] = nil
        end
    end
    -- Also clear package.searchers so require re-searches
    if package.searchers then
        for i = #package.searchers, 2, -1 do -- keep builtin searcher[1]
            package.searchers[i] = nil
        end
    end

    collectgarbage("collect")
    collectgarbage("stop")

    local start = uv.hrtime()
    local ok, err = pcall(setup_fn)
    local elapsed = (uv.hrtime() - start) / 1e6

    collectgarbage("restart")

    if ok then
        times[#times + 1] = elapsed
        print(string.format("  run %2d: %s", i, fmt_ms(elapsed)))
    else
        print(string.format("  run %2d: ERROR  %s", i, tostring(err)))
    end
end

-- ── Statistics ────────────────────────────────────────────────────────
if #times == 0 then
    print("\n  No successful runs.")
    vim.cmd("cq!")
end

table.sort(times)
local sum = 0
for _, v in ipairs(times) do sum = sum + v end
local mean = sum / #times
local sd = stddev(times, mean)

print(string.format("\n  ── Summary ──"))
print(string.format("  Runs:       %d", #times))
print(string.format("  Mean:       %s", fmt_ms(mean)))
print(string.format("  Median:     %s", fmt_ms(median(times))))
print(string.format("  Std Dev:    %s", fmt_ms(sd)))
print(string.format("  Min:        %s", fmt_ms(times[1])))
print(string.format("  Max:        %s", fmt_ms(times[#times])))
print(string.format("  P5:         %s", fmt_ms(percentile(times, 5))))
print(string.format("  P95:        %s", fmt_ms(percentile(times, 95))))
print(string.rep("=", 60) .. "\n")

-- Append to results file
local results_path = vim.fn.getcwd() .. "/tests/benchmark/results.txt"
local fd = uv.fs_open(results_path, "a", 438)
uv.fs_write(fd, string.format(
    "%-20s  mean=%s  median=%s  sd=%s  min=%s  max=%s  (n=%d)\n",
    plugin, fmt_ms(mean), fmt_ms(median(times)), fmt_ms(sd),
    fmt_ms(times[1]), fmt_ms(times[#times]), #times))
uv.fs_close(fd)

vim.cmd("qa!")
