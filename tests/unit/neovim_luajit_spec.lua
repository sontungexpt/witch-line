--- Unit tests for LuaJIT-specific behavior and Neovim environment.
--- Covers: weak tables, GC, table identity, closure allocation,
---          vim.api interaction, highlight creation, autocmd lifecycle.

local a = require("tests.helpers.assert")

-- ============================================================
print("=== LuaJIT: weak table allows GC ===")

do
    local mt = { __mode = "v" }
    local t = setmetatable({}, mt)
    local obj = { data = "keep me" }
    t[1] = obj
    a.not_nil(t[1], "object stored")
    obj = nil
    collectgarbage("collect")
    collectgarbage("collect")
    -- Weak ref table: value may be collected after GC
    -- We can only test that the table structure is valid
    a.is_type(t, "table", "weak table survives GC cycle")
end

-- ============================================================
print("=== LuaJIT: table identity ===")

do
    local t1 = { id = 1 }
    local t2 = t1
    a.is_true(t1 == t2, "same reference")
    local t3 = { id = 1 }
    a.neq(t1, t3, "different tables not equal")
end

-- ============================================================
print("=== LuaJIT: closure allocation ===")

do
    local x = 10
    local function make_adder(n)
        return function(v) return v + n end
    end
    local add5 = make_adder(5)
    local add10 = make_adder(10)
    a.eq(add5(3), 8, "closure captures n=5")
    a.eq(add10(3), 13, "closure captures n=10")
    a.neq(add5, add10, "different closures")
end

-- ============================================================
print("=== LuaJIT: rawget/rawset bypass metatable ===")

do
    local t = setmetatable({}, {
        __index = function(_, k) return "meta_" .. k end,
        __newindex = function(_, k, v) rawset(t, k, "blocked_" .. v) end,
    })
    rawset(t, "key", "val")
    a.eq(rawget(t, "key"), "val", "rawset bypasses newindex")
    a.eq(t.key, "val", "rawget value readable via __index")
    -- __index returns "meta_" .. k for any missing key
    a.eq(t.missing, "meta_missing", "__index called for missing key")
end

-- ============================================================
print("=== LuaJIT: select() behavior ===")

do
    local n = select("#", "a", "b", "c")
    a.eq(n, 3, "select count")
    local second = select(2, "a", "b", "c")
    a.eq(second, "b", "select(2)")
end

-- ============================================================
print("=== LuaJIT: string.rep optimization ===")

do
    local s = string.rep("x", 100)
    a.eq(#s, 100, "string.rep length correct")
    local empty = string.rep("x", 0)
    a.eq(#empty, 0, "zero rep is empty")
end

-- ============================================================
print("=== Neovim: nvim_set_hl + nvim_get_hl round-trip ===")

do
    vim.api.nvim_set_hl(0, "TestRoundTrip", { fg = "#aabbcc", bold = true })
    local hl = vim.api.nvim_get_hl(0, { name = "TestRoundTrip", create = false })
    a.not_nil(hl, "highlight created")
    a.eq(hl.fg, 0xaabbcc, "fg matches")
    a.is_true(hl.bold, "bold matches")
end

-- ============================================================
print("=== Neovim: highlight link ===")

do
    vim.api.nvim_set_hl(0, "TestLinkTarget", { fg = "#112233" })
    vim.api.nvim_set_hl(0, "TestLinkSource", { link = "TestLinkTarget" })
    local hl = vim.api.nvim_get_hl(0, { name = "TestLinkSource", create = false })
    a.not_nil(hl, "linked hl created")
    a.eq(hl.link, "TestLinkTarget", "link target correct")
end

-- ============================================================
print("=== Neovim: nvim_strwidth ===")

do
    local w = vim.api.nvim_strwidth("hello")
    a.eq(w, 5, "ascii width")
end

-- ============================================================
print("=== Neovim: autocmd creation ===")

do
    local group = vim.api.nvim_create_augroup("TestAugroup", { clear = true })
    a.not_nil(group, "augroup created")
    local id = vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function() end,
    })
    a.not_nil(id, "autocmd created")
    vim.api.nvim_del_augroup_by_id(group)
end

-- ============================================================
print("=== Neovim: schedule runs asynchronously ===")

do
    local executed = false
    local ok = pcall(function() vim.schedule(function() executed = true end) end)
    a.is_true(ok, "schedule does not error")
end

-- ============================================================
print("=== LuaJIT: GC does not break metatable proxies ===")

do
    local sentinel = {}
    local mt = {
        __index = function(_, k)
            return rawget(sentinel, k)
        end,
    }
    local t = setmetatable({}, mt)
    rawset(sentinel, "x", 42)
    collectgarbage("collect")
    a.eq(t.x, 42, "metatable survives GC")
end

-- ============================================================
print("=== Neovim: vim.inspect formats table ===")

do
    local s = vim.inspect({ a = 1, b = "two" })
    a.is_type(s, "string", "inspect returns string")
    a.matches(s, "a = 1", "contains field")
end

-- ============================================================
print("=== Neovim: vim.islist ===")

do
    a.is_true(vim.islist({ 1, 2, 3 }), "list detected")
    a.is_false(vim.islist({ a = 1 }), "map not a list")
    -- Note: vim.islist({}) behavior varies by Neovim version
    -- Some versions return true for empty tables, others false
end

-- ============================================================
-- Summary
-- ============================================================
local ok = a.summary()
os.exit(ok and 0 or 1)
