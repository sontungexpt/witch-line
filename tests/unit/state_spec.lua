local helper = require("tests.helper")
local eq = helper.eq
local is_true = helper.is_true
local is_false = helper.is_false
local not_nil = helper.not_nil

-- ====================================================================
-- Mock infrastructure
-- ====================================================================
local mock_calls = {}

local function reset_mocks()
    mock_calls = {
        pre_update = 0,
        post_update = 0,
        evaluate_returns = {},
        hidden_returns = {},
        theme_aware_returns = {},
        style_returns = {},
        side_style_returns = {},
        side_returns = {},
    }
end

-- Mock CompAPI (resolver)
package.loaded["witch-line.core.comp.resolver"] = {
    pre_update = function(_comp, _session)
        mock_calls.pre_update = mock_calls.pre_update + 1
    end,
    hidden = function(_comp, _session)
        return table.remove(mock_calls.hidden_returns, 1) or false
    end,
    evaluate = function(_comp, _session)
        local r = table.remove(mock_calls.evaluate_returns, 1)
        if r then return r.value, r.dynamic_style end
        return "", nil
    end,
    theme_aware = function(_comp, _session)
        return table.remove(mock_calls.theme_aware_returns, 1) or false
    end,
    style = function(_comp, _resolver_fn, _dynamic_style, _theme_aware_enabled)
        local r = table.remove(mock_calls.style_returns, 1)
        if r then return r.style, r.dynamic end
        return nil, false
    end,
    side_style = function(_comp, _side, _main_style, _theme_aware_enabled, _session)
        local r = table.remove(mock_calls.side_style_returns, 1)
        if r then return r.style, r.dynamic, r.inherited, r.is_sep_style end
        return nil, false, false, false
    end,
    side = function(_comp, _side, _resolver_fn, _session)
        return table.remove(mock_calls.side_returns, 1) or nil
    end,
    post_update = function(_comp, _session)
        mock_calls.post_update = mock_calls.post_update + 1
    end,
}

-- Mock Proxy
package.loaded["witch-line.core.comp.proxy"] = {
    bind = function(parent, _session) return parent end,
}

-- Mock Registry
package.loaded["witch-line.core.registry"] = {
    ManagedComps = {},
}

-- Mock click manager
package.loaded["witch-line.event.click"] = {
    register = function(comp) return "click_" .. comp.id end,
}

-- ====================================================================
-- Fresh module loader
-- ====================================================================
local State

local function fresh()
    reset_mocks()
    package.loaded["witch-line.core.state"] = nil
    State = require("witch-line.core.state")
    return State
end

-- ====================================================================
-- Helper: pretty-print a CompState
-- ====================================================================
local function pp_state(s)
    if not s then return "nil" end
    local parts = {}
    parts[#parts+1] = "hidden=" .. tostring(s.hidden)
    parts[#parts+1] = "value=" .. tostring(s.value)
    parts[#parts+1] = "theme_aware=" .. tostring(s.theme_aware_enabled)
    parts[#parts+1] = "click=" .. tostring(s.click_handler)
    parts[#parts+1] = "left=" .. tostring(s.left)
    parts[#parts+1] = "right=" .. tostring(s.right)
    if s.style then
        parts[#parts+1] = "style={fg=" .. tostring(s.style.style and s.style.style.fg)
            .. ",bold=" .. tostring(s.style.style and s.style.style.bold)
            .. ",dirty=" .. tostring(s.style.dirty) .. "}"
    end
    if s.left_style then
        parts[#parts+1] = "left_style={fg="
            .. tostring(s.left_style.style and s.left_style.style.fg)
            .. ",dirty=" .. tostring(s.left_style.dirty) .. "}"
    end
    if s.right_style then
        parts[#parts+1] = "right_style={fg="
            .. tostring(s.right_style.style and s.right_style.style.fg)
            .. ",dirty=" .. tostring(s.right_style.dirty) .. "}"
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local TOTAL, PASSED, FAILED = 0, 0, 0

local function test(name, fn)
    TOTAL = TOTAL + 1
    local ok, err = pcall(fn)
    if ok then
        PASSED = PASSED + 1
    else
        FAILED = FAILED + 1
        print("  FAIL  " .. name .. ": " .. tostring(err))
    end
end

-- ====================================================================
-- Tests
-- ====================================================================

test("hidden component returns true", function()
    fresh()
    mock_calls.hidden_returns = { true }
    local hidden = State.update_comp({ id = "c1", renderable = true }, {})
    is_true(hidden, "should be hidden")
    local s = State.get_states(nil)["c1"]
    print("    [c1] " .. pp_state(s))
end)

test("visible component with value", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "hello", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = { fg = "#ff0000" }, dynamic = false } }
    local hidden = State.update_comp({ id = "c2", renderable = true }, {})
    is_false(hidden, "should not be hidden")
    local s = State.get_states(nil)["c2"]
    print("    [c2] " .. pp_state(s))
end)

test("empty value hides renderable", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    local hidden = State.update_comp({ id = "c3", renderable = true }, {})
    is_true(hidden, "empty value should hide")
    local s = State.get_states(nil)["c3"]
    print("    [c3] " .. pp_state(s))
end)

test("style resolved and stored", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "styled", dynamic_style = { fg = "#ff0000" } } }
    mock_calls.theme_aware_returns = { true }
    mock_calls.style_returns = { { style = { fg = "#ff0000", bold = true }, dynamic = false } }
    State.update_comp({ id = "c4", renderable = true }, {})
    local s = State.get_states(nil)["c4"]
    print("    [c4] " .. pp_state(s))
end)

test("dynamic style stays dirty", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "dyn", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = { fg = "#111" }, dynamic = true } }
    State.update_comp({ id = "c5", renderable = true }, {})
    local s = State.get_states(nil)["c5"]
    print("    [c5] after first update (dynamic=true): " .. pp_state(s))
    is_true(s.style.dirty, "dynamic style dirty after first update")

    -- Second update: same style, still dynamic
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "dyn2", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = { fg = "#111" }, dynamic = true } }
    State.update_comp({ id = "c5", renderable = true }, {})
    s = State.get_states(nil)["c5"]
    print("    [c5] after second update (same dynamic): " .. pp_state(s))
end)

test("same static style clears dirty", function()
    fresh()
    -- First: dynamic
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "v", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = { fg = "#111" }, dynamic = true } }
    State.update_comp({ id = "c6", renderable = true }, {})
    local s = State.get_states(nil)["c6"]
    print("    [c6] after dynamic update: " .. pp_state(s))

    -- Second: same style but static
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "v2", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = { fg = "#111" }, dynamic = false } }
    State.update_comp({ id = "c6", renderable = true }, {})
    s = State.get_states(nil)["c6"]
    print("    [c6] after static update (same style): " .. pp_state(s))
    is_false(s.style.dirty, "same static style clears dirty")
end)

test("side separators stored", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "sep", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = { fg = "#fff" }, dynamic = false } }
    mock_calls.side_returns = { "│", "│" }
    mock_calls.side_style_returns = {
        { style = { fg = "#aaa" }, dynamic = false, inherited = false, is_sep_style = true },
        { style = { fg = "#aaa" }, dynamic = false, inherited = false, is_sep_style = true },
    }
    State.update_comp({ id = "c7", renderable = true }, {})
    local s = State.get_states(nil)["c7"]
    print("    [c7] " .. pp_state(s))
    eq(s.left, "│", "left sep")
    eq(s.right, "│", "right sep")
end)

test("click handler format", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "click", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = nil, dynamic = false } }
    State.update_comp({ id = "c8", renderable = true, on_click = function() end }, {})
    local s = State.get_states(nil)["c8"]
    print("    [c8] " .. pp_state(s))
end)

test("double update reuses same state table", function()
    fresh()
    mock_calls.hidden_returns = { false, false }
    mock_calls.evaluate_returns = {
        { value = "first", dynamic_style = nil },
        { value = "second", dynamic_style = { fg = "#000" } },
    }
    mock_calls.theme_aware_returns = { false, false }
    mock_calls.style_returns = {
        { style = { fg = "#aaa" }, dynamic = false },
        { style = { fg = "#000" }, dynamic = false },
    }
    local comp = { id = "c9", renderable = true }
    State.update_comp(comp, {})
    local s1 = State.get_states(nil)["c9"]
    print("    [c9] after first:  " .. pp_state(s1))

    State.update_comp(comp, {})
    local s2 = State.get_states(nil)["c9"]
    print("    [c9] after second: " .. pp_state(s2))

    eq(s1, s2, "same table reference")
end)

test("non-renderable skips style", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "nope", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    State.update_comp({ id = "c10", renderable = false }, {})
    local s = State.get_states(nil)["c10"]
    print("    [c10] " .. pp_state(s))
end)

test("window-local vs global", function()
    fresh()
    mock_calls.hidden_returns = { false }
    mock_calls.evaluate_returns = { { value = "g", dynamic_style = nil } }
    mock_calls.theme_aware_returns = { false }
    mock_calls.style_returns = { { style = nil, dynamic = false } }
    State.update_comp({ id = "c11", renderable = true }, {})
    local g = State.get_states(nil)["c11"]
    local w = State.get_states(42)["c11"]
    print("    [c11] global: " .. pp_state(g))
    print("    [c11] win42:  " .. pp_state(w))
end)

-- ====================================================================
print(string.format("%d/%d passed, %d failed", PASSED, TOTAL, FAILED))
