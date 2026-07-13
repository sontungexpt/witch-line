--- Tests for separator behavior in witch-line.core.comp.behavior
--- Covers: SepStyle enum, side(), side_style(), resolved_side_style(), hl_name_field()
---
--- Run: nvim --headless -u tests/minimal_init.lua
---        -c "luafile tests/separator_spec.lua" -c "qa!"

local helper = require("tests.helper")
local eq = helper.eq
local is_nil = helper.is_nil
local not_nil = helper.not_nil
local is_true = helper.is_true
local is_false = helper.is_false

local B = require("witch-line.core.comp.behavior")
local SepStyle = B.SepStyle

-- ====================================================================
-- Helpers
-- ====================================================================

--- Build a minimal managed component with unique ID to avoid cache collisions.
local _comp_counter = 0
local function make_comp(fields)
    _comp_counter = _comp_counter + 1
    return vim.tbl_extend("force", {
        id = "test.comp." .. _comp_counter,
        ___parent_id = nil,
    }, fields or {})
end

--- Stub resolve_parent_fn that looks up a table of components by id.
local function make_resolver(components)
    return function(id) return components[id] end
end

-- ====================================================================
-- SepStyle enum
-- ====================================================================
print("=== SepStyle enum ===")

do
    eq(SepStyle.Inherited, 0, "Inherited == 0")
    eq(SepStyle.SepFg, 1, "SepFg == 1")
    eq(SepStyle.SepBg, 2, "SepBg == 2")
    eq(SepStyle.Reverse, 3, "Reverse == 3")
end

-- ====================================================================
-- hl_name_field
-- ====================================================================
print("=== hl_name_field ===")

do
    eq(B.hl_name_field("left"), "___left_hl_name", "left -> ___left_hl_name")
    eq(B.hl_name_field("right"), "___right_hl_name", "right -> ___right_hl_name")
end

-- ====================================================================
-- side_style (raw style lookup)
-- ====================================================================
print("=== side_style ===")

do
    local comp = make_comp({ left_style = SepStyle.Reverse })
    eq(B.side_style(comp, "left"), SepStyle.Reverse, "returns left_style")
end

do
    local comp = make_comp({ right_style = SepStyle.SepFg })
    eq(B.side_style(comp, "right"), SepStyle.SepFg, "returns right_style")
end

do
    local comp = make_comp({})
    eq(B.side_style(comp, "left"), SepStyle.SepBg, "defaults to SepBg when nil")
    eq(B.side_style(comp, "right"), SepStyle.SepBg, "defaults to SepBg for right too")
end

do
    local comp = make_comp({ left_style = { fg = "#aaa", bg = "#bbb" } })
    local s = B.side_style(comp, "left")
    eq(s.fg, "#aaa", "returns custom style table")
    eq(s.bg, "#bbb")
end

-- ====================================================================
-- side() — static resolution
-- ====================================================================
print("=== side(): static ===")

do
    local comp = make_comp({ left = ">>" })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, ">>", "returns static string")
    is_false(dynamic, "not dynamic")
end

do
    local comp = make_comp({ left = 123 })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    is_nil(val, "non-string static returns nil")
    is_false(dynamic)
end

do
    local comp = make_comp({})
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    is_nil(val, "missing field returns nil")
    is_false(dynamic)
end

-- ====================================================================
-- side() — dynamic resolution
-- ====================================================================
print("=== side(): dynamic ===")

do
    local comp = make_comp({ left = function() return ">>" end })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, ">>", "dynamic function returns string")
    is_true(dynamic, "marked dynamic")
end

do
    local comp = make_comp({ left = function() return 999 end })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, "", "non-string dynamic returns empty string")
    is_true(dynamic)
end

do
    local comp = make_comp({ left = function() return nil end })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, "", "nil dynamic returns empty string")
    is_true(dynamic)
end

-- ====================================================================
-- side() — inheritance
-- ====================================================================
print("=== side(): inheritance ===")

do
    local parent = make_comp({ left = "<<" })
    local comp = make_comp({ left = ">>", ___parent_id = parent.id })
    local resolver = make_resolver({ [parent.id] = parent })
    local val = B.side(comp, "left", resolver)
    eq(val, "<<", "parent value wins (inheritance overrides)")
end

do
    local parent = make_comp({ left = "<<" })
    local comp = make_comp({ ___parent_id = parent.id })
    local resolver = make_resolver({ [parent.id] = parent })
    local val = B.side(comp, "left", resolver)
    eq(val, "<<", "inherits from parent")
end

do
    local grandparent = make_comp({ left = "gp-val" })
    local parent = make_comp({ ___parent_id = grandparent.id })
    local comp = make_comp({ ___parent_id = parent.id })
    local resolver = make_resolver({ [parent.id] = parent, [grandparent.id] = grandparent })
    local val = B.side(comp, "left", resolver)
    eq(val, "gp-val", "inherits from grandparent")
end

do
    local comp = make_comp({ ___parent_id = "missing" })
    local resolver = make_resolver({})
    local val = B.side(comp, "left", resolver)
    is_nil(val, "missing parent returns nil")
end

-- ====================================================================
-- resolved_side_style(): SepBg (default)
-- ====================================================================
print("=== resolved_side_style(): SepBg ===")

do
    local comp = make_comp({})
    local main_style = { fg = "#ffffff", bg = "#333333" }
    local style, dynamic, inherited = B.resolved_side_style(comp, "left", main_style, false)
    eq(style.fg, "#333333", "SepBg uses main bg as fg")
    eq(style.bg, "NONE", "SepBg sets bg=NONE")
    is_false(dynamic)
    is_false(inherited)
end

-- ====================================================================
-- resolved_side_style(): SepFg
-- ====================================================================
print("=== resolved_side_style(): SepFg ===")

do
    local comp = make_comp({ left_style = SepStyle.SepFg })
    local main_style = { fg = "#ffffff", bg = "#333333" }
    local style = B.resolved_side_style(comp, "left", main_style, false)
    eq(style.fg, "#ffffff", "SepFg uses main fg as fg")
    eq(style.bg, "NONE", "SepFg sets bg=NONE")
end

-- ====================================================================
-- resolved_side_style(): Reverse
-- ====================================================================
print("=== resolved_side_style(): Reverse ===")

do
    local comp = make_comp({ right_style = SepStyle.Reverse })
    local main_style = { fg = "#ffffff", bg = "#333333" }
    local style = B.resolved_side_style(comp, "right", main_style, false)
    eq(style.fg, "#333333", "Reverse uses bg as fg")
    eq(style.bg, "#ffffff", "Reverse uses fg as bg")
end

-- ====================================================================
-- resolved_side_style(): Inherited
-- ====================================================================
print("=== resolved_side_style(): Inherited ===")

do
    local comp = make_comp({ left_style = SepStyle.Inherited })
    local main_style = { fg = "#ffffff", bg = "#333333" }
    local style, dynamic, inherited = B.resolved_side_style(comp, "left", main_style, false)
    is_nil(style, "Inherited returns nil style")
    is_true(inherited, "inherited flag set")
end

-- ====================================================================
-- resolved_side_style(): no main_style fallback
-- ====================================================================
print("=== resolved_side_style(): no main_style ===")

do
    local comp = make_comp({})
    local style, dynamic, inherited = B.resolved_side_style(comp, "left", nil, false)
    is_nil(style, "no main_style returns nil for numeric side_style")
end

-- ====================================================================
-- resolved_side_style(): custom table
-- ====================================================================
print("=== resolved_side_style(): custom table ===")

do
    local comp = make_comp({ left_style = { fg = "#aaa", bold = true } })
    local style = B.resolved_side_style(comp, "left", nil, false)
    eq(style.fg, "#aaa", "custom fg preserved")
    is_true(style.bold, "custom attributes preserved")
end

-- ====================================================================
-- resolved_side_style(): custom string
-- ====================================================================
print("=== resolved_side_style(): custom string ===")

do
    local comp = make_comp({ left_style = "MyHighlight" })
    local style = B.resolved_side_style(comp, "left", nil, false)
    eq(style, "MyHighlight", "string style passed through")
end

-- ====================================================================
-- resolved_side_style(): theme_aware normalization
-- ====================================================================
print("=== resolved_side_style(): theme_aware ===")

do
    local comp = make_comp({ left_style = { fg = "#aaa" } })
    local style = B.resolved_side_style(comp, "left", nil, true)
    eq(style.theme_aware, true, "theme_aware set to true")

    local comp2 = make_comp({ left_style = { fg = "#bbb" } })
    local style2 = B.resolved_side_style(comp2, "left", nil, false)
    eq(style2.theme_aware, false, "theme_aware set to false")
end

-- ====================================================================
-- resolved_side_style(): dynamic function style
-- ====================================================================
print("=== resolved_side_style(): dynamic function style ===")

do
    local comp = make_comp({
        left_style = function(_, custom_fg)
            return { fg = custom_fg, bg = "NONE" }
        end,
    })
    local main_style = { fg = "#deadbeef", bg = "#111111" }
    local style, dynamic, inherited = B.resolved_side_style(comp, "left", main_style, false, "#cafebabe")
    eq(style.fg, "#cafebabe", "dynamic function receives varargs")
    eq(style.bg, "NONE", "dynamic function resolved bg")
    is_true(dynamic, "marked dynamic")
    is_false(inherited)
end

-- ====================================================================
-- resolved_side_style(): dynamic returning SepStyle enum
-- ====================================================================
print("=== resolved_side_style(): dynamic returning enum ===")

do
    local comp = make_comp({
        left_style = function() return SepStyle.SepFg end,
    })
    local main_style = { fg = "#aaaaaa", bg = "#222222" }
    local style, dynamic = B.resolved_side_style(comp, "left", main_style, false)
    eq(style.fg, "#aaaaaa", "dynamic SepFg uses main fg")
    eq(style.bg, "NONE")
    is_true(dynamic)
end

-- ====================================================================
-- resolved_side_style(): unknown enum falls through
-- ====================================================================
print("=== resolved_side_style(): unknown enum ===")

do
    local comp = make_comp({ left_style = 999 })
    local main_style = { fg = "#fff", bg = "#000" }
    local style, _, inherited = B.resolved_side_style(comp, "left", main_style, false)
    is_nil(style, "unknown numeric enum returns nil")
    is_false(inherited)
end

-- ====================================================================
-- side() — edge cases
-- ====================================================================
print("=== side(): edge cases ===")

do
    local comp = make_comp({ left = "" })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, "", "empty string is a valid side value")
    is_false(dynamic)
end

do
    local comp = make_comp({ left = true })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    is_nil(val, "boolean static returns nil")
    is_false(dynamic)
end

do
    local comp = make_comp({ left = false })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    is_nil(val, "false static returns nil")
    is_false(dynamic)
end

do
    local comp = make_comp({ left = function() return true end })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, "", "dynamic returning bool returns empty string")
    is_true(dynamic)
end

do
    local comp = make_comp({ left = function() return "" end })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, "", "dynamic returning empty string is valid")
    is_true(dynamic)
end

do
    local comp = make_comp({ left = function() return {} end })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(val, "", "dynamic returning table returns empty string")
    is_true(dynamic)
end

do
    local call_count = 0
    local comp = make_comp({ left = function()
        call_count = call_count + 1
        return ">>"
    end })
    local val1 = B.side(comp, "left", make_resolver({}))
    local val2 = B.side(comp, "left", make_resolver({}))
    eq(val1, ">>", "first call works")
    eq(val2, ">>", "second call works")
    eq(call_count, 2, "dynamic function called each time (no cache)")
end

-- ====================================================================
-- side() — inheritance edge cases
-- ====================================================================
print("=== side(): inheritance edge cases ===")

do
    local parent = make_comp({ left = function() return "dynamic-parent" end })
    local comp = make_comp({ ___parent_id = parent.id })
    local resolver = make_resolver({ [parent.id] = parent })
    local val, dynamic = B.side(comp, "left", resolver)
    eq(val, "dynamic-parent", "inherits dynamic parent value")
    is_true(dynamic, "inherited dynamic function marks dynamic")
end

do
    local grandparent = make_comp({ left = "gp" })
    local parent = make_comp({ ___parent_id = grandparent.id })
    local comp = make_comp({ ___parent_id = parent.id })
    local resolver = make_resolver({
        [parent.id] = parent,
        [grandparent.id] = grandparent,
    })
    local val = B.side(comp, "left", resolver)
    eq(val, "gp", "skips parent without value, inherits grandparent")
end

do
    local grandparent = make_comp({ left = "gp" })
    local parent = make_comp({ ___parent_id = grandparent.id, left = 123 })
    local comp = make_comp({ ___parent_id = parent.id })
    local resolver = make_resolver({
        [parent.id] = parent,
        [grandparent.id] = grandparent,
    })
    local val = B.side(comp, "left", resolver)
    is_nil(val, "parent with invalid type blocks grandparent inheritance (stops at first non-nil)")
end

do
    local parent_a = make_comp({ left = "a" })
    local parent_b = make_comp({ left = "b", ___parent_id = parent_a.id })
    local comp = make_comp({ ___parent_id = parent_b.id })
    local resolver = make_resolver({
        [parent_a.id] = parent_a,
        [parent_b.id] = parent_b,
    })
    local val = B.side(comp, "left", resolver)
    eq(val, "b", "stops at nearest parent with value")
end

do
    local parent = make_comp({ ___parent_id = "nonexistent" })
    local comp = make_comp({ ___parent_id = parent.id })
    local resolver = make_resolver({ [parent.id] = parent })
    local val = B.side(comp, "left", resolver)
    is_nil(val, "parent with broken chain returns nil")
end

do
    local comp = make_comp({})
    local val = B.side(comp, "left", function() error("should not be called") end)
    is_nil(val, "no parent_id means resolver is never called")
end

do
    local comp = make_comp({ right = ">>" })
    local val, dynamic = B.side(comp, "right", make_resolver({}))
    eq(val, ">>", "right side works independently")
    is_false(dynamic)
end

-- ====================================================================
-- side() — return value count
-- ====================================================================
print("=== side(): return value semantics ===")

do
    local comp = make_comp({ left = ">>" })
    local results = { B.side(comp, "left", make_resolver({})) }
    eq(#results, 2, "returns exactly 2 values: value, dynamic")
end

do
    local comp = make_comp({ left = function() return ">>" end })
    local val, dynamic = B.side(comp, "left", make_resolver({}))
    eq(type(dynamic), "boolean", "dynamic is always boolean")
end

-- ====================================================================
-- side_style — edge cases
-- ====================================================================
print("=== side_style(): edge cases ===")

do
    local comp = make_comp({ left_style = 0, right_style = 3 })
    eq(B.side_style(comp, "left"), 0, "explicit Inherited for left")
    eq(B.side_style(comp, "right"), 3, "explicit Reverse for right")
end

do
    local comp = make_comp({ left_style = function() return SepStyle.SepFg end })
    local s = B.side_style(comp, "left")
    eq(type(s), "number", "side_style resolves dynamic function to SepFg")
end

do
    local comp = make_comp({ left_style = "" })
    eq(B.side_style(comp, "left"), "", "empty string is a valid side_style")
end

do
    local comp = make_comp({ left_style = false })
    eq(B.side_style(comp, "left"), SepStyle.SepBg, "false is falsy, falls through to default SepBg")
end

-- ====================================================================
-- resolved_side_style() — main_style field variants
-- ====================================================================
print("=== resolved_side_style(): foreground/background fields ===")

do
    local comp = make_comp({ left_style = SepStyle.SepBg })
    local main_style = { foreground = "#aaa", background = "#bbb" }
    local style = B.resolved_side_style(comp, "left", main_style, false)
    eq(style.fg, "#bbb", "SepBg uses background as fg")
    eq(style.bg, "NONE")
end

do
    local comp = make_comp({ left_style = SepStyle.SepFg })
    local main_style = { foreground = "#aaa", background = "#bbb" }
    local style = B.resolved_side_style(comp, "left", main_style, false)
    eq(style.fg, "#aaa", "SepFg uses foreground as fg")
    eq(style.bg, "NONE")
end

do
    local comp = make_comp({ right_style = SepStyle.Reverse })
    local main_style = { foreground = "#aaa", background = "#bbb" }
    local style = B.resolved_side_style(comp, "right", main_style, false)
    eq(style.fg, "#bbb", "Reverse uses background as fg")
    eq(style.bg, "#aaa", "Reverse uses foreground as bg")
end

-- ====================================================================
-- resolved_side_style() — nil fg/bg in main_style
-- ====================================================================
print("=== resolved_side_style(): nil fg/bg in main_style ===")

do
    local comp = make_comp({ left_style = SepStyle.SepBg })
    local main_style = { bg = "#333" }
    local style = B.resolved_side_style(comp, "left", main_style, false)
    eq(style.fg, "#333", "SepBg with nil fg uses bg")
    eq(style.bg, "NONE")
end

do
    local comp = make_comp({ left_style = SepStyle.SepBg })
    local main_style = { fg = "#fff" }
    local style = B.resolved_side_style(comp, "left", main_style, false)
    is_nil(style.fg, "SepBg with nil bg results in nil fg")
    eq(style.bg, "NONE")
end

do
    local comp = make_comp({ right_style = SepStyle.Reverse })
    local main_style = {}
    local style = B.resolved_side_style(comp, "right", main_style, false)
    is_nil(style.fg, "Reverse with empty main_style: fg is nil")
    is_nil(style.bg, "Reverse with empty main_style: bg is nil")
end

do
    local comp = make_comp({ left_style = SepStyle.SepFg })
    local main_style = {}
    local style = B.resolved_side_style(comp, "left", main_style, false)
    is_nil(style.fg, "SepFg with empty main_style: fg is nil")
    eq(style.bg, "NONE")
end

-- ====================================================================
-- resolved_side_style() — no main_style with non-numeric styles
-- ====================================================================
print("=== resolved_side_style(): no main_style with custom styles ===")

do
    local comp = make_comp({ left_style = { fg = "#aaa" } })
    local style = B.resolved_side_style(comp, "left", nil, false)
    eq(style.fg, "#aaa", "custom table works without main_style")
end

do
    local comp = make_comp({ left_style = "MyHL" })
    local style = B.resolved_side_style(comp, "left", nil, false)
    eq(style, "MyHL", "string works without main_style")
end

-- ====================================================================
-- resolved_side_style() — dynamic function edge cases
-- ====================================================================
print("=== resolved_side_style(): dynamic function edge cases ===")

do
    local comp = make_comp({
        left_style = function() return nil end,
    })
    local main_style = { fg = "#fff", bg = "#000" }
    local style, dynamic = B.resolved_side_style(comp, "left", main_style, false)
    is_nil(style, "dynamic returning nil yields nil")
    is_true(dynamic)
end

do
    local comp = make_comp({
        left_style = function() return "MyHL" end,
    })
    local style = B.resolved_side_style(comp, "left", nil, false)
    eq(style, "MyHL", "dynamic returning string passes through")
end

do
    local comp = make_comp({
        left_style = function() return { fg = "#dynamic" } end,
    })
    local style = B.resolved_side_style(comp, "left", nil, false)
    eq(style.fg, "#dynamic", "dynamic returning table works")
end

do
    local comp = make_comp({
        left_style = function() return SepStyle.Inherited end,
    })
    local main_style = { fg = "#fff", bg = "#000" }
    local style, dynamic, inherited = B.resolved_side_style(comp, "left", main_style, false)
    is_nil(style, "dynamic returning Inherited yields nil")
    is_true(dynamic)
    is_true(inherited)
end

do
    local comp = make_comp({
        left_style = function() return 999 end,
    })
    local main_style = { fg = "#fff", bg = "#000" }
    local style, dynamic, inherited = B.resolved_side_style(comp, "left", main_style, false)
    is_nil(style, "dynamic returning unknown enum yields nil")
    is_true(dynamic)
    is_false(inherited)
end

-- ====================================================================
-- resolved_side_style() — theme_aware with different style types
-- ====================================================================
print("=== resolved_side_style(): theme_aware propagation ===")

do
    local comp = make_comp({ left_style = "MyHL" })
    local style = B.resolved_side_style(comp, "left", nil, true)
    eq(style, "MyHL", "string style not modified by theme_aware")
end

do
    local comp = make_comp({ left_style = { fg = "#aaa" } })
    local style = B.resolved_side_style(comp, "left", nil, true)
    eq(style.theme_aware, true, "table style gets theme_aware=true")
end

do
    local comp = make_comp({ left_style = { fg = "#aaa", theme_aware = false } })
    local style = B.resolved_side_style(comp, "left", nil, true)
    eq(style.theme_aware, false, "pre-set theme_aware not overwritten")
end

do
    local comp = make_comp({ left_style = SepStyle.SepBg })
    local main_style = { fg = "#fff", bg = "#000" }
    local style = B.resolved_side_style(comp, "left", main_style, true)
    eq(style.theme_aware, true, "resolved SepBg gets theme_aware")
end

-- ====================================================================
-- resolved_side_style() — return value semantics
-- ====================================================================
print("=== resolved_side_style(): return value semantics ===")

do
    local comp = make_comp({})
    local results = { B.resolved_side_style(comp, "left", nil, false) }
    eq(#results, 3, "returns 3 values: style, dynamic, inherited")
end

do
    local comp = make_comp({ left_style = SepStyle.Inherited })
    local _, dynamic, inherited = B.resolved_side_style(comp, "left", { fg = "#fff", bg = "#000" }, false)
    eq(type(dynamic), "boolean", "dynamic is boolean")
    eq(type(inherited), "boolean", "inherited is boolean")
end

-- ====================================================================
-- Summary
-- ====================================================================
local ok = helper.summary()
os.exit(ok and 0 or 1)
