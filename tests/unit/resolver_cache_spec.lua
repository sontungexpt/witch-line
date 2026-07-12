--- Tests for resolver cache behavior.
--- Verifies that only components that were traversed receive cached results.

local assert = require("tests.helpers.assert")

local ManagedComps = {}
local BuiltinComp = setmetatable({}, { __index = function() return nil end })

package.loaded["witch-line.core.registry"] = {
    ManagedComps = setmetatable({}, { __index = ManagedComps }),
}
package.loaded["witch-line.component"] = BuiltinComp
package.loaded["witch-line.core.resolver"] = nil
local Resolver = require("witch-line.core.resolver")

local function clear(t) for k in pairs(t) do t[k] = nil end end
local function reset()
    clear(ManagedComps)
    package.loaded["witch-line.core.resolver"] = nil
    Resolver = require("witch-line.core.resolver")
end

local function cache_keys(key)
    return Resolver.get_cache_keys(key)
end

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function cache_set(key)
    return cache_keys(key), count_keys(cache_keys(key))
end

-- ============================================================
print("=== 1. Direct value (no delegation) ===")
reset()
do
    local comp = { id = "A", style = { fg = "#fff" } }
    ManagedComps["A"] = comp
    local val, owner = Resolver.resolve_plain_field(comp, "style")
    assert.eq(val.fg, "#fff", "value correct")
    assert.eq(owner.id, "A", "owner correct")

    local keys, count = cache_set("style")
    assert.eq(count, 0, "no cache entries for direct value")
end

-- ============================================================
print("=== 2. Multi-level delegation A→B→C(value) ===")
reset()
do
    local c = { id = "C", style = { fg = "#ccc" } }
    local b = { id = "B", delegator = { style = "C" } }
    local a = { id = "A", delegator = { style = "B" } }
    ManagedComps["A"] = a
    ManagedComps["B"] = b
    ManagedComps["C"] = c

    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#ccc", "value correct")
    assert.eq(owner.id, "C", "owner is C")

    local keys, count = cache_set("style")
    assert.eq(count, 2, "cache has 2 entries")
    assert.is_true(keys["A"] ~= nil, "A is cached")
    assert.is_true(keys["B"] ~= nil, "B is cached")
    assert.is_true(keys["C"] == nil, "C is NOT cached")
end

-- ============================================================
print("=== 3. Missing value A→B→C(nil) ===")
reset()
do
    local c = { id = "C" }
    local b = { id = "B", delegator = { style = "C" } }
    local a = { id = "A", delegator = { style = "B" } }
    ManagedComps["A"] = a
    ManagedComps["B"] = b
    ManagedComps["C"] = c

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "nil value")

    local keys, count = cache_set("style")
    assert.eq(count, 2, "cache has 2 entries")
    assert.is_true(keys["A"] ~= nil, "A is cached with NIL")
    assert.is_true(keys["B"] ~= nil, "B is cached with NIL")
    assert.is_true(keys["C"] == nil, "C is NOT cached")
end

-- ============================================================
print("=== 4. Missing delegator (A.delegator is not table) ===")
reset()
do
    local a = { id = "A" }
    ManagedComps["A"] = a

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "nil value")

    local keys, count = cache_set("style")
    assert.eq(count, 0, "no cache entries")
end

-- ============================================================
print("=== 5. Cached lookup (second call uses cache) ===")
reset()
do
    local c = { id = "C5", style = { fg = "#555" } }
    local b = { id = "B5", delegator = { style = "C5" } }
    local a = { id = "A5", delegator = { style = "B5" } }
    ManagedComps["A5"] = a
    ManagedComps["B5"] = b
    ManagedComps["C5"] = c

    local val1, owner1 = Resolver.resolve_plain_field(a, "style")
    local val2, owner2 = Resolver.resolve_plain_field(a, "style")
    assert.eq(val1.fg, "#555", "first call value")
    assert.eq(val2.fg, "#555", "second call value")
    assert.eq(owner1.id, "C5", "first call owner")
    assert.eq(owner2.id, "C5", "second call owner")
end

-- ============================================================
print("=== 6. Cycle A→B→A ===")
reset()
do
    local a = { id = "CA", delegator = { style = "CB" } }
    local b = { id = "CB", delegator = { style = "CA" } }
    ManagedComps["CA"] = a
    ManagedComps["CB"] = b

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "cycle returns nil")

    local keys, count = cache_set("style")
    assert.eq(count, 1, "cache has 1 entry (cycle detected before CB enters paths)")
    assert.is_true(keys["CA"] ~= nil, "CA is cached with NIL")
    assert.is_true(keys["CB"] == nil, "CB is NOT cached")
end

-- ============================================================
print("=== 7. NIL result caching A→B→C(nil) then B→C ===")
reset()
do
    local c = { id = "C7" }
    local b = { id = "B7", delegator = { style = "C7" } }
    local a = { id = "A7", delegator = { style = "B7" } }
    ManagedComps["A7"] = a
    ManagedComps["B7"] = b
    ManagedComps["C7"] = c

    -- First call: A7 -> B7 -> C7 (nil)
    local val1 = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val1, "first call nil")

    -- Second call: B7 -> C7 (should use cache)
    local val2 = Resolver.resolve_plain_field(b, "style")
    assert.is_nil(val2, "second call nil (from cache)")

    local keys, count = cache_set("style")
    assert.eq(count, 2, "cache has 2 entries")
    assert.is_true(keys["A7"] ~= nil, "A7 is cached")
    assert.is_true(keys["B7"] ~= nil, "B7 is cached")
    assert.is_true(keys["C7"] == nil, "C7 is NOT cached")
end

-- ============================================================
print("=== 8. Long chain with value in middle A→B→C(value)→D ===")
reset()
do
    local d = { id = "D8" }
    local c = { id = "C8", style = { fg = "#c8" } }
    local b = { id = "B8", delegator = { style = "C8" } }
    local a = { id = "A8", delegator = { style = "B8" } }
    ManagedComps["A8"] = a
    ManagedComps["B8"] = b
    ManagedComps["C8"] = c
    ManagedComps["D8"] = d

    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#c8", "value correct")
    assert.eq(owner.id, "C8", "owner is C8")

    local keys, count = cache_set("style")
    assert.eq(count, 2, "cache has 2 entries")
    assert.is_true(keys["A8"] ~= nil, "A8 is cached")
    assert.is_true(keys["B8"] ~= nil, "B8 is cached")
    assert.is_true(keys["C8"] == nil, "C8 is NOT cached (owner)")
    assert.is_true(keys["D8"] == nil, "D8 is NOT cached")
end

-- ============================================================
print("=== 9. Branching: A→B→C(value), A also delegates to D→E(value) ===")
-- Note: This tests that we only cache the path we actually traversed
reset()
do
    local c = { id = "C9", style = { fg = "#c9" } }
    local b = { id = "B9", delegator = { style = "C9" } }
    local e = { id = "E9", highlight = { fg = "#e9" } }
    local d = { id = "D9", delegator = { highlight = "E9" } }
    local a = { id = "A9", delegator = { style = "B9", highlight = "D9" } }
    ManagedComps["A9"] = a
    ManagedComps["B9"] = b
    ManagedComps["C9"] = c
    ManagedComps["D9"] = d
    ManagedComps["E9"] = e

    -- Resolve style
    local val1 = Resolver.resolve_plain_field(a, "style")
    assert.eq(val1.fg, "#c9", "style value correct")

    -- Resolve highlight
    local val2 = Resolver.resolve_plain_field(a, "highlight")
    assert.eq(val2.fg, "#e9", "highlight value correct")

    local style_keys, style_count = cache_set("style")
    local highlight_keys, highlight_count = cache_set("highlight")

    assert.eq(style_count, 2, "style cache has 2 entries")
    assert.is_true(style_keys["A9"] ~= nil, "A9 is cached for style")
    assert.is_true(style_keys["B9"] ~= nil, "B9 is cached for style")

    assert.eq(highlight_count, 2, "highlight cache has 2 entries")
    assert.is_true(highlight_keys["A9"] ~= nil, "A9 is cached for highlight")
    assert.is_true(highlight_keys["D9"] ~= nil, "D9 is cached for highlight")
end

-- ============================================================
print("=== 10. Cycle with missing value: A→B→C→B (cycle) ===")
reset()
do
    local c = { id = "C10", delegator = { style = "B10" } }
    local b = { id = "B10", delegator = { style = "C10" } }
    local a = { id = "A10", delegator = { style = "B10" } }
    ManagedComps["A10"] = a
    ManagedComps["B10"] = b
    ManagedComps["C10"] = c

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "cycle returns nil")

    local keys, count = cache_set("style")
    assert.eq(count, 2, "cache has 2 entries (A10 and B10 traversed before cycle at C10→B10)")
    assert.is_true(keys["A10"] ~= nil, "A10 is cached with NIL")
    assert.is_true(keys["B10"] ~= nil, "B10 is cached with NIL")
    assert.is_true(keys["C10"] == nil, "C10 is NOT cached (cycle detected here)")
end

-- ============================================================
print("")
local ok = assert.summary()
os.exit(ok and 0 or 1)
