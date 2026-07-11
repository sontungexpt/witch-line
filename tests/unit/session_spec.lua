--- Unit tests for witch-line.core.session
--- Covers: Session lifecycle, cache, memoization, on_destroy hooks.

local a = require("tests.helpers.assert")
local Session = require("witch-line.core.session")

local function new_session()
    return Session.new()
end

-- ============================================================
print("=== Session: basic get/set ===")

do
    local s = new_session()
    a.is_nil(s:get("missing"), "get missing key returns nil")
    s:set("key1", "value1")
    a.eq(s:get("key1"), "value1", "set then get")
    s:set("key2", 42)
    a.eq(s:get("key2"), 42, "numeric value")
    s:set("key3", true)
    a.eq(s:get("key3"), true, "boolean value")
end

-- ============================================================
print("=== Session: overwrite ===")

do
    local s = new_session()
    s:set("k", "old")
    a.eq(s:get("k"), "old")
    s:set("k", "new")
    a.eq(s:get("k"), "new", "value overwritten")
end

-- ============================================================
print("=== Session: set returns value ===")

do
    local s = new_session()
    local ret = s:set("k", "v")
    a.eq(ret, "v", "set returns the value")
end

-- ============================================================
print("=== Session: cache creates scopes ===")

do
    local s = new_session()
    local scope1 = s:cache("a", "b")
    local scope2 = s:cache("a", "b")
    a.eq(scope1, scope2, "same path returns same scope")
    local scope3 = s:cache("a", "c")
    a.neq(scope1, scope3, "different path returns different scope")
end

-- ============================================================
print("=== Session: cache scope get/set ===")

do
    local s = new_session()
    local scope = s:cache("comp1")
    a.is_nil(scope:get("hl"), "scope starts empty")
    scope:set("hl", "MyHighlight")
    a.eq(scope:get("hl"), "MyHighlight", "scope stores value")
end

-- ============================================================
print("=== Session: cache memoization ===")

do
    local s = new_session()
    local scope = s:cache("comp1")
    local call_count = 0
    local function expensive(x)
        call_count = call_count + 1
        return x * 2
    end
    local r1 = scope:memo(expensive, 5)
    a.eq(r1, 10, "first call returns correct result")
    a.eq(call_count, 1, "function called once")
    local r2 = scope:memo(expensive, 5)
    a.eq(r2, 10, "cached call returns same result")
    a.eq(call_count, 1, "function not called again")
end

-- ============================================================
print("=== Session: cache memo different args ===")

do
    local s = new_session()
    local scope = s:cache("comp1")
    local call_count = 0
    local function fn(x)
        call_count = call_count + 1
        return x + 1
    end
    local r1 = scope:memo(fn, 1)
    -- memo uses fn as cache key; second call with same fn returns cached result
    local r2 = scope:memo(fn, 2)
    a.eq(r1, 2, "first memo result")
    a.eq(r2, 2, "cached result returned (memo ignores args after first call)")
    a.eq(call_count, 1, "function called only once due to memoization")
end

-- ============================================================
print("=== Session: cache memo different functions ===")

do
    local s = new_session()
    local scope = s:cache("comp1")
    local function fn_a() return "a" end
    local function fn_b() return "b" end
    local r1 = scope:memo(fn_a)
    local r2 = scope:memo(fn_b)
    a.eq(r1, "a")
    a.eq(r2, "b", "different functions cached separately")
end

-- ============================================================
print("=== Session: on_destroy hooks ===")

do
    local s = new_session()
    local hook_called = false
    s:on_destroy(function() hook_called = true end)
    s:destroy()
    a.is_true(hook_called, "destroy hook called")
end

-- ============================================================
print("=== Session: on_destroy order ===")

do
    local s = new_session()
    local order = {}
    s:on_destroy(function() order[#order + 1] = "a" end)
    s:on_destroy(function() order[#order + 1] = "b" end)
    s:on_destroy(function() order[#order + 1] = "c" end)
    s:destroy()
    a.eq(order[1], "a", "first hook first")
    a.eq(order[2], "b", "second hook second")
    a.eq(order[3], "c", "third hook third")
end

-- ============================================================
print("=== Session: destroy clears store ===")

do
    local s = new_session()
    s:set("k", "v")
    s:destroy()
    a.is_nil(s:get("k"), "store cleared after destroy")
end

-- ============================================================
print("=== Session: destroy clears cache ===")

do
    local s = new_session()
    local scope = s:cache("comp1")
    scope:set("hl", "MyHL")
    s:destroy()
    a.is_nil(s._cache, "cache table cleared after destroy")
end

-- ============================================================
print("=== Session: with_session lifecycle ===")

do
    local destroyed = false
    Session.with_session(function(s)
        s:set("k", "v")
        s:on_destroy(function() destroyed = true end)
    end)
    a.is_true(destroyed, "session destroyed after with_session callback")
end

-- ============================================================
print("=== Session: multiple scopes independent ===")

do
    local s = new_session()
    local scope_a = s:cache("a")
    local scope_b = s:cache("b")
    scope_a:set("x", 1)
    scope_b:set("x", 2)
    a.eq(scope_a:get("x"), 1, "scope a independent")
    a.eq(scope_b:get("x"), 2, "scope b independent")
end

-- ============================================================
print("=== Session: deep cache path ===")

do
    local s = new_session()
    local scope = s:cache("a", "b", "c", "d")
    scope:set("val", "deep")
    a.eq(scope:get("val"), "deep", "deep path works")
    local scope2 = s:cache("a", "b", "c", "d")
    a.eq(scope2:get("val"), "deep", "same deep path returns same scope")
end

-- ============================================================
print("=== Session: root scope shared across callers ===")

do
    local s = new_session()
    local scope1 = s:cache()
    local scope2 = s:cache()
    a.eq(scope1, scope2, "cache() with no args returns same scope")
    scope1:set("x", 10)
    a.eq(scope2:get("x"), 10, "root scope mutations visible across callers")
end

-- ============================================================
print("=== Session: memo returns same table reference (identity) ===")

do
    local s = new_session()
    local scope = s:cache()
    local call_count = 0
    local function build_table()
        call_count = call_count + 1
        return { ERROR = 5, WARN = 3, INFO = 1, HINT = 0 }
    end
    local t1 = scope:memo(build_table)
    local t2 = scope:memo(build_table)
    a.eq(t1, t2, "memo returns same table reference")
    a.eq(call_count, 1, "function called only once")
    a.is_type(t1, "table", "result is a table")
end

-- ============================================================
print("=== Session: memo table indexing (diagnostic pattern) ===")

do
    local s = new_session()
    local scope = s:cache()
    local function get_counts()
        return { [1] = 7, [2] = 3, [3] = 0, [4] = 2 }
    end
    local count = scope:memo(get_counts)
    a.eq(count[1], 7, "severity ERROR indexed correctly")
    a.eq(count[2], 3, "severity WARN indexed correctly")
    a.eq(count[3], 0, "severity INFO indexed correctly")
    a.eq(count[4], 2, "severity HINT indexed correctly")
end

-- ============================================================
print("=== Session: memo table indexing across calls ===")

do
    local s = new_session()
    local scope = s:cache()
    local call_count = 0
    local function get_counts()
        call_count = call_count + 1
        return { [1] = 7, [2] = 3 }
    end
    -- Simulate two components reading from same cache
    local e1 = scope:memo(get_counts)[1]
    local e2 = scope:memo(get_counts)[1]
    local w1 = scope:memo(get_counts)[2]
    a.eq(e1, 7, "first read correct")
    a.eq(e2, 7, "second read same value")
    a.eq(w1, 3, "different key correct")
    a.eq(call_count, 1, "function called once across all reads")
end

-- ============================================================
print("=== Session: memo table is shared (mutations visible) ===")

do
    local s = new_session()
    local scope = s:cache()
    local function get_tbl()
        return { value = "original" }
    end
    local t1 = scope:memo(get_tbl)
    t1.value = "mutated"
    local t2 = scope:memo(get_tbl)
    a.eq(t2.value, "mutated", "mutation visible through second memo call")
end

-- ============================================================
print("=== Session: root scope vs named scope independent ===")

do
    local s = new_session()
    local root = s:cache()
    local named = s:cache("comp1")
    root:set("k", "root_val")
    named:set("k", "named_val")
    a.eq(root:get("k"), "root_val", "root scope has own value")
    a.eq(named:get("k"), "named_val", "named scope has own value")
end

-- ============================================================
print("=== Session: memo on root scope deduplicates across sessions ===")

do
    local call_count = 0
    local function build()
        call_count = call_count + 1
        return { a = 1 }
    end
    local s1 = new_session()
    local s2 = new_session()
    s1:cache():memo(build)
    s1:cache():memo(build)
    s2:cache():memo(build)
    a.eq(call_count, 2, "same session deduplicates, different session does not")
end

-- ============================================================
-- Summary
-- ============================================================
local ok = a.summary()
os.exit(ok and 0 or 1)
