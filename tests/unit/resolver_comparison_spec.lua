--- Behavioral comparison: recursive reference vs iterative implementation.
--- For each scenario, we run both implementations on identical component graphs
--- and compare: (1) return value, (2) owner, (3) cache correctness.

local a = require("tests.helpers.assert")
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

-- ============================================================
-- Recursive reference (source of truth)
-- ============================================================
local recursive_cache = {}
local function clear_recursive_cache()
    for k in pairs(recursive_cache) do recursive_cache[k] = nil end
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
        local key_cache = recursive_cache[key]
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
                        recursive_cache[key] = { [cid] = result }
                    end
                    return result
                end
            end
            if key_cache then
                key_cache[cid] = NIL
            else
                recursive_cache[key] = { [cid] = NIL }
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
-- Iterative (current implementation in resolver.lua)
-- ============================================================
local iterative_cache = {}
local function clear_iterative_cache()
    for k in pairs(iterative_cache) do iterative_cache[k] = nil end
end

local function resolve_iterative(raw_comp, key)
    local raw_value = raw_comp[key]
    if raw_value ~= nil then
        return { raw_value, raw_comp }
    end

    local cid = raw_comp.id
    local field_cache = iterative_cache[key]
    if field_cache == nil then
        field_cache = {}
        iterative_cache[key] = field_cache
    end

    local cached = field_cache[cid]
    if cached then
        return cached
    end

    local seen = { [cid] = true }
    local delegator_table = raw_comp.delegator
    local result

    while true do
        if type(delegator_table) ~= "table" then
            break
        end
        local delegator_id = delegator_table[key]
        if delegator_id == nil or seen[delegator_id] then
            break
        end

        cached = field_cache[delegator_id]
        if cached then
            result = cached
            break
        end

        local next_comp = ManagedComps[delegator_id] or BuiltinComp[delegator_id]
        if next_comp == nil then
            break
        end

        raw_value = next_comp[key]
        if raw_value ~= nil then
            result = { raw_value, next_comp }
            break
        end

        seen[delegator_id] = true
        delegator_table = next_comp.delegator
    end

    result = result or NIL
    for id in next, seen do
        field_cache[id] = result
    end
    return result
end

local function call_iterative(raw_comp, key)
    local r = resolve_iterative(raw_comp, key)
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
    clear_recursive_cache()
    clear_iterative_cache()
end

local function compare(label, raw_comp, key)
    local r_val, r_owner = call_recursive(raw_comp, key)
    local i_val, i_owner = call_iterative(raw_comp, key)

    local r_oid = r_owner and r_owner.id or nil
    local i_oid = i_owner and i_owner.id or nil

    a.eq(i_val, r_val, label .. " value")
    a.eq(i_oid, r_oid, label .. " owner")

    -- Verify recursive cache has no obviously wrong entries
    local r_cache = recursive_cache[key] or {}
    local i_cache = iterative_cache[key] or {}
    for cid, r_result in pairs(r_cache) do
        local i_result = i_cache[cid]
        if r_result == NIL then
            -- Recursive cached NIL; iterative should too (or at least not cache a WRONG value)
            if i_result ~= nil and i_result ~= NIL and type(i_result) == "table" then
                a.fail(label .. " cache[" .. key .. "][" .. cid .. "] has value but recursive has NIL")
            end
        elseif type(r_result) == "table" then
            a.is_type(i_result, "table", label .. " cache[" .. key .. "][" .. cid .. "] type")
            a.eq(i_result[1], r_result[1], label .. " cache[" .. key .. "][" .. cid .. "] value")
            a.eq(i_result[2].id, r_result[2].id, label .. " cache[" .. key .. "][" .. cid .. "] owner")
        end
    end
end

-- ============================================================
-- Test 1: Direct field
-- ============================================================
print("=== Test 1: Direct field ===")
reset()
do
    local comp = { id = "direct", style = { fg = "#fff" } }
    ManagedComps["direct"] = comp
    compare("direct field", comp, "style")
end

-- ============================================================
-- Test 2: Cache reuse
-- ============================================================
print("=== Test 2: Cache reuse ===")
reset()
do
    local comp = { id = "cache1", style = { fg = "#abc" } }
    ManagedComps["cache1"] = comp
    compare("first call", comp, "style")
    compare("second call (cached)", comp, "style")
end

-- ============================================================
-- Test 3: 1-level delegation
-- ============================================================
print("=== Test 3: 1-level delegation ===")
reset()
do
    local target = { id = "t1", style = { fg = "#aaa" } }
    local comp = { id = "a1", delegator = { style = "t1" } }
    ManagedComps["t1"] = target
    ManagedComps["a1"] = comp
    compare("1-level", comp, "style")
end

-- ============================================================
-- Test 4: 4-level delegation chain
-- ============================================================
print("=== Test 4: 4-level delegation chain ===")
reset()
do
    local leaf = { id = "leaf", style = { fg = "#leaf" } }
    local d3 = { id = "d3", delegator = { style = "leaf" } }
    local d2 = { id = "d2", delegator = { style = "d3" } }
    local d1 = { id = "d1", delegator = { style = "d2" } }
    local root = { id = "root", delegator = { style = "d1" } }
    for _, c in ipairs({ leaf, d3, d2, d1, root }) do ManagedComps[c.id] = c end
    compare("4-level chain", root, "style")
end

-- ============================================================
-- Test 5: Mid-chain field
-- ============================================================
print("=== Test 5: Mid-chain field ===")
reset()
do
    local mid = { id = "mid", style = { fg = "#mid" } }
    local a_comp = { id = "a_chain", delegator = { style = "mid" } }
    local b_comp = { id = "b_chain", delegator = { style = "a_chain" } }
    ManagedComps["mid"] = mid
    ManagedComps["a_chain"] = a_comp
    ManagedComps["b_chain"] = b_comp
    compare("mid-chain field", b_comp, "style")
end

-- ============================================================
-- Test 6: Missing delegated component
-- ============================================================
print("=== Test 6: Missing delegated component ===")
reset()
do
    local comp = { id = "miss1", delegator = { style = "nonexistent" } }
    ManagedComps["miss1"] = comp
    compare("missing target", comp, "style")
end

-- ============================================================
-- Test 7: Missing field (no delegator)
-- ============================================================
print("=== Test 7: Missing field, no delegator ===")
reset()
do
    local comp = { id = "miss2" }
    ManagedComps["miss2"] = comp
    compare("nil field no delegator", comp, "nonexistent")
end

-- ============================================================
-- Test 8: Delegator table exists, key absent
-- ============================================================
print("=== Test 8: Delegator table exists, key absent ===")
reset()
do
    local comp = { id = "miss3", delegator = { style = "whatever" } }
    ManagedComps["miss3"] = comp
    compare("delegator key absent", comp, "nonexistent_key")
end

-- ============================================================
-- Test 9: Circular delegation
-- ============================================================
print("=== Test 9: Circular delegation ===")
reset()
do
    local a_comp = { id = "circ_a", delegator = { style = "circ_b" } }
    local b_comp = { id = "circ_b", delegator = { style = "circ_a" } }
    ManagedComps["circ_a"] = a_comp
    ManagedComps["circ_b"] = b_comp
    compare("cycle a→b→a", a_comp, "style")
end

-- ============================================================
-- Test 10: Cycle but root has direct field
-- ============================================================
print("=== Test 10: Cycle but root has direct field ===")
reset()
do
    local a_comp = { id = "cyc2_a", style = { fg = "#here" }, delegator = { style = "cyc2_b" } }
    local b_comp = { id = "cyc2_b", delegator = { style = "cyc2_a" } }
    ManagedComps["cyc2_a"] = a_comp
    ManagedComps["cyc2_b"] = b_comp
    compare("cycle but direct wins", a_comp, "style")
end

-- ============================================================
-- Test 11: No delegator field
-- ============================================================
print("=== Test 11: No delegator field ===")
reset()
do
    local comp = { id = "nodel" }
    ManagedComps["nodel"] = comp
    compare("no delegator field", comp, "style")
end

-- ============================================================
-- Test 12: Delegator table but key not in it
-- ============================================================
print("=== Test 12: Delegator table but key not in it ===")
reset()
do
    local comp = { id = "dkeynil", delegator = { other = "something" } }
    ManagedComps["dkeynil"] = comp
    compare("delegator key nil", comp, "style")
end

-- ============================================================
-- Test 13: Multiple keys independently
-- ============================================================
print("=== Test 13: Multiple keys ===")
reset()
do
    local target = { id = "mk_target", style = { fg = "#a" }, padding = 3 }
    local comp = { id = "mk_comp", delegator = { style = "mk_target", padding = "mk_target" } }
    ManagedComps["mk_target"] = target
    ManagedComps["mk_comp"] = comp
    compare("style via delegator", comp, "style")
    compare("padding via delegator", comp, "padding")
end

-- ============================================================
-- Test 14: Branching chains
-- ============================================================
print("=== Test 14: Branching chains ===")
reset()
do
    local leaf = { id = "br_leaf", style = { fg = "#br" } }
    local b = { id = "br_b", delegator = { style = "br_leaf" } }
    local c = { id = "br_c", delegator = { style = "br_leaf" } }
    local a_comp = { id = "br_a", delegator = { style = "br_b" } }
    for _, v in ipairs({ leaf, b, c, a_comp }) do ManagedComps[v.id] = v end
    compare("branch A→B→leaf", a_comp, "style")
end

-- ============================================================
-- Test 15: Self-referencing delegator
-- ============================================================
print("=== Test 15: Self-referencing delegator ===")
reset()
do
    local comp = { id = "self_ref", delegator = { style = "self_ref" } }
    ManagedComps["self_ref"] = comp
    compare("self ref", comp, "style")
end

-- ============================================================
-- Test 16: Builtin component fallback
-- ============================================================
print("=== Test 16: Builtin component fallback ===")
reset()
do
    BuiltinComp["builtin_1"] = { id = "builtin_1", style = { fg = "#builtin" } }
    local comp = { id = "use_builtin", delegator = { style = "builtin_1" } }
    ManagedComps["use_builtin"] = comp
    compare("builtin fallback", comp, "style")
    BuiltinComp["builtin_1"] = nil
end

-- ============================================================
-- Summary
-- ============================================================
print("")
local ok = a.summary()
os.exit(ok and 0 or 1)
