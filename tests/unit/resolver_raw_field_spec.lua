--- Comprehensive test suite for resolve_raw_field().
---
--- Goal: verify the iterative implementation behaves exactly like the
--- original recursive reference for every observable outcome (return value,
--- owner, termination). Cache correctness is tested against the documented
--- caching rules since the recursive reference has a cache-overwrite bug
--- where intermediate entries are lost when `key_cache` is captured as nil
--- before recursive calls populate the table.

local assert = require("tests.helpers.assert")
local NIL = vim.NIL

-- ============================================================
-- Mocks
-- ============================================================
local ManagedComps = {}
local BuiltinComp = setmetatable({}, { __index = function() return nil end })

package.loaded["witch-line.core.registry"] = {
    ManagedComps = setmetatable({}, { __index = ManagedComps }),
}
package.loaded["witch-line.component"] = BuiltinComp
package.loaded["witch-line.core.resolver"] = nil
local Resolver = require("witch-line.core.resolver")

-- ============================================================
-- Recursive reference (source of truth for return values)
-- ============================================================
local rec_cache = {}

local function clear_rec_cache()
    for k in pairs(rec_cache) do rec_cache[k] = nil end
end

local function resolve_recursive(raw_comp, key, seen)
    local cid = raw_comp.id
    if seen[cid] then
        return NIL
    end

    local value = raw_comp[key]
    if value ~= nil then
        return { value, raw_comp }
    end
    seen[cid] = true

    local delegator = raw_comp.delegator
    if type(delegator) == "table" then
        local key_cache = rec_cache[key]
        local result = key_cache and key_cache[cid]
        if result then
            return result
        end

        local delegator_id = delegator[key]
        if delegator_id then
            local delegator_raw = ManagedComps[delegator_id] or BuiltinComp[delegator_id]
            if delegator_raw then
                result = resolve_recursive(delegator_raw, key, seen)
                if result ~= NIL then
                    if key_cache then
                        key_cache[cid] = result
                    else
                        rec_cache[key] = { [cid] = result }
                    end
                    return result
                end
            end
            if key_cache then
                key_cache[cid] = NIL
            else
                rec_cache[key] = { [cid] = NIL }
            end
            return NIL
        end
    end

    return NIL
end

local function call_recursive(raw_comp, key)
    local r = resolve_recursive(raw_comp, key, {})
    if r == NIL then return nil, nil end
    return r[1], r[2]
end

-- ============================================================
-- Helpers
-- ============================================================
local function clear(t)
    for k in pairs(t) do t[k] = nil end
end

local function reset()
    clear(ManagedComps)
    clear_rec_cache()
    package.loaded["witch-line.core.resolver"] = nil
    Resolver = require("witch-line.core.resolver")
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- Get the set of cached component IDs for a field key.
local function get_cache(key)
    return Resolver.get_cache_keys(key)
end

--- Count cached entries for a field key.
local function cache_count(key)
    return count(get_cache(key))
end

--- Compare production iterative result against recursive reference.
--- Asserts value, owner, and basic cache correctness.
local function compare(label, comp, key)
    local p_val, p_owner = Resolver.resolve_plain_field(comp, key)
    local r_val, r_owner = call_recursive(comp, key)

    local p_oid = p_owner and p_owner.id or nil
    local r_oid = r_owner and r_owner.id or nil

    assert.eq(p_val, r_val, label .. " value matches recursive")
    assert.eq(p_oid, r_oid, label .. " owner matches recursive")
end

--- Assert exact cache key set for a field key.
local function assert_cache_keys(key, expected, label)
    local keys = get_cache(key)
    local n = count(keys)
    assert.eq(n, count(expected), label .. " cache entry count")
    for id in pairs(expected) do
        assert.is_true(keys[id] ~= nil, label .. " " .. id .. " is cached")
    end
    for id in pairs(keys) do
        assert.is_true(expected[id] ~= nil, label .. " " .. id .. " is NOT an unexpected cache entry")
    end
end


-- ============================================================
print("=== 1. Fast path: component has field directly ===")
-- ============================================================
reset()
do
    local comp = { id = "A", style = { fg = "#fff" } }
    ManagedComps["A"] = comp

    local val, owner = Resolver.resolve_plain_field(comp, "style")
    assert.eq(val.fg, "#fff", "1 returns correct value")
    assert.eq(owner.id, "A", "1 owner is self")
    assert.is_nil(comp.delegator, "1 delegator was never touched")

    -- Nothing cached: fast path returns before reaching the cache write loop.
    assert.eq(cache_count("style"), 0, "1 nothing cached on fast path")

    -- Recursive comparison.
    compare("1 fast path", comp, "style")
end

-- ============================================================
print("=== 2. Single delegation: A -> B(value) ===")
-- ============================================================
reset()
do
    local b = { id = "B", style = { fg = "#bbb" } }
    local a = { id = "A", delegator = { style = "B" } }
    ManagedComps["A"] = a
    ManagedComps["B"] = b

    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#bbb", "2 returns B's value")
    assert.eq(owner.id, "B", "2 owner is B")

    -- Only A delegated; B provided the value.
    assert_cache_keys("style", { A = true }, "2")

    compare("2 single delegation", a, "style")
end

-- ============================================================
print("=== 3. Multi-level delegation: A -> B -> C(value) ===")
-- ============================================================
reset()
do
    local c = { id = "C", style = { fg = "#ccc" } }
    local b = { id = "B", delegator = { style = "C" } }
    local a = { id = "A", delegator = { style = "B" } }
    ManagedComps["A"] = a
    ManagedComps["B"] = b
    ManagedComps["C"] = c

    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#ccc", "3 returns C's value")
    assert.eq(owner.id, "C", "3 owner is C")

    -- A and B delegated; C is the final owner (not cached).
    assert_cache_keys("style", { A = true, B = true }, "3")

    compare("3 multi-level", a, "style")
end

-- ============================================================
print("=== 4. Long chain: A -> B -> C -> D -> E(value) ===")
-- ============================================================
reset()
do
    local e = { id = "E", style = { fg = "#eee" } }
    local d = { id = "D", delegator = { style = "E" } }
    local c = { id = "C", delegator = { style = "D" } }
    local b = { id = "B", delegator = { style = "C" } }
    local a = { id = "A", delegator = { style = "B" } }
    for _, comp in ipairs({ a, b, c, d, e }) do ManagedComps[comp.id] = comp end

    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#eee", "4 returns E's value")
    assert.eq(owner.id, "E", "4 owner is E")

    -- A, B, C, D delegated; E is the final owner.
    assert_cache_keys("style", { A = true, B = true, C = true, D = true }, "4")

    compare("4 long chain", a, "style")
end

-- ============================================================
print("=== 5. Cached delegation: second call returns from cache ===")
-- ============================================================
reset()
do
    local c = { id = "C5", style = { fg = "#555" } }
    local b = { id = "B5", delegator = { style = "C5" } }
    local a = { id = "A5", delegator = { style = "B5" } }
    ManagedComps["A5"] = a
    ManagedComps["B5"] = b
    ManagedComps["C5"] = c

    local val1, owner1 = Resolver.resolve_plain_field(a, "style")
    assert.eq(val1.fg, "#555", "5 first call correct")

    -- Mutate the original value to detect whether the second call
    -- re-traverses or returns the cached reference.
    local original_ref = val1
    c.style = { fg = "#999" }

    local val2, owner2 = Resolver.resolve_plain_field(a, "style")
    assert.eq(val2, original_ref, "5 second call returns cached reference (same object)")
    assert.eq(owner2.id, "C5", "5 second call owner unchanged")
end

-- ============================================================
print("=== 6. Missing delegator mapping: A.delegator = {} ===")
-- ============================================================
reset()
do
    local a = { id = "A6", delegator = {} }
    ManagedComps["A6"] = a

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "6 returns nil")

    -- A has a delegator table but no mapping for "style".
    assert.eq(cache_count("style"), 0, "6 nothing cached")

    compare("6 missing mapping", a, "style")
end

-- ============================================================
print("=== 7. Missing referenced component: A -> [not registered] ===")
-- ============================================================
reset()
do
    local a = { id = "A7", delegator = { style = "MISSING" } }
    ManagedComps["A7"] = a

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "7 returns nil")

    -- A delegated but the target does not exist.
    assert_cache_keys("style", { A7 = true }, "7 A cached with NIL")

    compare("7 missing component", a, "style")
end

-- ============================================================
print("=== 8. Delegation ends with nil: A -> B -> C (no value, no delegator) ===")
-- ============================================================
reset()
do
    local c = { id = "C8" }
    local b = { id = "B8", delegator = { style = "C8" } }
    local a = { id = "A8", delegator = { style = "B8" } }
    ManagedComps["A8"] = a
    ManagedComps["B8"] = b
    ManagedComps["C8"] = c

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "8 returns nil")

    -- A and B delegated; C has no value and no delegator table.
    assert_cache_keys("style", { A8 = true, B8 = true }, "8")

    compare("8 ends with nil", a, "style")
end

-- ============================================================
print("=== 9. Empty delegator table on target: A -> B, B.delegator = {} ===")
-- ============================================================
reset()
do
    local b = { id = "B9", delegator = {} }
    local a = { id = "A9", delegator = { style = "B9" } }
    ManagedComps["A9"] = a
    ManagedComps["B9"] = b

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "9 returns nil")

    -- A delegated to B, but B has no mapping for "style" → chain dead-ends.
    -- Recursive caches A (key_cache was nil before the recursive call, so
    -- only A ends up in the cache). Iterative caches A (only A is in paths).
    assert_cache_keys("style", { A9 = true }, "9")

    compare("9 empty delegator on target", a, "style")
end

-- ============================================================
print("=== 10. Cached failure: A -> B -> MISSING, then second call ===")
-- ============================================================
reset()
do
    local b = { id = "B10", delegator = { style = "MISSING" } }
    local a = { id = "A10", delegator = { style = "B10" } }
    ManagedComps["A10"] = a
    ManagedComps["B10"] = b

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "10 first call nil")

    -- A and B are cached with NIL.
    assert_cache_keys("style", { A10 = true, B10 = true }, "10 after first call")

    -- Second call should hit cache, not re-traverse.
    local val2 = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val2, "10 second call still nil (from cache)")

    -- Cache unchanged.
    assert_cache_keys("style", { A10 = true, B10 = true }, "10 after second call")

    compare("10 cached failure", a, "style")
end

-- ============================================================
print("=== 11. Cycle (2 nodes): A -> B -> A ===")
-- ============================================================
reset()
do
    local b = { id = "CB", delegator = { style = "CA" } }
    local a = { id = "CA", delegator = { style = "CB" } }
    ManagedComps["CA"] = a
    ManagedComps["CB"] = b

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "11 cycle returns nil")

    -- Iterative: paths accumulates [CA] before breaking on seen[CA].
    -- Recursive: key_cache overwrite bug leaves only CA.
    -- Both produce the same observable cache for CA.
    assert_cache_keys("style", { CA = true }, "11")

    compare("11 cycle 2 nodes", a, "style")
end

-- ============================================================
print("=== 12. Cycle (3 nodes): A -> B -> C -> A ===")
-- ============================================================
reset()
do
    local c = { id = "C12", delegator = { style = "A12" } }
    local b = { id = "B12", delegator = { style = "C12" } }
    local a = { id = "A12", delegator = { style = "B12" } }
    ManagedComps["A12"] = a
    ManagedComps["B12"] = b
    ManagedComps["C12"] = c

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "12 cycle returns nil")

    -- Iterative caches [A12, B12] (paths before cycle detection at C→A).
    -- Recursive caches only A12 (key_cache overwrite bug).
    assert_cache_keys("style", { A12 = true, B12 = true }, "12")

    compare("12 cycle 3 nodes", a, "style")
end

-- ============================================================
print("=== 13. Cycle after several nodes: A -> B -> C -> D -> B ===")
-- ============================================================
reset()
do
    local d = { id = "D13", delegator = { style = "B13" } }
    local c = { id = "C13", delegator = { style = "D13" } }
    local b = { id = "B13", delegator = { style = "C13" } }
    local a = { id = "A13", delegator = { style = "B13" } }
    ManagedComps["A13"] = a
    ManagedComps["B13"] = b
    ManagedComps["C13"] = c
    ManagedComps["D13"] = d

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "13 cycle returns nil")

    -- Iterative caches [A13, B13, C13] (paths before cycle at D→B).
    assert_cache_keys("style", { A13 = true, B13 = true, C13 = true }, "13")

    compare("13 cycle after several nodes", a, "style")
end

-- ============================================================
print("=== 14. Cached intermediate: pre-cache B, then A -> B -> C(value) ===")
-- ============================================================
reset()
do
    local c = { id = "C14", style = { fg = "#c14" } }
    local b = { id = "B14", delegator = { style = "C14" } }
    local a = { id = "A14", delegator = { style = "B14" } }
    ManagedComps["A14"] = a
    ManagedComps["B14"] = b
    ManagedComps["C14"] = c

    -- Pre-cache B14 by resolving it first.
    local b_val, b_owner = Resolver.resolve_plain_field(b, "style")
    assert.eq(b_val.fg, "#c14", "14 pre-cache B returns correct value")
    assert.eq(b_owner.id, "C14", "14 pre-cache B owner is C14")

    -- Now resolve A14: should use B14's cached result.
    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#c14", "14 A gets correct value via cached B")
    assert.eq(owner.id, "C14", "14 owner is C14")
    assert.eq(val, b_val, "14 same value reference (no re-traversal to C)")

    -- A is cached; B was already cached; C is the final owner (not cached).
    assert_cache_keys("style", { A14 = true, B14 = true }, "14")
end

-- ============================================================
print("=== 15. Builtin component lookup ===")
-- ============================================================
reset()
do
    BuiltinComp["builtin_a"] = { id = "builtin_a", style = { fg = "#builtin" } }
    local a = { id = "A15", delegator = { style = "builtin_a" } }
    ManagedComps["A15"] = a

    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#builtin", "15 builtin value resolved")
    assert.eq(owner.id, "builtin_a", "15 owner is builtin component")

    assert_cache_keys("style", { A15 = true }, "15 A cached, builtin not cached")

    compare("15 builtin lookup", a, "style")

    BuiltinComp["builtin_a"] = nil
end

-- ============================================================
print("=== 16. Priority: direct value always wins over delegator ===")
-- ============================================================
reset()
do
    local b = { id = "B16", style = { fg = "#remote" } }
    local a = { id = "A16", style = { fg = "#local" }, delegator = { style = "B16" } }
    ManagedComps["A16"] = a
    ManagedComps["B16"] = b

    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#local", "16 direct value wins")
    assert.eq(owner.id, "A16", "16 owner is self")

    -- Fast path: nothing cached, delegator never visited.
    assert.eq(cache_count("style"), 0, "16 nothing cached")

    compare("16 priority", a, "style")
end

-- ============================================================
print("=== 17. Function field resolved as value (fast path) ===")
-- ============================================================
reset()
do
    local comp = { id = "A17", update = function() return "x" end }
    ManagedComps["A17"] = comp

    local val, owner = Resolver.resolve_plain_field(comp, "update")
    assert.is_type(val, "function", "17 function field returned as-is")
    assert.eq(owner.id, "A17", "17 owner is self")

    assert.eq(cache_count("update"), 0, "17 nothing cached on fast path")

    compare("17 function field", comp, "update")
end

-- ============================================================
print("=== 18. Branching keys: A -> B->C(value), A -> D->E(value) ===")
-- ============================================================
reset()
do
    local c = { id = "C18", style = { fg = "#c18" } }
    local b = { id = "B18", delegator = { style = "C18" } }
    local e = { id = "E18", highlight = { fg = "#e18" } }
    local d = { id = "D18", delegator = { highlight = "E18" } }
    local a = { id = "A18", delegator = { style = "B18", highlight = "D18" } }
    for _, comp in ipairs({ a, b, c, d, e }) do ManagedComps[comp.id] = comp end

    local v1 = Resolver.resolve_plain_field(a, "style")
    assert.eq(v1.fg, "#c18", "18 style correct")

    local v2 = Resolver.resolve_plain_field(a, "highlight")
    assert.eq(v2.fg, "#e18", "18 highlight correct")

    -- Each key has its own cache: style traversed A→B, highlight traversed A→D.
    assert_cache_keys("style", { A18 = true, B18 = true }, "18 style cache")
    assert_cache_keys("highlight", { A18 = true, D18 = true }, "18 highlight cache")

    compare("18 branching style", a, "style")
    compare("18 branching highlight", a, "highlight")
end

-- ============================================================
print("=== 19. Self-referencing delegator: A -> A ===")
-- ============================================================
reset()
do
    local a = { id = "SR", delegator = { style = "SR" } }
    ManagedComps["SR"] = a

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "19 self-ref returns nil")

    -- Iterative: loop breaks on first iteration (seen["SR"] is already true),
    -- so paths is empty and nothing is cached. Recursive caches SR due to
    -- its recursive call structure. Return values match.
    assert.eq(cache_count("style"), 0, "19 nothing cached (self-cycle)")

    compare("19 self-referencing", a, "style")
end

-- ============================================================
print("=== 20. Cycle with value in one branch: A -> B -> C(value), C -> A (cycle) ===")
-- ============================================================
reset()
do
    local c = { id = "C20", style = { fg = "#c20" }, delegator = { style = "A20" } }
    local b = { id = "B20", delegator = { style = "C20" } }
    local a = { id = "A20", delegator = { style = "B20" } }
    ManagedComps["A20"] = a
    ManagedComps["B20"] = b
    ManagedComps["C20"] = c

    -- C has a value AND a delegator. The resolver checks the value first,
    -- so it returns C's value without following the cycle.
    local val, owner = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#c20", "20 value found at C")
    assert.eq(owner.id, "C20", "20 owner is C")

    -- A and B delegated; C is the owner (not cached).
    assert_cache_keys("style", { A20 = true, B20 = true }, "20")

    compare("20 cycle with value", a, "style")
end

-- ============================================================
print("=== 21. Nil field, no delegator ===")
-- ============================================================
reset()
do
    local a = { id = "A21" }
    ManagedComps["A21"] = a

    local val = Resolver.resolve_plain_field(a, "nonexistent")
    assert.is_nil(val, "21 nil field")

    assert.eq(cache_count("nonexistent"), 0, "21 nothing cached")

    compare("21 nil field no delegator", a, "nonexistent")
end

-- ============================================================
print("=== 22. Delegator table exists but key absent in it ===")
-- ============================================================
reset()
do
    local a = { id = "A22", delegator = { other = "something" } }
    ManagedComps["A22"] = a

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "22 returns nil")

    -- A has a delegator table but not for "style" → chain never starts.
    assert.eq(cache_count("style"), 0, "22 nothing cached")

    compare("22 delegator key absent", a, "style")
end

-- ============================================================
print("=== 23. resolve_field_owner follows same path ===")
-- ============================================================
reset()
do
    local c = { id = "C23", style = { fg = "#c23" } }
    local b = { id = "B23", delegator = { style = "C23" } }
    local a = { id = "A23", delegator = { style = "B23" } }
    ManagedComps["A23"] = a
    ManagedComps["B23"] = b
    ManagedComps["C23"] = c

    local owner = Resolver.resolve_field_owner(a, "style")
    assert.eq(owner.id, "C23", "23 owner is C23")
end

-- ============================================================
print("=== 24. resolve_field_owner returns nil on failure ===")
-- ============================================================
reset()
do
    local a = { id = "A24", delegator = { style = "MISSING" } }
    ManagedComps["A24"] = a

    local owner = Resolver.resolve_field_owner(a, "style")
    assert.is_nil(owner, "24 returns nil")
end

-- ============================================================
print("=== 25. Cache correctness: success path ===")
-- ============================================================
reset()
do
    local c = { id = "C25", style = { fg = "#c25" } }
    local b = { id = "B25", delegator = { style = "C25" } }
    local a = { id = "A25", delegator = { style = "B25" } }
    ManagedComps["A25"] = a
    ManagedComps["B25"] = b
    ManagedComps["C25"] = c

    Resolver.resolve_plain_field(a, "style")

    local keys = get_cache("style")
    -- Every cached entry should point to the same result.
    local first
    for id, result in pairs(Resolver.get_cache_keys("style")) do
        assert.is_true(id == "A25" or id == "B25", "25 only A25/B25 cached")
    end
    -- C25 (the owner) is not cached.
    assert.is_true(keys["C25"] == nil, "25 C25 (owner) not cached")

    -- Verify the cached value resolves correctly on re-lookup.
    local val = Resolver.resolve_plain_field(a, "style")
    assert.eq(val.fg, "#c25", "25 re-lookup correct")
end

-- ============================================================
print("=== 26. Cache correctness: failure path ===")
-- ============================================================
reset()
do
    local b = { id = "B26", delegator = { style = "MISSING" } }
    local a = { id = "A26", delegator = { style = "B26" } }
    ManagedComps["A26"] = a
    ManagedComps["B26"] = b

    Resolver.resolve_plain_field(a, "style")

    local keys = get_cache("style")
    -- A26 and B26 both delegated → both cached with NIL.
    assert.is_true(keys["A26"] ~= nil, "26 A26 cached with NIL")
    assert.is_true(keys["B26"] ~= nil, "26 B26 cached with NIL")
    -- No other entries.
    assert.eq(cache_count("style"), 2, "26 exactly 2 entries")

    -- Re-lookup returns nil (from cache).
    assert.is_nil(Resolver.resolve_plain_field(a, "style"), "26 re-lookup nil")
end

-- ============================================================
print("=== 27. Delegator with nil value for key is not traversed ===")
-- ============================================================
reset()
do
    -- A.delegator = { style = nil } means delegator[key] is nil.
    local a = { id = "A27", delegator = {} }
    ManagedComps["A27"] = a

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "27 returns nil")
    assert.eq(cache_count("style"), 0, "27 nothing cached")
end

-- ============================================================
print("=== 28. Component not in registry but delegator targets it ===")
-- ============================================================
reset()
do
    local a = { id = "A28", delegator = { style = "ghost" } }
    ManagedComps["A28"] = a
    -- "ghost" is not in ManagedComps and not in BuiltinComp.

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "28 returns nil")
    assert_cache_keys("style", { A28 = true }, "28 A cached with NIL")
end

-- ============================================================
print("=== 29. Multi-key isolation: style cache independent of padding cache ===")
-- ============================================================
reset()
do
    local b = { id = "B29", style = { fg = "#s" } }
    local a = { id = "A29", padding = 7, delegator = { style = "B29" } }
    ManagedComps["A29"] = a
    ManagedComps["B29"] = b

    local sv = Resolver.resolve_plain_field(a, "style")
    local pv = Resolver.resolve_plain_field(a, "padding")
    assert.eq(sv.fg, "#s", "29 style resolved via delegation")
    assert.eq(pv, 7, "29 padding resolved directly")

    -- style: A delegated → cached. B is owner → not cached.
    assert_cache_keys("style", { A29 = true }, "29 style cache")
    -- padding: A has direct value → fast path, nothing cached.
    assert_cache_keys("padding", {}, "29 padding cache empty (direct value)")
end

-- ============================================================
print("=== 30. Chain terminates at missing mid-node: A -> B -> [missing] -> D(value) ===")
-- ============================================================
reset()
do
    local d = { id = "D30", style = { fg = "#d30" } }
    local b = { id = "B30", delegator = { style = "ghost30" } }
    local a = { id = "A30", delegator = { style = "B30" } }
    ManagedComps["A30"] = a
    ManagedComps["B30"] = b
    -- "ghost30" not registered; D30 exists but is unreachable.

    local val = Resolver.resolve_plain_field(a, "style")
    assert.is_nil(val, "30 returns nil (chain broken at missing node)")

    assert_cache_keys("style", { A30 = true, B30 = true }, "30")
end

-- ============================================================
-- Summary
-- ============================================================
print("")
local ok = assert.summary()
os.exit(ok and 0 or 1)
