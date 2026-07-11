--- Unit tests for witch-line.core.comp.proxy
--- Covers: bind, field access, function memoization, ref resolution, newindex.

local a = require("tests.helpers.assert")
local Session = require("witch-line.core.session")

--- We need to mock registry and component modules for the resolver.
local ManagedComps = {}

package.loaded["witch-line.core.registry"] = {
    ManagedComps = setmetatable({}, { __index = ManagedComps })
}

package.loaded["witch-line.component"] = setmetatable({}, {
    __index = function() return nil end,
})

package.loaded["witch-line.core.resolver"] = nil
package.loaded["witch-line.core.comp.proxy"] = nil
local Proxy = require("witch-line.core.comp.proxy")

local function clear(t)
    for k in pairs(t) do t[k] = nil end
end

local function reset()
    clear(ManagedComps)
end

-- ============================================================
print("=== bind: returns proxy with correct id ===")
reset()

do
    local comp = { id = "c1" }
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    a.eq(proxy.id, "c1", "proxy has component id")
    session:destroy()
end

-- ============================================================
print("=== bind: get_raw_comp ===")
reset()

do
    local comp = { id = "c1" }
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    a.eq(Proxy.get_raw_comp(proxy), comp, "raw comp retrieved")
    session:destroy()
end

-- ============================================================
print("=== bind: get_session ===")
reset()

do
    local comp = { id = "c1" }
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    a.eq(Proxy.get_session(proxy), session, "session retrieved")
    session:destroy()
end

-- ============================================================
print("=== proxy: read non-function field ===")
reset()

do
    local comp = { id = "c1", style = { fg = "#fff" } }
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    a.eq(proxy.style.fg, "#fff", "non-function field returned directly")
    session:destroy()
end

-- ============================================================
print("=== proxy: read nil field ===")
reset()

do
    local comp = { id = "c1" }
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    a.is_nil(proxy.nonexistent, "nil field stays nil")
    session:destroy()
end

-- ============================================================
print("=== proxy: write field via newindex ===")
reset()

do
    local comp = { id = "c1" }
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    proxy.new_key = "new_value"
    a.eq(comp.new_key, "new_value", "write goes to raw comp")
    a.eq(proxy.new_key, "new_value", "read returns written value")
    session:destroy()
end

-- ============================================================
print("=== proxy: function field memoization ===")
reset()

do
    local comp = { id = "c1" }
    local call_count = 0
    comp.update = function(self)
        call_count = call_count + 1
        return "result"
    end
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    local fn1 = proxy.update
    local fn2 = proxy.update
    -- Both should be wrapper functions (not the same ref, but same memoized result)
    a.is_type(fn1, "function", "function field wrapped")
    a.is_type(fn2, "function", "second access also wrapped")
    session:destroy()
end

-- ============================================================
print("=== proxy: function with ref chain ===")
reset()

do
    local target = { id = "target" }
    target.get_color = function(self) return "#target_color" end
    ManagedComps["target"] = target

    local comp = { id = "c1", ref = { get_color = "target" } }
    ManagedComps["c1"] = comp

    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    -- Accessing a ref-resolved function should work
    local fn = proxy.get_color
    a.is_type(fn, "function", "ref function wrapped")
    session:destroy()
end

-- ============================================================
print("=== proxy: different proxies, same raw comp ===")
reset()

do
    local comp = { id = "c1", style = { fg = "#aaa" } }
    local session = Session.new()
    local p1 = Proxy.bind(comp, session)
    local p2 = Proxy.bind(comp, session)
    a.eq(p1.style.fg, p2.style.fg, "same underlying data")
    session:destroy()
end

-- ============================================================
print("=== proxy: write through proxy visible on raw ===")
reset()

do
    local comp = { id = "c1" }
    local session = Session.new()
    local proxy = Proxy.bind(comp, session)
    proxy.left = ">>"
    a.eq(comp.left, ">>", "write through proxy visible on raw")
    session:destroy()
end

-- ============================================================
-- Summary
-- ============================================================
local ok = a.summary()
os.exit(ok and 0 or 1)
