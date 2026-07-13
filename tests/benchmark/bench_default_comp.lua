--- Benchmark: three approaches to resolving default component IDs.
local COMP_CONTAINER = "witch-line.component."

local IdPathMap = {
    ["wl.mode"]                 = { "mode" },
    ["wl.file.name"]            = { "file", "name" },
    ["wl.file.icon"]            = { "file", "icon" },
    ["wl.file.modifier"]        = { "file", "modifier" },
    ["wl.file.size"]            = { "file", "size" },
    ["wl.copilot"]              = { "ai.copilot" },
    ["wl.codeium"]             = { "ai.codeium", "codeium" },
    ["wl.codeium.neocodeium"]  = { "ai.codeium", "neocodeium" },
    ["wl.diagnostic.error"]     = { "diagnostic", "error" },
    ["wl.diagnostic.warn"]      = { "diagnostic", "warn" },
    ["wl.diagnostic.info"]      = { "diagnostic", "info" },
    ["wl.diagnostic.hint"]      = { "diagnostic", "hint" },
    ["wl.cursor.pos"]           = { "cursor", "pos" },
    ["wl.cursor.progress"]      = { "cursor", "progress" },
    ["wl.encoding"]             = { "encoding" },
    ["wl.lsp.clients"]          = { "lsp", "clients" },
    ["wl.indent"]               = { "indent" },
    ["wl.git.branch"]           = { "git", "branch" },
    ["wl.git.diff.added"]       = { "git", "diff", "added" },
    ["wl.git.diff.removed"]     = { "git", "diff", "removed" },
    ["wl.git.diff.modified"]    = { "git", "diff", "modified" },
    ["wl.battery"]              = { "battery" },
    ["wl.datetime"]             = { "datetime" },
    ["wl.os_uname"]             = { "os_uname" },
    ["wl.nvim_dap"]             = { "nvim_dap" },
    ["wl.search.count"]         = { "search", "count" },
    ["wl.selection.count"]      = { "selection", "count" },
}

local IDS = {}
for id in pairs(IdPathMap) do IDS[#IDS + 1] = id end

-- Helper: resolve a single component from path
local function resolve_component(id)
    local path = IdPathMap[id]
    if not path then return nil end
    local comp = require(COMP_CONTAINER .. path[1])
    for i = 2, #path do
        comp = comp[path[i]]
        if not comp then return nil end
    end
    return comp
end

-- ====================================================================
-- Strategy 1: metatable, no cache (current)
-- ====================================================================
local M1 = setmetatable({}, {
    __index = function(_, id) return resolve_component(id) end,
})

-- ====================================================================
-- Strategy 2: metatable + cache-on-first-access via rawset
-- ====================================================================
local M2 = setmetatable({}, {
    __index = function(self, id)
        local comp = resolve_component(id)
        if comp then rawset(self, id, comp) end
        return comp
    end,
})

-- ====================================================================
-- Strategy 3: pre-populate at module load
-- ====================================================================
local M3 = {}
for id in pairs(IdPathMap) do
    M3[id] = resolve_component(id)
end

-- ====================================================================
-- Benchmark
-- ====================================================================
local ITERATIONS = 5
local SAMPLES = 50000

local function bench(name, tbl, first_call_warmup)
    -- Warmup first access (require cache)
    if first_call_warmup then first_call_warmup() end

    for iter = 1, ITERATIONS do
        local start = vim.uv.hrtime()
        for _ = 1, SAMPLES do
            for _, id in ipairs(IDS) do
                local _ = tbl[id]
            end
        end
        local elapsed = (vim.uv.hrtime() - start) / 1e6
        print(string.format("  %s run %d: %.2f ms  (%.2f ns/access)",
            name, iter, elapsed, (elapsed * 1e6) / (#IDS * SAMPLES)))
    end
end

-- Measure memory
local collect = vim.uv or vim.loop

print(string.format("Benchmark: %d ids x %d samples x %d iterations\n", #IDS, SAMPLES, ITERATIONS))

-- Warmup: resolve all ids once so require cache is hot
for _, id in ipairs(IDS) do resolve_component(id) end

bench("no-cache metatable", M1)
print()
bench("cached metatable  ", M2)
print()
bench("pre-populated     ", M3)
print()

-- Memory: count table entries
local function tbl_size(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
print(string.format("Memory: no-cache=%d entries, cached=%d entries, pre-pop=%d entries",
    tbl_size(M1), tbl_size(M2), tbl_size(M3)))
