--- Benchmark suite for resolver, style, and update pipeline.
--- Measures: static vs dynamic resolution, deep inheritance, cache hits,
---           style merging, and full update cycles.

local uv = vim.uv or vim.loop
local hrtime = uv.hrtime

local F = require("tests.helpers.component_factory")

-- ====================================================================
--- Run a benchmark function N iterations, report timing.
---@param name string Scenario name.
---@param iterations number Number of iterations.
---@param fn fun() Function to benchmark.
---@return number avg_ns Average nanoseconds per iteration.
local function bench(name, iterations, fn)
    -- Warmup
    for _ = 1, math.min(iterations, 1000) do fn() end

    collectgarbage("collect")
    collectgarbage("stop")

    local start = hrtime()
    for _ = 1, iterations do fn() end
    local elapsed = hrtime() - start

    collectgarbage("restart")

    local avg_ns = elapsed / iterations
    return avg_ns
end

--- Format nanoseconds to human-readable.
---@param ns number
---@return string
local function fmt_ns(ns)
    if ns < 1000 then
        return string.format("%.0f ns", ns)
    elseif ns < 1000000 then
        return string.format("%.1f us", ns / 1000)
    else
        return string.format("%.2f ms", ns / 1000000)
    end
end

-- ====================================================================
-- Setup: mock dependencies for resolver and behavior
-- ====================================================================
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

package.loaded["witch-line.core.comp.resolver"] = nil
package.loaded["witch-line.core.comp.behavior"] = nil
package.loaded["witch-line.core.comp.proxy"] = nil

local Resolver = require("witch-line.core.comp.resolver")
local B = require("witch-line.core.comp.behavior")
local Proxy = require("witch-line.core.comp.proxy")
local Session = require("witch-line.core.session")

local function make_resolver(components)
    return function(id) return components[id] end
end

-- ====================================================================
print("\n=== Resolver Benchmarks ===")
-- ====================================================================

local N = 100000

do
    local comp = { id = "bench.direct", style = { fg = "#fff" } }
    ManagedComps["bench.direct"] = comp
    local avg = bench("Resolver: direct field", N, function()
        Resolver.resolve_plain_field(comp, "style")
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Direct field", fmt_ns(avg), N))
end

do
    local target = { id = "bench.target", style = { fg = "#aaa" } }
    ManagedComps["bench.target"] = target
    local comp = { id = "bench.ref1", delegator = { style = "bench.target" } }
    ManagedComps["bench.ref1"] = comp
    local avg = bench("Resolver: 1-level delegator chain", N, function()
        Resolver.resolve_plain_field(comp, "style")
    end)
    print(string.format("  %-40s %10s  (%d iters)", "1-level delegator chain", fmt_ns(avg), N))
end

do
    -- 4-level delegator chain
    local leaf = { id = "bench.leaf", style = { fg = "#leaf" } }
    local d3 = { id = "bench.d3", delegator = { style = "bench.leaf" } }
    local d2 = { id = "bench.d2", delegator = { style = "bench.d3" } }
    local d1 = { id = "bench.d1", delegator = { style = "bench.d2" } }
    local root = { id = "bench.root", delegator = { style = "bench.d1" } }
    for _, c in ipairs({ leaf, d3, d2, d1, root }) do ManagedComps[c.id] = c end
    local avg = bench("Resolver: 4-level delegator chain", N, function()
        Resolver.resolve_plain_field(root, "style")
    end)
    print(string.format("  %-40s %10s  (%d iters)", "4-level delegator chain", fmt_ns(avg), N))
end

do
    local comp = { id = "bench.missing" }
    ManagedComps["bench.missing"] = comp
    local avg = bench("Resolver: nil field", N, function()
        Resolver.resolve_plain_field(comp, "nonexistent")
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Nil field", fmt_ns(avg), N))
end

-- ====================================================================
print("\n=== Inheritance Benchmarks ===")
-- ====================================================================

do
    local comp = F.make_comp({ style = { fg = "#fff" } })
    local avg = bench("Inherit: no parent, static", N, function()
        B.resolve_inherited_value(comp, "style", make_resolver({}), nil)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "No parent, static", fmt_ns(avg), N))
end

do
    local comp = F.make_comp({ style = function() return { fg = "#fff" } end })
    local avg = bench("Inherit: no parent, dynamic", N, function()
        B.resolve_inherited_value(comp, "style", make_resolver({}), nil)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "No parent, dynamic", fmt_ns(avg), N))
end

do
    local comps = F.make_deep_chain(10, { style = { fg = "#deep" } })
    local lookup = {}
    for _, c in ipairs(comps) do lookup[c.id] = c end
    local resolver = make_resolver(lookup)
    local leaf = comps[10]
    local avg = bench("Inherit: 10-level chain", N, function()
        B.resolve_inherited_value(leaf, "style", resolver, nil)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "10-level chain (first call)", fmt_ns(avg), N))
end

do
    local comps = F.make_deep_chain(100, { style = { fg = "#deep100" } })
    local lookup = {}
    for _, c in ipairs(comps) do lookup[c.id] = c end
    local resolver = make_resolver(lookup)
    local leaf = comps[100]
    -- First call to prime cache
    B.resolve_inherited_value(leaf, "style", resolver, nil)
    local avg = bench("Inherit: 100-level chain (cached)", N, function()
        B.resolve_inherited_value(leaf, "style", resolver, nil)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "100-level chain (cached)", fmt_ns(avg), N))
end

-- ====================================================================
print("\n=== Style Resolution Benchmarks ===")
-- ====================================================================

do
    local comp = F.make_comp({ left = ">>", style = { fg = "#fff", bg = "#000" } })
    local avg = bench("SepStyle: SepBg default", N, function()
        B.resolved_side_style(comp, "left", { fg = "#fff", bg = "#000" }, false)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "SepBg default", fmt_ns(avg), N))
end

do
    local comp = F.make_comp({ left = ">>", left_style = 1, style = { fg = "#fff", bg = "#000" } })
    local avg = bench("SepStyle: SepFg", N, function()
        B.resolved_side_style(comp, "left", { fg = "#fff", bg = "#000" }, false)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "SepFg", fmt_ns(avg), N))
end

do
    local comp = F.make_comp({ left = ">>", left_style = { fg = "#aaa", bold = true } })
    local avg = bench("SepStyle: custom table", N, function()
        B.resolved_side_style(comp, "left", nil, false)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Custom table", fmt_ns(avg), N))
end

do
    local comp = F.make_comp({ left = ">>", left_style = function() return { fg = "#aaa" } end })
    local avg = bench("SepStyle: dynamic function", N, function()
        B.resolved_side_style(comp, "left", { fg = "#fff", bg = "#000" }, false)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Dynamic function", fmt_ns(avg), N))
end

-- ====================================================================
print("\n=== Evaluate Benchmarks ===")
-- ====================================================================

do
    local comp = F.make_comp({ update = function() return "hello" end, padding = 1 })
    local avg = bench("Evaluate: string update + padding", N, function()
        B.evaluate(comp)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "String update + padding", fmt_ns(avg), N))
end

do
    local comp = F.make_comp({ update = function() return "v", { fg = "#fff" } end, padding = 0 })
    local avg = bench("Evaluate: update with style override", N, function()
        B.evaluate(comp)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Update with style override", fmt_ns(avg), N))
end

do
    local comp = F.make_comp({ update = "static text", padding = 2 })
    local avg = bench("Evaluate: static field (no function)", N, function()
        B.evaluate(comp)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Static field", fmt_ns(avg), N))
end

-- ====================================================================
print("\n=== Session/Cache Benchmarks ===")
-- ====================================================================

do
    local session = Session.new()
    local scope = session:cache("bench_comp")
    local fn = function(x) return x * 2 end
    local avg = bench("Cache: memo cold", N, function()
        scope:memo(fn, math.random(1, 1000))
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Memo cold (unique args)", fmt_ns(avg), N))
    session:destroy()
end

do
    local session = Session.new()
    local scope = session:cache("bench_comp2")
    scope:memo(function() return 42 end) -- prime cache
    local avg = bench("Cache: memo warm", N, function()
        scope:memo(function() return 42 end)
    end)
    print(string.format("  %-40s %10s  (%d iters)", "Memo warm (cached)", fmt_ns(avg), N))
    session:destroy()
end

-- ====================================================================
-- Summary table
-- ====================================================================
print("\n" .. string.rep("=", 70))
print(string.format("  %-40s %10s", "Scenario", "Avg Time"))
print(string.rep("=", 70))
print("  All benchmarks completed. See individual timings above.")
print(string.rep("=", 70))

os.exit(0)
