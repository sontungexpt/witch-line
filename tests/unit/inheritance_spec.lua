--- Unit tests for witch-line.core.comp.behavior
--- Covers: resolve_inherited_value, evaluate, hidden, theme_aware, normalize_style

local a = require("tests.helpers.assert")
local F = require("tests.helpers.component_factory")
local B = require("witch-line.core.comp.behavior")

--- Create a resolver from a components table.
local function make_resolver(components)
    return function(id) return components[id] end
end

-- ============================================================
print("=== resolve_inherited_value: no parent, static ===")

do
    local comp = F.make_comp({ style = { fg = "#fff" } })
    local val, dynamic, count = B.resolve_inherited_value(comp, "style", make_resolver({}), nil)
    a.eq(val.fg, "#fff", "own value returned")
    a.is_false(dynamic, "static is not dynamic")
    a.eq(count, 0, "no inheritance")
end

-- ============================================================
print("=== resolve_inherited_value: no parent, nil ===")

do
    local comp = F.make_comp({})
    local val, dynamic, count = B.resolve_inherited_value(comp, "style", make_resolver({}), nil)
    a.is_nil(val, "nil field returns nil")
    a.is_false(dynamic)
end

-- ============================================================
print("=== resolve_inherited_value: dynamic function field ===")

do
    local comp = F.make_comp({ style = function() return { fg = "#aaa" } end })
    local val, dynamic = B.resolve_inherited_value(comp, "style", make_resolver({}), nil)
    a.eq(val.fg, "#aaa", "dynamic function resolved")
    a.is_true(dynamic, "marked dynamic")
end

-- ============================================================
print("=== resolve_inherited_value: one parent, no merge ===")

do
    local parent = F.make_comp({ left = "<<" })
    local comp = F.make_comp({ ___parent_id = parent.id })
    local val = B.resolve_inherited_value(comp, "left", make_resolver({ [parent.id] = parent }), nil)
    a.eq(val, "<<", "inherited from parent")
end

-- ============================================================
print("=== resolve_inherited_value: own + parent, no merge => parent wins ===")

do
    local parent = F.make_comp({ left = "P" })
    local comp = F.make_comp({ left = "C", ___parent_id = parent.id })
    local val = B.resolve_inherited_value(comp, "left", make_resolver({ [parent.id] = parent }), nil)
    a.eq(val, "P", "parent overrides when no merge_fn")
end

-- ============================================================
print("=== resolve_inherited_value: with merge_fn accumulates ===")

do
    local parent = F.make_comp({ style = { fg = "#111" } })
    local comp = F.make_comp({ style = { bg = "#222" }, ___parent_id = parent.id })
    local merge = function(child, par)
        local merged = {}
        for k, v in pairs(par) do merged[k] = v end
        for k, v in pairs(child) do merged[k] = v end
        return merged
    end
    local val, _, count = B.resolve_inherited_value(comp, "style", make_resolver({ [parent.id] = parent }), merge)
    a.eq(val.bg, "#222", "child bg present")
    a.eq(val.fg, "#111", "parent fg inherited")
    a.eq(count, 1, "one inheritance")
end

-- ============================================================
print("=== resolve_inherited_value: deep chain, no merge ===")

do
    local comps = F.make_deep_chain(5, { left = "deep" })
    local lookup = {}
    for _, c in ipairs(comps) do lookup[c.id] = c end
    local resolver = make_resolver(lookup)
    local leaf = comps[5]
    local val = B.resolve_inherited_value(leaf, "left", resolver, nil)
    a.eq(val, "deep", "inherited from root through chain")
end

-- ============================================================
print("=== resolve_inherited_value: parent not found ===")

do
    local comp = F.make_comp({ ___parent_id = "nonexistent" })
    local val = B.resolve_inherited_value(comp, "left", make_resolver({}), nil)
    a.is_nil(val, "missing parent => nil")
end

-- ============================================================
print("=== resolve_inherited_value: cycle detection ===")

do
    local a_comp = F.make_comp({ left = "a" })
    local b_comp = F.make_comp({ left = "b", ___parent_id = a_comp.id })
    a_comp.___parent_id = b_comp.id -- create cycle
    local resolver = make_resolver({ [a_comp.id] = a_comp, [b_comp.id] = b_comp })
    local val, dynamic = B.resolve_inherited_value(a_comp, "left", resolver, nil)
    -- The function should handle the cycle without infinite loop
    a.not_nil(val, "cycle does not cause infinite loop")
end

-- ============================================================
print("=== resolve_inherited_value: caching static results ===")

do
    local comp = F.make_comp({ left = "cached" })
    local resolver = make_resolver({})
    local v1 = B.resolve_inherited_value(comp, "left", resolver, nil)
    local v2 = B.resolve_inherited_value(comp, "left", resolver, nil)
    a.eq(v1, "cached", "first call")
    a.eq(v2, "cached", "cached call")
    a.is_false(v1 == nil, "not nil")
end

-- ============================================================
print("=== evaluate: string update ===")

do
    local comp = F.make_comp({ update = function() return "hello" end, padding = 0 })
    local val, style = B.evaluate(comp)
    a.eq(val, "hello", "string returned")
    a.is_nil(style, "no style override")
end

-- ============================================================
print("=== evaluate: numeric padding ===")

do
    local comp = F.make_comp({ update = function() return "hi" end, padding = 2 })
    local val = B.evaluate(comp)
    a.eq(val, "  hi  ", "padding applied")
end

-- ============================================================
print("=== evaluate: zero padding ===")

do
    local comp = F.make_comp({ update = function() return "hi" end, padding = 0 })
    local val = B.evaluate(comp)
    a.eq(val, "hi", "zero padding no change")
end

-- ============================================================
print("=== evaluate: table padding ===")

do
    local comp = F.make_comp({
        update = function() return "x" end,
        padding = { left = 2, right = 3 },
    })
    local val = B.evaluate(comp)
    a.eq(val, "  x   ", "table padding applied")
end

-- ============================================================
print("=== evaluate: nil padding defaults to 1 ===")

do
    local comp = F.make_comp({ update = function() return "y" end })
    local val = B.evaluate(comp)
    a.eq(val, " y ", "default padding 1")
end

-- ============================================================
print("=== evaluate: style override from update ===")

do
    local comp = F.make_comp({
        update = function() return "v", { fg = "#fff" } end,
        padding = 0,
    })
    local val, style = B.evaluate(comp)
    a.eq(val, "v")
    a.eq(style.fg, "#fff", "style override returned")
end

-- ============================================================
print("=== evaluate: non-string result => empty ===")

do
    local comp = F.make_comp({ update = function() return 123 end })
    local val = B.evaluate(comp)
    a.eq(val, "", "non-string => empty")
end

-- ============================================================
print("=== evaluate: empty string => empty ===")

do
    local comp = F.make_comp({ update = function() return "" end })
    local val = B.evaluate(comp)
    a.eq(val, "", "empty stays empty")
end

-- ============================================================
print("=== evaluate: static update field (non-function) ===")

do
    local comp = F.make_comp({ update = "static text", padding = 0 })
    local val = B.evaluate(comp)
    a.eq(val, "static text", "static update field used as value")
end

-- ============================================================
print("=== hidden: true ===")

do
    local comp = F.make_comp({ hidden = true })
    a.is_true(B.hidden(comp), "hidden=true returns true")
end

-- ============================================================
print("=== hidden: false ===")

do
    local comp = F.make_comp({ hidden = false })
    a.is_false(B.hidden(comp), "hidden=false returns false")
end

-- ============================================================
print("=== hidden: nil ===")

do
    local comp = F.make_comp({})
    a.is_false(B.hidden(comp), "nil hidden returns false")
end

-- ============================================================
print("=== hidden: dynamic function ===")

do
    local comp = F.make_comp({ hidden = function() return true end })
    a.is_true(B.hidden(comp), "dynamic hidden function")
end

-- ============================================================
print("=== theme_aware: builtin default ===")

do
    local comp = F.make_comp({ ___builtin = true })
    a.is_true(B.theme_aware(comp), "builtin defaults to theme_aware=true")
end

-- ============================================================
print("=== theme_aware: non-builtin default ===")

do
    local comp = F.make_comp({ ___builtin = false })
    a.is_false(B.theme_aware(comp), "non-builtin defaults to theme_aware=false")
end

-- ============================================================
print("=== theme_aware: explicit override ===")

do
    local comp = F.make_comp({ ___builtin = true, theme_aware = false })
    a.is_false(B.theme_aware(comp), "explicit false overrides builtin default")
end

-- ============================================================
print("=== theme_aware: dynamic function ===")

do
    local comp = F.make_comp({ ___builtin = true, theme_aware = function() return false end })
    a.is_false(B.theme_aware(comp), "dynamic theme_aware function")
end

-- ============================================================
print("=== normalize_style: attaches theme_aware ===")

do
    local style = { fg = "#fff" }
    local result = B.normalize_style(style, true)
    a.eq(result.theme_aware, true, "theme_aware set")
    a.eq(result.fg, "#fff", "original fields preserved")
end

-- ============================================================
print("=== normalize_style: does not overwrite existing ===")

do
    local style = { fg = "#fff", theme_aware = false }
    local result = B.normalize_style(style, true)
    a.is_false(result.theme_aware, "existing theme_aware not overwritten")
end

-- ============================================================
print("=== normalize_style: non-table passthrough ===")

do
    local result = B.normalize_style("MyHL", true)
    a.eq(result, "MyHL", "string passthrough")
end

-- ============================================================
-- Summary
-- ============================================================
local ok = a.summary()
os.exit(ok and 0 or 1)
