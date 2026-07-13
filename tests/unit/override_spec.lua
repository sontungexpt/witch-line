--- Unit tests for witch-line.core.comp.override
--- Covers: type validation, merge behavior, accept_returned_style, theme_aware.

local a = require("tests.helpers.assert")

-- Load override (it returns a function directly)
local apply_override = require("witch-line.core.comp.override")

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
print("=== override: config must be table, string rejected ===")

do
    local comp = { id = "c1", config = { a = 1 } }
    local result = apply_override(comp, { config = "bad" })
    a.eq(result.config.a, 1, "string config rejected, original preserved")
end

-- ============================================================
print("=== override: timing number accepted ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { timing = 5000 })
    a.eq(result.timing, 5000, "number timing accepted")
end

-- ============================================================
print("=== override: timing boolean accepted ===")

do
    local comp = { id = "c1", timing = 1000 }
    local result = apply_override(comp, { timing = false })
    a.is_false(result.timing, "boolean timing accepted")
end

-- ============================================================
print("=== override: timing string rejected ===")

do
    local comp = { id = "c1", timing = 1000 }
    local result = apply_override(comp, { timing = "fast" })
    a.eq(result.timing, 1000, "string timing rejected")
end

-- ============================================================
print("=== override: lazy boolean accepted ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { lazy = true })
    a.is_true(result.lazy)
end

-- ============================================================
print("=== override: lazy number rejected ===")

do
    local comp = { id = "c1", lazy = false }
    local result = apply_override(comp, { lazy = 1 })
    a.is_false(result.lazy, "number lazy rejected")
end

-- ============================================================
print("=== override: hidden function accepted ===")

do
    local comp = { id = "c1" }
    local fn = function() return true end
    local result = apply_override(comp, { hidden = fn })
    a.eq(result.hidden, fn, "function hidden accepted")
end

-- ============================================================
print("=== override: hidden string rejected ===")

do
    local comp = { id = "c1", hidden = nil }
    local result = apply_override(comp, { hidden = "yes" })
    a.is_nil(result.hidden, "string hidden rejected")
end

-- ============================================================
print("=== override: flexible number accepted ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { flexible = 2 })
    a.eq(result.flexible, 2)
end

-- ============================================================
print("=== override: flexible string rejected ===")

do
    local comp = { id = "c1", flexible = 1 }
    local result = apply_override(comp, { flexible = "wide" })
    a.eq(result.flexible, 1, "string flexible rejected")
end

-- ============================================================
print("=== override: theme_aware boolean accepted ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { theme_aware = true })
    a.is_true(result.theme_aware)
end

-- ============================================================
print("=== override: theme_aware function accepted ===")

do
    local comp = { id = "c1" }
    local fn = function() return true end
    local result = apply_override(comp, { theme_aware = fn })
    a.eq(result.theme_aware, fn)
end

-- ============================================================
print("=== override: theme_aware string rejected ===")

do
    local comp = { id = "c1", theme_aware = true }
    local result = apply_override(comp, { theme_aware = "yes" })
    a.is_true(result.theme_aware, "string theme_aware rejected")
end

-- ============================================================
print("=== override: left_style table accepted ===")

do
    local comp = { id = "c1", theme_aware = true }
    local result = apply_override(comp, { left_style = { fg = "#aaa" } })
    a.is_type(result.left_style, "table")
    a.is_false(result.theme_aware, "theme_aware disabled by left_style")
end

-- ============================================================
print("=== override: left_style function accepted ===")

do
    local comp = { id = "c1", theme_aware = true }
    local fn = function() return {} end
    local result = apply_override(comp, { left_style = fn })
    a.eq(result.left_style, fn)
end

-- ============================================================
print("=== override: right_style table accepted ===")

do
    local comp = { id = "c1", theme_aware = true }
    local result = apply_override(comp, { right_style = { bg = "#000" } })
    a.is_type(result.right_style, "table")
    a.is_false(result.theme_aware, "theme_aware disabled by right_style")
end

-- ============================================================
print("=== override: style as table accepted ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { style = { fg = "#fff", bold = true } })
    a.is_type(result.style, "table")
    a.eq(result.style.fg, "#fff")
    a.is_true(result.style.bold)
end

-- ============================================================
print("=== override: config deep merge nested tables ===")

do
    local comp = { id = "c1", config = { icons = { ok = "yes", fail = "no" } } }
    local result = apply_override(comp, { config = { icons = { fail = "FAIL", warn = "?" } } })
    a.eq(result.config.icons.ok, "yes", "nested existing key preserved")
    a.eq(result.config.icons.fail, "FAIL", "nested key overridden")
    a.eq(result.config.icons.warn, "?", "nested new key added")
end

-- ============================================================
print("=== override: config list replacement inside deep merge ===")

do
    local comp = { id = "c1", config = { modes = { "normal", "insert" } } }
    local result = apply_override(comp, { config = { modes = { "visual" } } })
    a.is_true(vim.islist(result.config.modes), "nested list replaced")
    a.eq(#result.config.modes, 1)
    a.eq(result.config.modes[1], "visual")
end

-- ============================================================
print("=== override: config merge preserves unrelated keys ===")

do
    local comp = { id = "c1", config = { a = 1, b = 2, c = 3 } }
    local result = apply_override(comp, { config = { b = 99 } })
    a.eq(result.config.a, 1, "a preserved")
    a.eq(result.config.b, 99, "b overridden")
    a.eq(result.config.c, 3, "c preserved")
end

-- ============================================================
print("=== override: multiple fields at once ===")

do
    local comp = { id = "c1", ___builtin = true, theme_aware = true, padding = 1 }
    local result = apply_override(comp, {
        style = { fg = "#fff" },
        padding = 5,
        left = "[",
        right = "]",
    })
    a.is_false(result.___accept_returned_style, "style disables accept_returned_style")
    a.is_false(result.theme_aware, "style disables theme_aware")
    a.eq(result.padding, 5, "padding overridden")
    a.eq(result.left, "[", "left set")
    a.eq(result.right, "]", "right set")
end

-- ============================================================
print("=== override: style override without theme_aware on comp ===")

do
    local comp = { id = "c1" }
    local result = apply_override(comp, { style = { fg = "#fff" } })
    a.is_false(result.___accept_returned_style, "accept_returned_style set")
end

-- ============================================================
print("=== override: config nil value in override ===")

do
    local comp = { id = "c1", config = { a = 1 } }
    local result = apply_override(comp, { config = { a = nil } })
    a.eq(result.config.a, 1, "nil value in override preserves original")
end

-- ============================================================
print("=== override: padding nil rejected ===")

do
    local comp = { id = "c1", padding = 2 }
    local result = apply_override(comp, { padding = nil })
    a.eq(result.padding, 2, "nil padding ignored, original preserved")
end

-- ============================================================
print("=== override: comp mutation returns same reference ===")

do
    local comp = { id = "c1", padding = 1 }
    local result = apply_override(comp, { padding = 9 })
    a.eq(result, comp, "returns same table reference")
end

-- ============================================================
print("=== override: merge_value both empty tables ===")

do
    local comp = { id = "c1", config = {} }
    local result = apply_override(comp, { config = {} })
    a.is_true(vim.islist(result.config) or next(result.config) == nil, "both empty")
end

-- ============================================================
print("=== override: merge_value to empty from non-empty ===")

do
    local comp = { id = "c1", config = {} }
    local result = apply_override(comp, { config = { x = 1 } })
    a.eq(result.config.x, 1, "empty to non-empty merges")
end

-- ============================================================
print("=== override: merge_value to non-empty from empty ===")

do
    local comp = { id = "c1", config = { x = 1 } }
    local result = apply_override(comp, { config = {} })
    a.eq(result.config.x, 1, "non-empty to empty preserved")
end

-- ============================================================
-- Summary
-- ============================================================
local ok = a.summary()
os.exit(ok and 0 or 1)
