--- Unit tests for witch-line.core.resolver
--- Covers: resolve_plain_field, resolve_field_owner, ref chains, caching, cycles.

local a = require("tests.helpers.assert")

--- Setup: populate ManagedComps and BuiltinComp mocks before loading resolver.
--- We need to mock the registry and component modules that resolver depends on.

local ManagedComps = {}

package.loaded["witch-line.core.registry"] = {
    ManagedComps = setmetatable({}, { __index = ManagedComps })
}

package.loaded["witch-line.component"] = setmetatable({}, { __index = function() return nil end })

package.loaded["witch-line.core.resolver"] = nil
local Resolver = require("witch-line.core.resolver")

local function clear(t)
    for k in pairs(t) do t[k] = nil end
end

local function reset()
    clear(ManagedComps)
    -- Force-reload resolver to clear its internal cache
    package.loaded["witch-line.core.resolver"] = nil
    Resolver = require("witch-line.core.resolver")
end

-- ============================================================
print("=== resolve_plain_field: direct field ===")
reset()

do
    local comp = { id = "c1", style = { fg = "#fff" } }
    ManagedComps["c1"] = comp
    local val, owner = Resolver.resolve_plain_field(comp, "style")
    a.eq(val.fg, "#fff", "direct field resolved")
    a.eq(owner.id, "c1", "owner is self")
end

-- ============================================================
print("=== resolve_plain_field: nil field ===")
reset()

do
    local comp = { id = "c1" }
    ManagedComps["c1"] = comp
    local val, owner = Resolver.resolve_plain_field(comp, "nonexistent")
    a.is_nil(val, "nil field returns nil")
    a.is_nil(owner, "nil owner")
end

-- ============================================================
print("=== resolve_plain_field: ref chain ===")
reset()

do
    local target = { id = "target", style = { fg = "#aaa" } }
    ManagedComps["target"] = target
    local comp = { id = "c1", ref = { style = "target" } }
    ManagedComps["c1"] = comp
    local val, owner = Resolver.resolve_plain_field(comp, "style")
    a.eq(val.fg, "#aaa", "ref chain resolved")
    a.eq(owner.id, "target", "owner is target")
end

-- ============================================================
print("=== resolve_plain_field: ref chain missing target ===")
reset()

do
    local comp = { id = "c1", ref = { style = "nonexistent" } }
    ManagedComps["c1"] = comp
    local val, owner = Resolver.resolve_plain_field(comp, "style")
    a.is_nil(val, "missing ref target => nil")
    a.is_nil(owner)
end

-- ============================================================
print("=== resolve_plain_field: local field takes precedence over ref ===")
reset()

do
    local target = { id = "target", style = { fg = "#aaa" } }
    ManagedComps["target"] = target
    local comp = { id = "c1", style = { fg = "#bbb" }, ref = { style = "target" } }
    ManagedComps["c1"] = comp
    local val, owner = Resolver.resolve_plain_field(comp, "style")
    a.eq(val.fg, "#bbb", "local field wins")
    a.eq(owner.id, "c1", "owner is self")
end

-- ============================================================
print("=== resolve_plain_field: function field resolved as value ===")
reset()

do
    local comp = { id = "c1", update = function() return "x" end }
    ManagedComps["c1"] = comp
    local val, owner = Resolver.resolve_plain_field(comp, "update")
    a.is_type(val, "function", "function field returned as-is")
    a.eq(owner.id, "c1")
end

-- ============================================================
print("=== resolve_field_owner: returns owner ===")
reset()

do
    local comp = { id = "c1", style = { fg = "#fff" } }
    ManagedComps["c1"] = comp
    local owner = Resolver.resolve_field_owner(comp, "style")
    a.eq(owner.id, "c1", "owner found")
end

-- ============================================================
print("=== resolve_field_owner: nil when not found ===")
reset()

do
    local comp = { id = "c1" }
    ManagedComps["c1"] = comp
    local owner = Resolver.resolve_field_owner(comp, "missing")
    a.is_nil(owner, "no owner for missing field")
end

-- ============================================================
print("=== resolve_field_owner: follows ref ===")
reset()

do
    local target = { id = "target", style = { fg = "#aaa" } }
    ManagedComps["target"] = target
    local comp = { id = "c1", ref = { style = "target" } }
    ManagedComps["c1"] = comp
    local owner = Resolver.resolve_field_owner(comp, "style")
    a.eq(owner.id, "target", "owner is ref target")
end

-- ============================================================
print("=== resolve_plain_field: cycle detection ===")
reset()

do
    local a_comp = { id = "a", ref = { style = "b" } }
    local b_comp = { id = "b", ref = { style = "a" } }
    ManagedComps["a"] = a_comp
    ManagedComps["b"] = b_comp
    local val = Resolver.resolve_plain_field(a_comp, "style")
    a.is_nil(val, "cycle resolved to nil without infinite loop")
end

-- ============================================================
print("=== resolve_plain_field: caching ===")
reset()

do
    local comp = { id = "c1", style = { fg = "#fff" } }
    ManagedComps["c1"] = comp
    local v1 = Resolver.resolve_plain_field(comp, "style")
    local v2 = Resolver.resolve_plain_field(comp, "style")
    a.eq(v1.fg, "#fff", "first call")
    a.eq(v2.fg, "#fff", "cached call")
end

-- ============================================================
print("=== resolve_plain_field: ref chain depth 2 ===")
reset()

do
    local leaf = { id = "leaf", style = { fg = "#leaf" } }
    local mid = { id = "mid", ref = { style = "leaf" } }
    local root = { id = "root", ref = { style = "mid" } }
    ManagedComps["leaf"] = leaf
    ManagedComps["mid"] = mid
    ManagedComps["root"] = root
    local val, owner = Resolver.resolve_plain_field(root, "style")
    a.eq(val.fg, "#leaf", "deep ref chain resolved")
    a.eq(owner.id, "leaf", "owner is the leaf")
end

-- ============================================================
-- Summary
-- ============================================================
local ok = a.summary()
os.exit(ok and 0 or 1)
