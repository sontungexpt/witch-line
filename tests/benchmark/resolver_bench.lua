--- Benchmark for resolver field resolution (recursive vs while-loop).
--- Run: nvim --headless --cmd "set rtp+=/path/to/witch-line" -l tests/benchmark/resolver_bench.lua

local uv = vim.uv or vim.loop
local hrtime = uv.hrtime

local ManagedComps = {}

package.preload["witch-line"] = function()
    return { user_config = { theme_aware = false } }
end
package.preload["witch-line.core.registry"] = function()
    return {
        ManagedComps = setmetatable({}, { __index = ManagedComps }),
        DepGraphKind = { All = 1, Visible = 2, Event = 3, Timer = 4 },
        register = function(id, comp) ManagedComps[id] = comp; return comp end,
    }
end
package.preload["witch-line.component"] = function()
    return setmetatable({}, { __index = function() return nil end })
end

package.loaded["witch-line.core.resolver"] = nil
package.loaded["witch-line.core.comp.behavior"] = nil
package.loaded["witch-line.core.comp.proxy"] = nil

local Resolver = require("witch-line.core.resolver")

local function bench(name, iterations, fn)
    for _ = 1, math.min(iterations, 1000) do fn() end
    collectgarbage("collect")
    collectgarbage("stop")
    local start = hrtime()
    for _ = 1, iterations do fn() end
    local elapsed = hrtime() - start
    collectgarbage("restart")
    return elapsed / iterations
end

local function fmt_ns(ns)
    if ns < 1000 then
        return string.format("%.0f ns", ns)
    elseif ns < 1000000 then
        return string.format("%.1f us", ns / 1000)
    else
        return string.format("%.2f ms", ns / 1000000)
    end
end

local N = 100000

print("\n=== Resolver Benchmarks (recursive, current) ===\n")

local function run_case(label, setup_fn)
    setup_fn()
    local comp, field = table.unpack(setup_fn())
    local avg = bench(label, N, function()
        Resolver.resolve_plain_field(comp, field)
    end)
    print(string.format("  %-45s %10s  (%d iters)", label, fmt_ns(avg), N))
end

-- 1. Direct field
do
    local comp = { id = "bench.direct", style = { fg = "#fff" } }
    ManagedComps["bench.direct"] = comp
    local avg = bench("Direct field", N, function()
        Resolver.resolve_plain_field(comp, "style")
    end)
    print(string.format("  %-45s %10s  (%d iters)", "Direct field", fmt_ns(avg), N))
end

-- 2. 1-level delegator chain
do
    local target = { id = "bench.target1", style = { fg = "#aaa" } }
    ManagedComps["bench.target1"] = target
    local comp = { id = "bench.ref1", delegator = { style = "bench.target1" } }
    ManagedComps["bench.ref1"] = comp
    local avg = bench("1-level chain", N, function()
        Resolver.resolve_plain_field(comp, "style")
    end)
    print(string.format("  %-45s %10s  (%d iters)", "1-level delegator chain", fmt_ns(avg), N))
end

-- 3. 4-level delegator chain
do
    local leaf = { id = "bench.leaf4", style = { fg = "#leaf" } }
    local d3 = { id = "bench.d3", delegator = { style = "bench.leaf4" } }
    local d2 = { id = "bench.d2", delegator = { style = "bench.d3" } }
    local d1 = { id = "bench.d1", delegator = { style = "bench.d2" } }
    local root = { id = "bench.root4", delegator = { style = "bench.d1" } }
    for _, c in ipairs({ leaf, d3, d2, d1, root }) do ManagedComps[c.id] = c end
    local avg = bench("4-level chain", N, function()
        Resolver.resolve_plain_field(root, "style")
    end)
    print(string.format("  %-45s %10s  (%d iters)", "4-level delegator chain", fmt_ns(avg), N))
end

-- 4. 8-level delegator chain
do
    local leaf = { id = "bench.leaf8", style = { fg = "#leaf8" } }
    local prev = leaf
    for i = 7, 1, -1 do
        local node = { id = "bench.l8_" .. i, delegator = { style = prev.id } }
        ManagedComps[node.id] = node
        prev = node
    end
    local root = { id = "bench.root8", delegator = { style = prev.id } }
    ManagedComps[root.id] = root
    local avg = bench("8-level chain", N, function()
        Resolver.resolve_plain_field(root, "style")
    end)
    print(string.format("  %-45s %10s  (%d iters)", "8-level delegator chain", fmt_ns(avg), N))
end

-- 5. Nil field (no delegator)
do
    local comp = { id = "bench.nil1" }
    ManagedComps["bench.nil1"] = comp
    local avg = bench("Nil field (no delegator)", N, function()
        Resolver.resolve_plain_field(comp, "nonexistent")
    end)
    print(string.format("  %-45s %10s  (%d iters)", "Nil field (no delegator)", fmt_ns(avg), N))
end

-- 6. Nil field (delegator, missing target)
do
    local comp = { id = "bench.nil2", delegator = { style = "bench.nonexistent_target" } }
    ManagedComps["bench.nil2"] = comp
    local avg = bench("Nil field (delegator, missing)", N, function()
        Resolver.resolve_plain_field(comp, "style")
    end)
    print(string.format("  %-45s %10s  (%d iters)", "Nil field (delegator, missing target)", fmt_ns(avg), N))
end

-- 7. Resolve_plain_field with cache hit (2nd call)
do
    local target = { id = "bench.cache_hit", style = { fg = "#cached" } }
    ManagedComps["bench.cache_hit"] = target
    local comp = { id = "bench.cache_ref", delegator = { style = "bench.cache_hit" } }
    ManagedComps["bench.cache_ref"] = comp
    -- Prime cache
    Resolver.resolve_plain_field(comp, "style")
    local avg = bench("Cached hit", N, function()
        Resolver.resolve_plain_field(comp, "style")
    end)
    print(string.format("  %-45s %10s  (%d iters)", "Cached hit (2nd call)", fmt_ns(avg), N))
end

print("\n" .. string.rep("=", 70))
print("  All benchmarks completed. Baseline recorded.")
print(string.rep("=", 70) .. "\n")

os.exit(0)
