--- Tests for comp_state module.
--- Tests verify state transitions through update_comp().
---
--- Run: nvim --headless --cmd "set rtp+=." -c "luafile tests/comp_state_spec.lua" -c "qa!"
---   or: bash tests/run.sh

local helper = require("tests.helper")
local eq = helper.eq
local neq = helper.neq
local is_true = helper.is_true
local is_false = helper.is_false
local not_nil = helper.not_nil
local summary = helper.summary
local reset = helper.reset

----------------------------------------------------------------------
-- Mock infrastructure
----------------------------------------------------------------------

local last_mock_config = {}

local function configure_mocks(config)
    last_mock_config = config
end

-- Mock CompAPI (resolver)
package.loaded["witch-line.core.comp.resolver"] = {
    pre_update = function(_comp, _session)
        if last_mock_config.pre_update then
            last_mock_config.pre_update(_comp, _session)
        end
    end,
    hidden = function(_comp, _session)
        if last_mock_config.hidden then
            return last_mock_config.hidden(_comp, _session)
        end
        return false
    end,
    evaluate = function(_comp, _session)
        if last_mock_config.evaluate then
            return last_mock_config.evaluate(_comp, _session)
        end
        return "", nil
    end,
    style = function(_comp, _resolver_fn, _dynamic_style, _theme_aware_enabled)
        if last_mock_config.style then
            return last_mock_config.style(_comp, _resolver_fn, _dynamic_style, _theme_aware_enabled)
        end
        return nil, false
    end,
    side_style = function(_comp, _side, _main_style, _theme_aware_enabled, _session)
        if last_mock_config.side_style then
            return last_mock_config.side_style(_comp, _side, _main_style, _theme_aware_enabled, _session)
        end
        return nil, false, false, false
    end,
    side = function(_comp, _side, _resolver_fn, _session)
        if last_mock_config.side then
            return last_mock_config.side(_comp, _side, _resolver_fn, _session)
        end
        return nil
    end,
    theme_aware = function(_comp, _session)
        if last_mock_config.theme_aware then
            return last_mock_config.theme_aware(_comp, _session)
        end
        return false
    end,
    post_update = function(_comp, _session)
        if last_mock_config.post_update then
            last_mock_config.post_update(_comp, _session)
        end
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
    register = function(comp) return comp.id end,
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function create_component(overrides)
    local comp = {
        id = "test_comp",
        renderable = true,
    }
    if overrides then
        for k, v in pairs(overrides) do
            comp[k] = v
        end
    end
    return comp
end

local function create_session()
    return {}
end

---@param s CompState|nil
---@return string
local function dump_state(s)
    if s == nil then
        return "nil"
    end

    local parts = {}

    if s.hidden ~= nil then
        parts[#parts + 1] = "hidden=" .. tostring(s.hidden)
    end
    if s.value ~= nil then
        parts[#parts + 1] = 'value="' .. s.value .. '"'
    end
    if s.theme_aware_enabled ~= nil then
        parts[#parts + 1] = "theme_aware=" .. tostring(s.theme_aware_enabled)
    end
    if s.click_handler ~= nil then
        parts[#parts + 1] = 'click_handler="' .. s.click_handler .. '"'
    end
    if s.left ~= nil then
        parts[#parts + 1] = 'left="' .. s.left .. '"'
    end
    if s.right ~= nil then
        parts[#parts + 1] = 'right="' .. s.right .. '"'
    end

    if s.style then
        local style_inner = s.style.style
        local style_str = style_inner and vim.inspect(style_inner, { compact = true }) or "nil"
        local dirty_str = tostring(s.style.dirty)
        parts[#parts + 1] = "style={style=" .. style_str .. ",dirty=" .. dirty_str .. "}"
    end

    if s.left_style then
        local ls = s.left_style.style
        local ls_str = ls and vim.inspect(ls, { compact = true }) or "nil"
        local ld_str = tostring(s.left_style.dirty)
        parts[#parts + 1] = "left_style={style=" .. ls_str .. ",dirty=" .. ld_str .. "}"
    end

    if s.right_style then
        local rs = s.right_style.style
        local rs_str = rs and vim.inspect(rs, { compact = true }) or "nil"
        local rd_str = tostring(s.right_style.dirty)
        parts[#parts + 1] = "right_style={style=" .. rs_str .. ",dirty=" .. rd_str .. "}"
    end

    if #parts == 0 then
        return "{ }"
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function print_header(title)
    print("")
    print(string.rep("=", 60))
    print("TEST: " .. title)
    print(string.rep("=", 60))
end

local function print_section(label, content)
    print("")
    print(label .. ":")
    print("  " .. content:gsub("\n", "\n  "))
end

----------------------------------------------------------------------
-- Test runner
----------------------------------------------------------------------

local State
local function fresh()
    reset()
    configure_mocks({})
    package.loaded["witch-line.core.state"] = nil
    State = require("witch-line.core.state")
end

local TOTAL, PASSED, FAILED = 0, 0, 0

local function test(name, fn)
    fresh()
    TOTAL = TOTAL + 1
    local ok, err = pcall(fn)
    if ok then
        PASSED = PASSED + 1
    else
        FAILED = FAILED + 1
        print("  FAIL: " .. tostring(err))
    end
end

----------------------------------------------------------------------
-- TEST 1: Hidden component
----------------------------------------------------------------------
test("1. hidden component", function()
    print_header("1. hidden component")

    local comp = create_component({ id = "hidden_comp" })
    local session = create_session()

    configure_mocks({
        hidden = function()
            return true
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Session", vim.inspect(session, { compact = true }))
    print_section("Mock results", "hidden=true")

    local before = State.get_states(nil)["hidden_comp"]
    print_section("Before state", dump_state(before))

    local hidden = State.update_comp(comp, session)
    local after = State.get_states(nil)["hidden_comp"]

    print_section("After state", dump_state(after))
    print_section("Return value", "hidden=" .. tostring(hidden))
    print_section("Reason",
        "- Component is hidden (CompAPI.hidden returns true).\n"
        .. "- State.hidden is set to true.\n"
        .. "- No value or style is computed (early return).")

    is_true(hidden, "update_comp returns true")
    is_true(after.hidden, "state.hidden is true")
end)

----------------------------------------------------------------------
-- TEST 2: Renderable component with normal value
----------------------------------------------------------------------
test("2. renderable component with normal value", function()
    print_header("2. renderable component with normal value")

    local comp = create_component({ id = "text_comp" })
    local session = create_session()

    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "hello", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "red" }, false
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Session", vim.inspect(session, { compact = true }))
    print_section("Mock results",
        "hidden=false\n"
        .. 'evaluate="hello", nil\n'
        .. 'style={fg="red"}, dynamic=false\n'
        .. "theme_aware=false")

    local before = State.get_states(nil)["text_comp"]
    print_section("Before state", dump_state(before))

    local hidden = State.update_comp(comp, session)
    local after = State.get_states(nil)["text_comp"]

    print_section("After state", dump_state(after))
    print_section("Return value", "hidden=" .. tostring(hidden))
    print_section("Reason",
        "- Component is visible (hidden=false).\n"
        .. '- Value "hello" is non-empty, so state.value is set.\n'
        .. "- Style is created for the first time (dirty=true).\n"
        .. "- No separators (side returns nil).")

    is_false(hidden, "update_comp returns false")
    eq(after.value, "hello", "value stored")
    eq(after.hidden, false, "hidden is false")
    eq(after.theme_aware_enabled, false, "theme_aware false")
    eq(after.style.style.fg, "red", "style fg stored")
    is_true(after.style.dirty, "first style is always dirty")
end)

----------------------------------------------------------------------
-- TEST 3: Style does not change on second update
----------------------------------------------------------------------
test("3. style unchanged on second update clears dirty", function()
    print_header("3. style unchanged on second update clears dirty")

    local comp = create_component({ id = "stable_comp" })
    local session = create_session()

    -- First update
    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "hello", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "red" }, false
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Mock results (update 1)", 'hidden=false\nevaluate="hello"\nstyle={fg="red"}, dynamic=false')

    State.update_comp(comp, session)
    local after1 = State.get_states(nil)["stable_comp"]

    print_section("After update 1", dump_state(after1))
    print_section("dirty", tostring(after1.style.dirty))
    is_true(after1.style.dirty, "first update: dirty=true")

    -- Second update: same style
    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "world", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "red" }, false
        end,
    })

    print_section("\nMock results (update 2)", 'hidden=false\nevaluate="world"\nstyle={fg="red"}, dynamic=false')

    State.update_comp(comp, session)
    local after2 = State.get_states(nil)["stable_comp"]

    print_section("After update 2", dump_state(after2))
    print_section("Reason",
        "- Style object is the same reference ({fg=\"red\"}).\n"
        .. "- hl_state.style == style is true.\n"
        .. "- dirty is cleared to nil (no re-render needed).")

    eq(after1, after2, "same table reference (mutated in place)")
    eq(after2.style.dirty, nil, "dirty cleared when style unchanged")
end)

----------------------------------------------------------------------
-- TEST 4: Dynamic style update
----------------------------------------------------------------------
test("4. dynamic style update", function()
    print_header("4. dynamic style update")

    local comp = create_component({ id = "dyn_comp" })
    local session = create_session()

    -- First update: static style
    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "v", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "red" }, false
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Mock results (update 1)", 'hidden=false\nevaluate="v"\nstyle={fg="red"}, dynamic=false')

    State.update_comp(comp, session)
    local after1 = State.get_states(nil)["dyn_comp"]

    print_section("After update 1", dump_state(after1))

    -- Second update: different style, dynamic
    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "v2", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "blue" }, true
        end,
    })

    print_section("\nMock results (update 2)", 'hidden=false\nevaluate="v2"\nstyle={fg="blue"}, dynamic=true')

    State.update_comp(comp, session)
    local after2 = State.get_states(nil)["dyn_comp"]

    print_section("After update 2", dump_state(after2))
    print_section("Reason",
        "- Style changed from {fg=\"red\"} to {fg=\"blue\"}.\n"
        .. "- dynamic=true, so dirty is set to true.\n"
        .. "- Renderer must re-apply this highlight.")

    eq(after2.style.style.fg, "blue", "style updated to blue")
    is_true(after2.style.dirty, "dirty is true (dynamic)")
end)

----------------------------------------------------------------------
-- TEST 5: Component with left separator
----------------------------------------------------------------------
test("5. component with left separator", function()
    print_header("5. component with left separator")

    local comp = create_component({ id = "separator_comp" })
    local session = create_session()

    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "abc", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "white" }, false
        end,
        side = function(_comp, side)
            if side == "left" then return "|" end
            return nil
        end,
        side_style = function(_comp, side)
            if side == "left" then
                return { fg = "green" }, true, false, false
            end
            return nil, false, false, false
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Session", vim.inspect(session, { compact = true }))
    print_section("Mock results",
        "hidden=false\n"
        .. 'evaluate="abc"\n'
        .. 'style={fg="white"}, dynamic=false\n'
        .. 'side("left")="|"\n'
        .. 'side_style("left")={fg="green"}, dynamic=true, inherited=false')

    local before = State.get_states(nil)["separator_comp"]
    print_section("Before state", dump_state(before))

    local hidden = State.update_comp(comp, session)
    local after = State.get_states(nil)["separator_comp"]

    print_section("After state", dump_state(after))
    print_section("Reason",
        '- Component is visible, value "abc" stored.\n'
        .. '- Left separator "|" stored.\n'
        .. "- Left style created first time (dirty=true).")

    is_false(hidden, "not hidden")
    eq(after.value, "abc", "value stored")
    eq(after.left, "|", "left separator stored")
    eq(after.left_style.style.fg, "green", "left style fg stored")
    is_true(after.left_style.dirty, "left style is dirty")
end)

----------------------------------------------------------------------
-- TEST 6: Component with right separator
----------------------------------------------------------------------
test("6. component with right separator", function()
    print_header("6. component with right separator")

    local comp = create_component({ id = "right_sep_comp" })
    local session = create_session()

    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "xyz", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "white" }, false
        end,
        side = function(_comp, side)
            if side == "right" then return "/" end
            return nil
        end,
        side_style = function(_comp, side)
            if side == "right" then
                return { fg = "blue" }, false, false, true
            end
            return nil, false, false, false
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Mock results",
        "hidden=false\n"
        .. 'evaluate="xyz"\n'
        .. 'side("right")="/"\n'
        .. 'side_style("right")={fg="blue"}, dynamic=false, inherited=false, is_sep_style=true')

    local before = State.get_states(nil)["right_sep_comp"]
    print_section("Before state", dump_state(before))

    local hidden = State.update_comp(comp, session)
    local after = State.get_states(nil)["right_sep_comp"]

    print_section("After state", dump_state(after))
    print_section("Reason",
        '- Right separator "/" stored.\n'
        .. "- Right style created first time (dirty=true).\n"
        .. "- is_sep_style=true but first creation always dirty.")

    is_false(hidden, "not hidden")
    eq(after.right, "/", "right separator stored")
    eq(after.right_style.style.fg, "blue", "right style fg stored")
    is_true(after.right_style.dirty, "right style dirty on first creation")
end)

----------------------------------------------------------------------
-- TEST 7: Component with click handler
----------------------------------------------------------------------
test("7. component with click handler", function()
    print_header("7. component with click handler")

    local comp = create_component({ id = "click_comp", on_click = true })
    local session = create_session()

    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "btn", nil end,
        theme_aware = function() return false end,
        style = function()
            return nil, false
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Mock results", 'hidden=false\nevaluate="btn"\nstyle=nil')

    local before = State.get_states(nil)["click_comp"]
    print_section("Before state", dump_state(before))

    local hidden = State.update_comp(comp, session)
    local after = State.get_states(nil)["click_comp"]

    print_section("After state", dump_state(after))
    print_section("Reason",
        "- Component is visible.\n"
        .. "- on_click is truthy, so click_manager.register is called.\n"
        .. "- click_handler is formatted as \"%@v:lua.<id>@\".")

    is_false(hidden, "not hidden")
    eq(after.click_handler, "%@v:lua.click_comp@", "click_handler format")
end)

----------------------------------------------------------------------
-- TEST 8: Component returns empty value
----------------------------------------------------------------------
test("8. component returns empty value", function()
    print_header("8. component returns empty value")

    local comp = create_component({ id = "empty_comp" })
    local session = create_session()

    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "", nil end,
        theme_aware = function() return false end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Mock results", "hidden=false\nevaluate=\"\"")

    local before = State.get_states(nil)["empty_comp"]
    print_section("Before state", dump_state(before))

    local hidden = State.update_comp(comp, session)
    local after = State.get_states(nil)["empty_comp"]

    print_section("After state", dump_state(after))
    print_section("Return value", "hidden=" .. tostring(hidden))
    print_section("Reason",
        '- CompAPI.hidden returned false, but value="" is empty.\n'
        .. "- Empty value causes hidden=true (same as being hidden).\n"
        .. "- No style or separator is computed.")

    is_true(hidden, "empty value hides component")
    is_true(after.hidden, "state.hidden is true")
end)

----------------------------------------------------------------------
-- TEST 9: Window state isolation
----------------------------------------------------------------------
test("9. window state isolation", function()
    print_header("9. window state isolation")

    local comp = create_component({ id = "isolated_comp" })
    local session = create_session()

    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "val", nil end,
        theme_aware = function() return false end,
        style = function()
            return { fg = "red" }, false
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Mock results", 'hidden=false\nevaluate="val"\nstyle={fg="red"}')

    -- Update in window 1
    print_section("Action", "State.update_comp(comp, {})  -- no winid")
    State.update_comp(comp, session)

    local global = State.get_states(nil)
    local win1 = State.get_states(1)
    local win2 = State.get_states(2)

    print_section("GlobalStates[\"isolated_comp\"]", dump_state(global["isolated_comp"]))
    print_section("WindowStates[1][\"isolated_comp\"]", dump_state(win1["isolated_comp"]))
    print_section("WindowStates[2][\"isolated_comp\"]", dump_state(win2["isolated_comp"]))
    print_section("Reason",
        "- Global state is set directly.\n"
        .. "- Window 1 and Window 2 have separate state tables.\n"
        .. "- Window fallback reads from GlobalStates via __index.\n"
        .. "- But writes go to the window-specific table.")

    not_nil(global["isolated_comp"], "global state exists")
    not_nil(win1["isolated_comp"], "window 1 has state")
    not_nil(win2["isolated_comp"], "window 2 has state")
    neq(win1, win2, "window 1 and window 2 are different tables")
end)

----------------------------------------------------------------------
-- TEST 10: Global state
----------------------------------------------------------------------
test("10. global state", function()
    print_header("10. global state")

    local comp = create_component({ id = "global_comp" })
    local session = create_session()

    configure_mocks({
        hidden = function() return false end,
        evaluate = function() return "gval", nil end,
        theme_aware = function() return true end,
        style = function()
            return { fg = "#aaa", bold = true }, true
        end,
    })

    print_section("Component", vim.inspect(comp, { compact = true }))
    print_section("Mock results",
        "hidden=false\n"
        .. 'evaluate="gval"\n'
        .. "theme_aware=true\n"
        .. 'style={fg="#aaa", bold=true}, dynamic=true')

    local before = State.get_states(nil)["global_comp"]
    print_section("Before state", dump_state(before))

    local hidden = State.update_comp(comp, session)
    local after = State.get_states(nil)["global_comp"]

    print_section("After state", dump_state(after))
    print_section("Reason",
        "- No winid passed, so state lives in GlobalStates.\n"
        .. '- Value "gval" stored.\n'
        .. "- theme_aware=true stored.\n"
        .. "- Style is first creation (dirty=true).\n"
        .. "- Dynamic=true, so dirty remains true.")

    is_false(hidden, "not hidden")
    eq(after.value, "gval", "value stored in global")
    is_true(after.theme_aware_enabled, "theme_aware stored")
    eq(after.style.style.fg, "#aaa", "style fg stored")
    is_true(after.style.dirty, "dynamic style is dirty")
end)

----------------------------------------------------------------------
-- Run all tests
----------------------------------------------------------------------
print(string.format("%d/%d passed, %d failed", PASSED, PASSED + FAILED, FAILED))
if FAILED > 0 then
    os.exit(1)
end
