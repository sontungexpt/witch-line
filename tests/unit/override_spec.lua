--- Unit tests for witch-line.core.override
--- Covers: type validation, merge behavior, accept_returned_style, theme_aware.

local a = require("tests.helpers.assert")

-- Load override (it returns a function directly)
local apply_override = require("witch-line.core.override")

-- ============================================================
print("=== override: basic field override ===")

do
    local comp = {
        id = "c1", ___builtin = true,
        padding = 1,
        update = function() return "v" end,
    }
    local result = apply_override(comp, { padding = 2 })
    a.eq(result.padding, 2, "padding overridden")
end

-- ============================================================
print("=== override: style override disables accept_returned_style ===")

do
    local comp = { id = "c1", ___builtin = true }
    local result = apply_override(comp, { style = { fg = "#fff" } })
    a.is_false(result.___accept_returned_style, "accept_returned_style = false")
end

-- ============================================================
print("=== override: style override disables theme_aware ===")

do
    local comp = { id = "c1", ___builtin = true, theme_aware = true }
    local result = apply_override(comp, { style = { fg = "#fff" } })
    a.is_false(result.theme_aware, "theme_aware = false")
end

-- ============================================================
print("=== override: left_style disables theme_aware ===")

do
    local comp = { id = "c1", ___builtin = true, theme_aware = true }
    local result = apply_override(comp, { left_style = 2 })
    a.is_false(result.theme_aware, "theme_aware = false")
end

-- ============================================================
print("=== override: right_style disables theme_aware ===")

do
    local comp = { id = "c1", ___builtin = true, theme_aware = true }
    local result = apply_override(comp, { right_style = 1 })
    a.is_false(result.theme_aware, "theme_aware = false")
end

-- ============================================================
print("=== override: non-table override returns comp unchanged ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, "not a table")
    a.eq(result, comp, "comp returned as-is")
end

-- ============================================================
print("=== override: invalid type for field ignored ===")

do
    local comp = { id = "c1", padding = 1 }
    local result = apply_override(comp, { padding = "invalid" })
    a.eq(result.padding, 1, "invalid type ignored, original preserved")
end

-- ============================================================
print("=== override: function type accepted for style ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { style = function() return {} end })
    a.is_type(result.style, "function", "function accepted for style")
end

-- ============================================================
print("=== override: deep merge for table values ===")

do
    local comp = { id = "c1", config = { a = 1, b = 2 } }
    local result = apply_override(comp, { config = { b = 99, c = 3 } })
    a.eq(result.config.a, 1, "existing key preserved")
    a.eq(result.config.b, 99, "existing key overridden")
    a.eq(result.config.c, 3, "new key added")
end

-- ============================================================
print("=== override: list replacement ===")

do
    local comp = { id = "c1", config = { "BufEnter", "BufLeave" } }
    local result = apply_override(comp, { config = { "CursorMoved" } })
    -- vim.islist returns true for both, so list replacement applies
    a.is_true(vim.islist(result.config), "result is a list")
    a.eq(#result.config, 1, "list replaced not merged")
    a.eq(result.config[1], "CursorMoved")
end

-- ============================================================
print("=== override: unknown field ignored ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { unknown_field = "value" })
    a.is_nil(result.unknown_field, "unknown field not set")
end

-- ============================================================
print("=== override: left/right as string ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { left = ">>", right = "<<" })
    a.eq(result.left, ">>", "left string accepted")
    a.eq(result.right, "<<", "right string accepted")
end

-- ============================================================
print("=== override: left/right reject non-string ===")

do
    local comp = { id = "c1", left = ">>" }
    local result = apply_override(comp, { left = 123 })
    a.eq(result.left, ">>", "non-string left rejected")
end

-- ============================================================
print("=== override: padding number accepted ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { padding = 3 })
    a.eq(result.padding, 3)
end

-- ============================================================
print("=== override: padding table accepted ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { padding = { left = 1, right = 2 } })
    a.is_type(result.padding, "table", "table padding accepted")
end

-- ============================================================
print("=== override: empty override ===")

do
    local comp = { id = "c1", style = { fg = "#fff" } }
    local result = apply_override(comp, {})
    a.eq(result.style.fg, "#fff", "empty override preserves original")
end

-- ============================================================
print("=== override: nil override ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, nil)
    a.eq(result, comp, "nil override returns comp")
end

-- ============================================================
-- Summary
-- ============================================================
local ok = a.summary()
os.exit(ok and 0 or 1)
