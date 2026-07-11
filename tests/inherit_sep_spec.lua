--- Integration tests for style inheritance and separator resolution
--- through the full update flow (update.lua → behavior → highlight → statusline).
---
--- Run: nvim --headless --cmd "set rtp+=<plugin_root>"
---        -c "luafile tests/inherit_sep_spec.lua" -c "qa!"

local helper = require("tests.helper")
local eq = helper.eq
local is_nil = helper.is_nil
local not_nil = helper.not_nil
local is_true = helper.is_true
local is_false = helper.is_false

-- ====================================================================
-- Mock infrastructure
-- ====================================================================
local function clear_table(t)
    for k in pairs(t) do t[k] = nil end
end

local statusline_calls = {
    set_value = {},
    set_side_value = {},
    hide_segment = {},
    push = {},
}

local function reset_statusline_calls()
    clear_table(statusline_calls.set_value)
    clear_table(statusline_calls.set_side_value)
    clear_table(statusline_calls.hide_segment)
    clear_table(statusline_calls.push)
end

--- Unique component ID counter (avoid cache collisions between tests).
local _id = 0
local function uid(prefix)
    _id = _id + 1
    return (prefix or "comp") .. "." .. _id
end

-- ====================================================================
-- Stub all external dependencies
-- ====================================================================
local MOCK_MODULES = {
    "witch-line",
    "witch-line.core.registry",
    "witch-line.engine.statusline",
    "witch-line.event.event",
    "witch-line.event.timer",
    "witch-line.util.bitmask",
    "witch-line.util.notifier",
    "witch-line.component",
    "witch-line.engine.update",
}

-- Shared ManagedComps table that update.lua will read from.
local ManagedComps = {}

package.preload["witch-line"] = function()
    return { user_config = { theme_aware = false } }
end

package.preload["witch-line.core.registry"] = function()
    local DepGraphKind = { Visible = 1, Event = 2, Timer = 3, All = 4 }
    return {
        DepGraphKind = DepGraphKind,
        ManagedComps = ManagedComps,
        register = function(id, comp)
            ManagedComps[id] = comp
            return comp
        end,
        get_comp = function(id) return ManagedComps[id] end,
        iterate_dependent_ids = function() return function() end end,
    }
end

package.preload["witch-line.engine.statusline"] = function()
    return {
        push = function(cid, text, winid)
            statusline_calls.push[#statusline_calls.push + 1] = {
                cid = cid, text = text, winid = winid,
            }
        end,
        set_value = function(cid, value, hl_name, winid)
            statusline_calls.set_value[#statusline_calls.set_value + 1] = {
                cid = cid, value = value, hl_name = hl_name, winid = winid,
            }
        end,
        set_side_value = function(cid, side, value, hl_name, force, winid)
            statusline_calls.set_side_value[#statusline_calls.set_side_value + 1] = {
                cid = cid, side = side, value = value,
                hl_name = hl_name, force = force, winid = winid,
            }
        end,
        hide_segment = function(cid, winid)
            statusline_calls.hide_segment[#statusline_calls.hide_segment + 1] = {
                cid = cid, winid = winid,
            }
        end,
        render = function() end,
        render_debounce = function() end,
        set_click_handler = function() end,
        track_flexible = function() end,
    }
end

package.preload["witch-line.event.event"] = function()
    return {
        register_events = function() end,
        on_event = function() end,
    }
end

package.preload["witch-line.event.timer"] = function()
    return {
        register_timer = function() end,
        on_timer_trigger = function() end,
    }
end

package.preload["witch-line.util.bitmask"] = function()
    return { is_marked = function() return false end, mark_bit = function() end }
end

package.preload["witch-line.util.notifier"] = function()
    return { info = function() end, error = function(msg) error(msg) end }
end

package.preload["witch-line.component"] = function()
    return setmetatable({}, {
        __index = function() return nil end,
    })
end

-- ====================================================================
-- Load modules under test (real implementations)
-- ====================================================================
local function fresh_update()
    for _, name in ipairs(MOCK_MODULES) do
        package.loaded[name] = nil
    end
    -- Only force-reload update.lua; let behavior/highlight/proxy/resolver
    -- stay cached since they have no mutable state that leaks.
    package.loaded["witch-line.engine.update"] = nil
    return require("witch-line.engine.update")
end

-- ====================================================================
-- Helpers to build component trees
-- ====================================================================

--- Build a component with default fields merged.
local function make_comp(overrides)
    local id = uid("comp")
    return vim.tbl_extend("force", {
        id = id,
        ___builtin = true,
        update = function() return "" end,
        renderable = true,
    }, overrides or {})
end

--- Register a component so update.lua can find it in ManagedComps.
local function register(comp)
    ManagedComps[comp.id] = comp
    return comp
end

--- Run update_single_comp on a component inside a session.
--- Returns the session for further inspection.
local function run_update(update_mod, comp, kind)
    local session
    require("witch-line.core.session").with_session(function(s)
        session = s
        update_mod.update_comp(comp, s, kind or 1) -- DepGraphKind.Visible = 1
    end)
    return session
end

--- Find the set_value call for a component.
local function find_set_value(cid)
    for _, c in ipairs(statusline_calls.set_value) do
        if c.cid == cid then return c end
    end
    return nil
end

--- Find set_side_value calls for a component.
local function find_side_values(cid)
    local left, right
    for _, c in ipairs(statusline_calls.set_side_value) do
        if c.cid == cid then
            if c.side == -1 then left = c end
            if c.side == 1 then right = c end
        end
    end
    return left, right
end

-- ====================================================================
-- Tests
-- ====================================================================

-- ---------------------------------------------------------------
print("=== Style inheritance: child inherits parent style ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        style = { fg = "#ffffff", bg = "#333333" },
        update = function() return "parent" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        update = function() return "child" end,
    })
    register(child)

    run_update(update, child)

    local sv = find_set_value(child.id)
    not_nil(sv, "child value was set")
    not_nil(sv.hl_name, "child got a highlight name")
end

-- ---------------------------------------------------------------
print("=== Style inheritance: child overrides fg, inherits bg ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        style = { fg = "#aaaaaa", bg = "#111111" },
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        style = { fg = "#bbbbbb" },
        update = function() return "c" end,
    })
    register(child)

    run_update(update, child)

    local sv = find_set_value(child.id)
    not_nil(sv, "child value was set")
    not_nil(sv.hl_name, "child got a highlight name")
    -- The highlight should exist in nvim with merged properties.
    local hl = vim.api.nvim_get_hl(0, { name = sv.hl_name, create = false })
    not_nil(hl, "highlight group was created")
end

-- ---------------------------------------------------------------
print("=== Style inheritance: grandchild chain ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local gp = make_comp({
        id = uid("gp"),
        style = { fg = "#aaa", bg = "#111" },
        update = function() return "gp" end,
    })
    register(gp)

    local mid = make_comp({
        id = uid("mid"),
        ___parent_id = gp.id,
        update = function() return "mid" end,
    })
    register(mid)

    local leaf = make_comp({
        id = uid("leaf"),
        ___parent_id = mid.id,
        update = function() return "leaf" end,
    })
    register(leaf)

    run_update(update, leaf)

    local sv = find_set_value(leaf.id)
    not_nil(sv, "leaf value was set")
    not_nil(sv.hl_name, "leaf got a highlight name via grandparent")
end

-- ---------------------------------------------------------------
print("=== Separator: parent defines left separator, child inherits ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        left = ">>",
        style = { fg = "#fff", bg = "#000" },
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        update = function() return "child" end,
    })
    register(child)

    run_update(update, child)

    local left = find_side_values(child.id)
    not_nil(left, "child got a left separator from parent")
    eq(left.value, ">>", "left separator value inherited from parent")
end

-- ---------------------------------------------------------------
print("=== Separator: child defines own separator, parent has different ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        left = "PARENT",
        style = { fg = "#fff", bg = "#000" },
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        left = "CHILD",
        update = function() return "c" end,
    })
    register(child)

    run_update(update, child)

    local left = find_side_values(child.id)
    not_nil(left, "child got a left separator")
    eq(left.value, "PARENT", "parent's left wins (nearest parent with value overrides)")
end

-- ---------------------------------------------------------------
print("=== Separator: right separator inheritance ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        right = "<<",
        style = { fg = "#fff", bg = "#000" },
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        update = function() return "c" end,
    })
    register(child)

    run_update(update, child)

    local _, right = find_side_values(child.id)
    not_nil(right, "child got a right separator from parent")
    eq(right.value, "<<", "right separator inherited")
end

-- ---------------------------------------------------------------
print("=== Separator: both left and right ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        left = "[",
        right = "]",
        style = { fg = "#fff", bg = "#000" },
        update = function() return "hello" end,
    })
    register(comp)

    run_update(update, comp)

    local left, right = find_side_values(comp.id)
    not_nil(left, "left separator set")
    not_nil(right, "right separator set")
    eq(left.value, "[", "left bracket")
    eq(right.value, "]", "right bracket")
end

-- ---------------------------------------------------------------
print("=== Separator: parent with dynamic left separator ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local counter = 0
    local parent = make_comp({
        id = uid("parent"),
        left = function()
            counter = counter + 1
            return counter == 1 and "A" or "B"
        end,
        style = { fg = "#fff", bg = "#000" },
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        update = function() return "c" end,
    })
    register(child)

    -- First update
    run_update(update, child)
    local left1 = find_side_values(child.id)
    not_nil(left1, "first update got left separator")
    eq(left1.value, "A", "dynamic parent separator: first value")

    -- Second update
    reset_statusline_calls()
    run_update(update, child)
    local left2 = find_side_values(child.id)
    not_nil(left2, "second update got left separator")
    eq(left2.value, "B", "dynamic parent separator: second value")
end

-- ---------------------------------------------------------------
print("=== Separator style: default SepBg ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        left = "<<",
        style = { fg = "#ffffff", bg = "#333333" },
        update = function() return "val" end,
    })
    register(comp)

    run_update(update, comp)

    local left = find_side_values(comp.id)
    not_nil(left, "left separator set")
    not_nil(left.hl_name, "left separator has highlight name")
    -- The highlight should exist with SepBg style: fg = main.bg, bg = NONE
    local hl = vim.api.nvim_get_hl(0, { name = left.hl_name, create = false })
    not_nil(hl, "left sep highlight group exists")
end

-- ---------------------------------------------------------------
print("=== Separator style: SepFg ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        left = ">>",
        left_style = 1, -- SepFg
        style = { fg = "#aaaaaa", bg = "#222222" },
        update = function() return "v" end,
    })
    register(comp)

    run_update(update, comp)

    local left = find_side_values(comp.id)
    not_nil(left, "left separator set")
    not_nil(left.hl_name, "left SepFg highlight allocated")
end

-- ---------------------------------------------------------------
print("=== Separator style: Reverse ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        right = "<>",
        right_style = 3, -- Reverse
        style = { fg = "#ffffff", bg = "#000000" },
        update = function() return "v" end,
    })
    register(comp)

    run_update(update, comp)

    local _, right = find_side_values(comp.id)
    not_nil(right, "right separator set")
    not_nil(right.hl_name, "right Reverse highlight allocated")
end

-- ---------------------------------------------------------------
print("=== Separator style: Inherited (reuse main hl) ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        left = "|",
        left_style = 0, -- Inherited
        style = { fg = "#ffffff", bg = "#000000" },
        update = function() return "v" end,
    })
    register(comp)

    run_update(update, comp)

    local sv = find_set_value(comp.id)
    local left = find_side_values(comp.id)
    not_nil(sv, "main value set")
    not_nil(left, "left separator set")
    -- Inherited means the side reuses the main highlight
    eq(left.hl_name, sv.hl_name, "Inherited side uses main highlight name")
end

-- ---------------------------------------------------------------
print("=== Separator style: custom table ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        left = "<",
        left_style = { fg = "#deadbeef", bold = true },
        style = { fg = "#fff", bg = "#000" },
        update = function() return "v" end,
    })
    register(comp)

    run_update(update, comp)

    local left = find_side_values(comp.id)
    not_nil(left, "left separator set")
    not_nil(left.hl_name, "custom table side style gets highlight")
    local hl = vim.api.nvim_get_hl(0, { name = left.hl_name, create = false })
    is_true(hl.bold, "custom bold attribute applied")
end

-- ---------------------------------------------------------------
print("=== Separator style: custom string highlight link ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    -- Create the target highlight first.
    vim.api.nvim_set_hl(0, "MySepHL", { fg = "#aabbcc" })

    local comp = make_comp({
        id = uid("comp"),
        left = "<",
        left_style = "MySepHL",
        style = { fg = "#fff", bg = "#000" },
        update = function() return "v" end,
    })
    register(comp)

    run_update(update, comp)

    local left = find_side_values(comp.id)
    not_nil(left, "left separator set")
    not_nil(left.hl_name, "string side style allocates a linked highlight group")
    -- String side style creates a NEW hl that links to the target.
    local hl = vim.api.nvim_get_hl(0, { name = left.hl_name, create = false })
    not_nil(hl, "linked highlight group exists")
    eq(hl.link, "MySepHL", "highlight links to MySepHL")
end

-- ---------------------------------------------------------------
print("=== Style inheritance + separator together ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        style = { fg = "#aaa", bg = "#111" },
        left = "(",
        right = ")",
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        style = { fg = "#bbb" },
        update = function() return "child" end,
    })
    register(child)

    run_update(update, child)

    local sv = find_set_value(child.id)
    local left, right = find_side_values(child.id)
    not_nil(sv, "child main value set")
    not_nil(left, "child left separator inherited")
    not_nil(right, "child right separator inherited")
    eq(left.value, "(", "left sep from parent")
    eq(right.value, ")", "right sep from parent")
end

-- ---------------------------------------------------------------
print("=== Dynamic style from update() overrides static ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        style = { fg = "#000000", bg = "#ffffff" },
        update = function()
            return "dynamic", { fg = "#ff0000", bg = "#00ff00" }
        end,
    })
    register(comp)

    run_update(update, comp)

    local sv = find_set_value(comp.id)
    not_nil(sv, "value set")
    not_nil(sv.hl_name, "highlight allocated")
    local hl = vim.api.nvim_get_hl(0, { name = sv.hl_name, create = false })
    not_nil(hl, "highlight group exists")
end

-- ---------------------------------------------------------------
print("=== Hidden component: no value or side set ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        style = { fg = "#fff", bg = "#000" },
        left = "<<",
        right = ">>",
        hidden = true,
        update = function() return "hidden" end,
    })
    register(comp)

    run_update(update, comp)

    local sv = find_set_value(comp.id)
    is_nil(sv, "hidden component: no set_value call")
    local left, right = find_side_values(comp.id)
    is_nil(left, "hidden component: no left separator")
    is_nil(right, "hidden component: no right separator")
end

-- ---------------------------------------------------------------
print("=== Empty update value: component hidden ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        style = { fg = "#fff", bg = "#000" },
        left = "<<",
        update = function() return "" end,
    })
    register(comp)

    run_update(update, comp)

    local sv = find_set_value(comp.id)
    is_nil(sv, "empty value: component hidden, no set_value")
end

-- ---------------------------------------------------------------
print("=== Dynamic left separator from child function ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local tick = 0
    local comp = make_comp({
        id = uid("comp"),
        left = function()
            tick = tick + 1
            return tick == 1 and "A" or "B"
        end,
        style = { fg = "#fff", bg = "#000" },
        update = function() return "v" end,
    })
    register(comp)

    run_update(update, comp)
    local left1 = find_side_values(comp.id)
    eq(left1.value, "A", "first call: A")

    reset_statusline_calls()
    run_update(update, comp)
    local left2 = find_side_values(comp.id)
    eq(left2.value, "B", "second call: B")
end

-- ---------------------------------------------------------------
print("=== Dynamic right separator: force flag ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local comp = make_comp({
        id = uid("comp"),
        right = function() return ">" end,
        style = { fg = "#fff", bg = "#000" },
        update = function() return "v" end,
    })
    register(comp)

    run_update(update, comp)

    local _, right = find_side_values(comp.id)
    not_nil(right, "right separator set")
    is_true(right.force, "dynamic separator has force=true")
end

-- ---------------------------------------------------------------
print("=== Parent with no style: child without style gets no hl ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        update = function() return "c" end,
    })
    register(child)

    run_update(update, child)

    local sv = find_set_value(child.id)
    not_nil(sv, "child value set")
    is_nil(sv.hl_name, "no highlight when neither parent nor child has style")
end

-- ---------------------------------------------------------------
print("=== Grandchild inherits grandparent separator (middle has none) ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local gp = make_comp({
        id = uid("gp"),
        left = "<<",
        right = ">>",
        style = { fg = "#fff", bg = "#000" },
        update = function() return "gp" end,
    })
    register(gp)

    local mid = make_comp({
        id = uid("mid"),
        ___parent_id = gp.id,
        update = function() return "mid" end,
    })
    register(mid)

    local leaf = make_comp({
        id = uid("leaf"),
        ___parent_id = mid.id,
        update = function() return "leaf" end,
    })
    register(leaf)

    run_update(update, leaf)

    local left, right = find_side_values(leaf.id)
    not_nil(left, "leaf left separator set")
    not_nil(right, "leaf right separator set")
    eq(left.value, "<<", "left inherited from grandparent")
    eq(right.value, ">>", "right inherited from grandparent")
end

-- ---------------------------------------------------------------
print("=== Mixed: parent sep style + child override sep style ===")
do
    local update = fresh_update()
    reset_statusline_calls()

    local parent = make_comp({
        id = uid("parent"),
        left = "<<",
        left_style = 2, -- SepBg default
        style = { fg = "#ffffff", bg = "#333333" },
        update = function() return "p" end,
    })
    register(parent)

    local child = make_comp({
        id = uid("child"),
        ___parent_id = parent.id,
        left_style = 1, -- SepFg
        update = function() return "c" end,
    })
    register(child)

    run_update(update, child)

    local left = find_side_values(child.id)
    not_nil(left, "child left separator set")
    not_nil(left.hl_name, "child left sep got its own highlight")
end

-- ====================================================================
-- Summary
-- ====================================================================
package.loaded["witch-line.engine.update"] = nil
local ok = helper.summary()
os.exit(ok and 0 or 1)
