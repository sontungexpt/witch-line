--- Tests for witch-line.engine.init
--- Tests only the public API: M.setup and Request.update_comp.
--- Internal functions (load_component, mount_component_tree, etc.) are
--- verified indirectly through side effects on mocked dependencies.
---
--- Run: nvim --headless -u tests/minimal_init.lua
---        -c "luafile tests/engine/init_spec.lua" -c "qa!"

local helper = require("tests.helper")
local eq = helper.eq
local is_true = helper.is_true
local is_false = helper.is_false
local not_nil = helper.not_nil

-- ====================================================================
-- Mock infrastructure
-- ====================================================================
--- Clear a table in-place without reassigning the variable.
--- Mock closures capture mock_calls/registered by reference;
--- clearing in-place preserves those references.
local function clear_table(t)
    for k in pairs(t) do t[k] = nil end
end

local mock_calls = {
    link_dependency = {},
    register_cid = {},
    push = {},
    register_timer = {},
    register_events = {},
    on_event_cb = nil,
    on_timer_cb = nil,
    render = 0,
    render_debounce = 0,
    autocmd_events = {},
    autocmd_cbs = {},
    schedule_cbs = {},
}
local registered = {}

local function reset_mocks()
    clear_table(registered)
    clear_table(mock_calls.link_dependency)
    clear_table(mock_calls.register_cid)
    clear_table(mock_calls.push)
    clear_table(mock_calls.register_timer)
    clear_table(mock_calls.register_events)
    clear_table(mock_calls.autocmd_events)
    clear_table(mock_calls.autocmd_cbs)
    clear_table(mock_calls.schedule_cbs)
    mock_calls.on_event_cb = nil
    mock_calls.on_timer_cb = nil
    mock_calls.render = 0
    mock_calls.render_debounce = 0
end

-- ====================================================================
-- Stub all dependencies of engine/init.lua via package.loaded
-- (package.preload is not used by Neovim's require).
-- ====================================================================

local COMPONENT_DEFS = {
    ["wl.test.simple"] = {
        id = "wl.test.simple", ___builtin = true,
        update = function() return "resolved" end,
    },
    ["wl.test.parent"] = {
        id = "wl.test.parent", ___builtin = true,
        update = function() return "parent" end,
    },
}

package.loaded["witch-line.component"] = setmetatable({}, {
    __index = function(_, id)
        return COMPONENT_DEFS[id]
    end,
})

local DepGraphKind = { Visible = 1, Event = 2, Timer = 3, All = 4 }
package.loaded["witch-line.core.registry"] = {
    DepGraphKind = DepGraphKind,
    ManagedComps = setmetatable({}, { __index = registered }),
    is_existed = function(id) return registered[id] ~= nil end,
    link_dependency = function(kind, source, dep)
        mock_calls.link_dependency[#mock_calls.link_dependency + 1] = {
            kind = kind, source = source, dep = dep,
        }
    end,
    register = function(cid, comp)
        registered[cid] = comp
        mock_calls.register_cid[#mock_calls.register_cid + 1] = cid
        return comp
    end,
    get_comp = function(id) return registered[id] end,
    iterate_dependent_ids = function() return function() end end,
}

package.loaded["witch-line.engine.statusline"] = {
    push = function(cid, text, winid)
        mock_calls.push[#mock_calls.push + 1] = { cid = cid, text = text, winid = winid }
    end,
    render = function() mock_calls.render = mock_calls.render + 1 end,
    render_debounce = function() mock_calls.render_debounce = mock_calls.render_debounce + 1 end,
    hide_segment = function() end,
    track_flexible = function() end,
}

package.loaded["witch-line.core.override"] = function(base, overrides)
    local result = vim.tbl_deep_extend("force", base, overrides)
    if overrides.style then
        result.___accept_returned_style = false
    end
    if overrides.style or overrides.left_style or overrides.right_style then
        result.theme_aware = false
    end
    return result
end

package.loaded["witch-line.core.component_api"] = {
    pre_update = function() end,
    hidden = function() return false end,
    evaluate = function() return "", nil end,
}

package.loaded["witch-line.core.session"] = {
    with_session = function(fn)
        fn({
            get_cache = function() return nil end,
            set_cache = function() end,
            set = function() end,
        })
    end,
}

package.loaded["witch-line.event.event"] = {
    register_events = function(cid, events)
        mock_calls.register_events[#mock_calls.register_events + 1] = { cid = cid, events = events }
    end,
    on_event = function(cb) mock_calls.on_event_cb = cb end,
}

package.loaded["witch-line.event.timer"] = {
    register_timer = function(cid, timing)
        mock_calls.register_timer[#mock_calls.register_timer + 1] = { cid = cid, timing = timing }
    end,
    on_timer_trigger = function(cb) mock_calls.on_timer_cb = cb end,
}

--- Transitive deps needed by module loading
package.loaded["witch-line.engine.update"] = {
    update_comp_by_ids = function() end,
    update_comp = function() end,
    update_comp_graph_by_ids = function() end,
    update_comp_graph = function() end,
}
package.loaded["witch-line.core.highlight"] = {}
package.loaded["witch-line.util.bitmask"] = {
    is_marked = function() return false end, mark_bit = function() end,
}
package.loaded["witch-line.util.notifier"] = {
    info = function() end, error = function(msg) error(msg) end,
}
package.loaded["witch-line.constant.color"] = {}

-- ====================================================================
-- Stub Neovim API
-- ====================================================================
local real_api = vim.api
local real_schedule = vim.schedule

local function stub_vim_api()
    vim.api.nvim_create_autocmd = function(events, opts)
        mock_calls.autocmd_events[#mock_calls.autocmd_events + 1] = events
        if opts and opts.callback then
            mock_calls.autocmd_cbs[#mock_calls.autocmd_cbs + 1] = opts.callback
        end
    end
    vim.api.nvim_get_current_win = function() return 1000 end
    vim.api.nvim_win_is_valid = function() return true end
    vim.schedule = function(fn)
        mock_calls.schedule_cbs[#mock_calls.schedule_cbs + 1] = fn
    end
end

local function restore_vim_api()
    vim.api = real_api
    vim.schedule = real_schedule
end

stub_vim_api()

-- ====================================================================
-- Helper: fresh module + fresh mocks per sub-test
-- ====================================================================
local Request
--- Only the module under test needs re-loading. Mocks are set via
--- package.loaded (not preload) and reference mock_calls/registered
--- which are cleared in-place by reset_mocks().
local MOCK_MODULES = {
    "witch-line.engine.init",
    "witch-line.engine.request",
}

local function fresh_engine()
    reset_mocks()
    for _, name in ipairs(MOCK_MODULES) do
        package.loaded[name] = nil
    end
    local ok, eng = pcall(require, "witch-line.engine.init")
    if not ok then error("reload failed: " .. tostring(eng)) end
    Request = require("witch-line.engine.request")
    return eng
end

--- Shorthand: setup + fresh engine
local function run_setup(cfg)
    local eng = fresh_engine()
    eng.setup(cfg or { global = {} })
    return eng
end

-- ====================================================================
-- Tests
-- ====================================================================

-- ---------------------------------------------------------------
print("=== M.setup: global component mounting ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "hello" end,
        },
    })

    is_true(#mock_calls.register_cid >= 1, "component registered")
    local push_found = false
    for _, p in ipairs(mock_calls.push) do
        if p.cid == "wl.test.simple" then push_found = true end
    end
    is_true(push_found, "component pushed to statusline")
end

do
    local eng = run_setup({
        global = { "wl.test.simple", "wl.test.parent" },
    })

    eq(#mock_calls.register_cid, 2, "two resolved components registered")
    eq(#mock_calls.push, 2, "both pushed to statusline")
end

do
    local eng = run_setup({
        global = { "plain literal text" },
    })

    eq(#mock_calls.push, 1, "unresolved string pushed")
    eq(mock_calls.push[1].cid, nil, "literal has nil cid")
    eq(mock_calls.push[1].text, "plain literal text", "literal text preserved")
end

do
    local eng = run_setup({
        global = {
            id = "wl.abstract",
            ___builtin = true,
            abstract = true,
        },
    })

    eq(#mock_calls.push, 0, "abstract component not pushed")
end

do
    local eng = run_setup({
        global = {
            {
                id = "wl.test.simple",
                ___builtin = true,
                update = function() return "a" end,
            },
            "literal two",
        },
    })

    eq(#mock_calls.register_cid, 1, "one component registered from list")
    eq(#mock_calls.push, 2, "both children pushed")
end

-- ---------------------------------------------------------------
print("=== M.setup: dependency links via delegator ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "dep" end,
            delegator = { events = "wl.test.parent" },
        },
    })

    local found = false
    for _, ld in ipairs(mock_calls.link_dependency) do
        if ld.kind == 2 and ld.source == "wl.test.parent" and ld.dep == "wl.test.simple" then
            found = true
        end
    end
    is_true(found, "event dependency linked")
end

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "multi" end,
            delegator = { events = { "wl.test.parent", "wl.test.simple" } },
        },
    })

    local count = 0
    for _, ld in ipairs(mock_calls.link_dependency) do
        if ld.kind == 2 and ld.dep == "wl.test.simple" then
            count = count + 1
        end
    end
    eq(count, 2, "two event dependencies linked")
end

-- ---------------------------------------------------------------
print("=== M.setup: timer and event registration ===")

do
    local eng = run_setup({
        global = {
            id = "wl.timed",
            ___builtin = true,
            update = function() return "tick" end,
            timing = 5000,
        },
    })

    eq(#mock_calls.register_timer, 1, "timer registered")
    eq(mock_calls.register_timer[1].cid, "wl.timed")
    eq(mock_calls.register_timer[1].timing, 5000)
end

do
    local eng = run_setup({
        global = {
            id = "wl.ev",
            ___builtin = true,
            update = function() return "boom" end,
            events = { "BufEnter", "BufWritePost" },
        },
    })

    eq(#mock_calls.register_events, 1, "events registered")
    eq(mock_calls.register_events[1].cid, "wl.ev")
end

-- ---------------------------------------------------------------
print("=== M.setup: init lifecycle ===")

do
    local init_called = false
    local eng = run_setup({
        global = {
            id = "wl.inited",
            ___builtin = true,
            update = function() return "hello" end,
            init = function(self)
                init_called = true
                self.___test_inited = true
            end,
        },
    })

    is_true(init_called, "init function called")
    is_true(registered["wl.inited"].___test_inited, "init wrote to component")
end

-- ---------------------------------------------------------------
print("=== M.setup: EmergencyIds (lazy=false) ===")

do
    local eng = run_setup({
        global = {
            id = "wl.emergency",
            ___builtin = true,
            lazy = false,
            update = function() return "urgent" end,
        },
    })

    is_true(mock_calls.render_debounce >= 1, "render debounced for emergency update")
end

-- ---------------------------------------------------------------
print("=== M.setup: event/timer handler registration ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "x" end,
        },
    })

    not_nil(mock_calls.on_event_cb, "on_event handler registered")
    not_nil(mock_calls.on_timer_cb, "on_timer_trigger handler registered")
end

-- ---------------------------------------------------------------
print("=== M.setup: per-window components (WinEnter) ===")

do
    local eng = run_setup({
        global = { "global_literal" },
        win = function() return { "win_literal" } end,
    })

    eq(mock_calls.push[1].text, "global_literal", "global literal pushed")

    local found_win = false
    for _, events in ipairs(mock_calls.autocmd_events) do
        if type(events) == "table" then
            for _, e in ipairs(events) do
                if e == "WinEnter" or e == "WinClosed" then found_win = true end
            end
        end
    end
    is_true(found_win, "WinEnter/WinClosed autocmd created")

    -- Fire WinEnter, then run scheduled win mount
    if #mock_calls.autocmd_cbs > 0 then
        local cb = mock_calls.autocmd_cbs[1]
        cb({ event = "WinEnter", match = "1000" })

        eq(#mock_calls.schedule_cbs, 1, "win mount scheduled via vim.schedule")

        local scheduled = mock_calls.schedule_cbs[1]
        scheduled()

        is_true(#mock_calls.push >= 2, "win literal pushed after WinEnter")
        if #mock_calls.push >= 2 then
            eq(mock_calls.push[#mock_calls.push].text, "win_literal", "win literal text correct")
        end
    end
end

-- ---------------------------------------------------------------
print("=== Request.update_comp ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "base" end,
        },
    })

    local base_render = mock_calls.render

    Request.update_comp(
        { id = "wl.test.simple" },
        true
    )

    eq(mock_calls.render, base_render + 1, "eager render incremented")
end

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "base" end,
        },
    })

    local base_debounce = mock_calls.render_debounce

    Request.update_comp(
        { id = "wl.test.simple" },
        false
    )

    eq(mock_calls.render_debounce, base_debounce + 1, "debounce render incremented")
end

-- ---------------------------------------------------------------
print("=== M.setup: combined component (parent + children) ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.container",
            ___builtin = true,
            update = function() return "container" end,
            style = { fg = "#ffffff" },
            {
                id = "wl.test.child1",
                ___builtin = true,
                update = function() return "child1" end,
            },
            {
                id = "wl.test.child2",
                ___builtin = true,
                update = function() return "child2" end,
            },
            "literal_child",
        },
    })

    eq(#mock_calls.register_cid, 3, "container + 2 children registered")
    eq(#mock_calls.push, 4, "container + 2 children + literal pushed")

    eq(registered["wl.test.child1"].___parent_id, "wl.test.container", "child1 parent is container")
    eq(registered["wl.test.child2"].___parent_id, "wl.test.container", "child2 parent is container")
end

-- ---------------------------------------------------------------
print("=== M.setup: combined component inherits parent fields ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.parent_style",
            ___builtin = true,
            update = function() return "p" end,
            style = { fg = "Special" },
            {
                id = "wl.test.styled_child",
                ___builtin = true,
                update = function() return "c" end,
            },
        },
    })

    local parent = registered["wl.test.parent_style"]
    not_nil(parent, "parent registered")
    eq(parent.style.fg, "Special", "parent has style")
end

-- ---------------------------------------------------------------
print("=== M.setup: combined component with timer child ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.timer_parent",
            ___builtin = true,
            update = function() return "tp" end,
            {
                id = "wl.test.timer_child",
                ___builtin = true,
                update = function() return "tc" end,
                timing = 2000,
            },
        },
    })

    eq(#mock_calls.register_timer, 1, "timer registered for child")
    eq(mock_calls.register_timer[1].cid, "wl.test.timer_child")
    eq(mock_calls.register_timer[1].timing, 2000)
end

-- ---------------------------------------------------------------
print("=== M.setup: combined component with event child ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.event_parent",
            ___builtin = true,
            update = function() return "ep" end,
            {
                id = "wl.test.event_child",
                ___builtin = true,
                update = function() return "ec" end,
                events = "DiagnosticChanged",
            },
        },
    })

    eq(#mock_calls.register_events, 1, "events registered for child")
    eq(mock_calls.register_events[1].cid, "wl.test.event_child")
end

-- ---------------------------------------------------------------
print("=== M.setup: deeply nested combined components ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.grandparent",
            ___builtin = true,
            update = function() return "gp" end,
            {
                id = "wl.test.parent2",
                ___builtin = true,
                update = function() return "p2" end,
                {
                    id = "wl.test.grandchild",
                    ___builtin = true,
                    update = function() return "gc" end,
                },
            },
        },
    })

    eq(#mock_calls.register_cid, 3, "grandparent + parent + grandchild registered")
    eq(#mock_calls.push, 3, "all three pushed")

    eq(registered["wl.test.parent2"].___parent_id, "wl.test.grandparent", "parent2 is child of grandparent")
    eq(registered["wl.test.grandchild"].___parent_id, "wl.test.parent2", "grandchild is child of parent2")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] merges into base ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.override",
            padding = 5,
        },
    })

    local comp = registered["my.override"]
    not_nil(comp, "override comp registered with custom id")
    eq(comp.padding, 5, "padding merged from override")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] base update preserved ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.override2",
            padding = 3,
        },
    })

    local comp = registered["my.override2"]
    not_nil(comp, "override comp registered")
    not_nil(comp.update, "base update function preserved")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] unknown path falls through ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.nonexistent.component",
            id = "my.fallback",
            update = function() return "fallback" end,
        },
    })

    local comp = registered["my.fallback"]
    not_nil(comp, "fallback comp registered")
    eq(comp.update(), "fallback", "own update used")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with style ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.styled",
            style = { fg = "#ff0000" },
        },
    })

    local comp = registered["my.styled"]
    not_nil(comp, "styled override registered")
    eq(type(comp.style), "table", "style is table")
    eq(comp.style.fg, "#ff0000", "style fg from override")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with events ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.evented",
            events = "BufEnter",
        },
    })

    local comp = registered["my.evented"]
    not_nil(comp, "evented override registered")
    local found = false
    for _, e in ipairs(mock_calls.register_events) do
        if e.cid == "my.evented" then found = true end
    end
    is_true(found, "events registered for override comp")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with timing ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.timed",
            timing = 3000,
        },
    })

    local comp = registered["my.timed"]
    not_nil(comp, "timed override registered")
    local found = false
    for _, t in ipairs(mock_calls.register_timer) do
        if t.cid == "my.timed" then found = true end
    end
    is_true(found, "timer registered for override comp")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with ref ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.dep",
            delegator = { events = "wl.test.parent" },
        },
    })

    local found = false
    for _, ld in ipairs(mock_calls.link_dependency) do
        if ld.kind == 2 and ld.source == "wl.test.parent" and ld.dep == "my.dep" then
            found = true
        end
    end
    is_true(found, "event dependency linked for override comp")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] config deep merge ===")

do
    COMPONENT_DEFS["wl.test.configurable"] = {
        id = "wl.test.configurable", ___builtin = true,
        config = { icon = "A", level = 1 },
        update = function() return "cfg" end,
    }

    local eng = run_setup({
        global = {
            [0] = "wl.test.configurable",
            id = "my.cfg",
            config = { level = 9 },
        },
    })

    local comp = registered["my.cfg"]
    not_nil(comp, "config override registered")
    eq(comp.config.icon, "A", "base config.icon preserved")
    eq(comp.config.level, 9, "config.level overridden")

    COMPONENT_DEFS["wl.test.configurable"] = nil
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] constructor called ===")

do
    local constructor_called = false
    COMPONENT_DEFS["wl.test.installable"] = {
        id = "wl.test.installable", ___builtin = true,
        constructor = function(self) constructor_called = true end,
        update = function() return "inst" end,
    }

    local eng = run_setup({
        global = {
            [0] = "wl.test.installable",
            id = "my.inst",
            padding = 1,
        },
    })

    is_true(constructor_called, "constructor function called on override comp")

    COMPONENT_DEFS["wl.test.installable"] = nil
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] custom update replaces base ===")

do
    COMPONENT_DEFS["wl.test.updatable"] = {
        id = "wl.test.updatable", ___builtin = true,
        update = function() return "base" end,
    }

    local eng = run_setup({
        global = {
            [0] = "wl.test.updatable",
            id = "my.upd",
            update = function() return "custom" end,
        },
    })

    local comp = registered["my.upd"]
    not_nil(comp, "custom update comp registered")
    eq(comp.update(), "custom", "custom update overrides base")

    COMPONENT_DEFS["wl.test.updatable"] = nil
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with hidden ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.hidden",
            hidden = function() return true end,
        },
    })

    local comp = registered["my.hidden"]
    not_nil(comp, "hidden override registered")
    eq(type(comp.hidden), "function", "hidden is function")
    is_true(comp.hidden(), "hidden returns true")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] ___builtin from base ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.builtin",
        },
    })

    local comp = registered["my.builtin"]
    not_nil(comp, "override comp registered")
    is_true(comp.___builtin, "___builtin inherited from base")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with padding table ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.pad",
            padding = { left = 2, right = 3 },
        },
    })

    local comp = registered["my.pad"]
    not_nil(comp, "table padding override registered")
    eq(type(comp.padding), "table", "padding is table")
    eq(comp.padding.left, 2, "padding.left from override")
    eq(comp.padding.right, 3, "padding.right from override")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with theme_aware ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.theme",
            theme_aware = true,
        },
    })

    local comp = registered["my.theme"]
    not_nil(comp, "theme_aware override registered")
    is_true(comp.theme_aware, "theme_aware set")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with left_style ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.ls",
            left_style = { fg = "#aaa" },
        },
    })

    local comp = registered["my.ls"]
    not_nil(comp, "left_style override registered")
    eq(type(comp.left_style), "table", "left_style is table")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with flexible ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.flex",
            flexible = 3,
            update = function() return "flex" end,
        },
    })

    local comp = registered["my.flex"]
    not_nil(comp, "flexible override registered")
    eq(comp.flexible, 3, "flexible from override")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with lazy ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.lazy",
            lazy = false,
        },
    })

    local comp = registered["my.lazy"]
    not_nil(comp, "lazy override registered")
    is_false(comp.lazy, "lazy = false from override")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] with left/right ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.lr",
            left = ">>",
            right = "<<",
        },
    })

    local comp = registered["my.lr"]
    not_nil(comp, "left/right override registered")
    eq(comp.left, ">>", "left from override")
    eq(comp.right, "<<", "right from override")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] combined parent + override child ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.container2",
            ___builtin = true,
            update = function() return "container" end,
            {
                [0] = "wl.test.simple",
                id = "my.child.override",
                padding = 7,
            },
        },
    })

    local comp = registered["my.child.override"]
    not_nil(comp, "override child registered")
    eq(comp.padding, 7, "child override padding merged")
    eq(comp.___parent_id, "wl.test.container2", "child linked to container")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] list field replaced ===")

do
    COMPONENT_DEFS["wl.test.listcomp"] = {
        id = "wl.test.listcomp", ___builtin = true,
        config = { modes = { "normal", "insert" } },
        update = function() return "lst" end,
    }

    local eng = run_setup({
        global = {
            [0] = "wl.test.listcomp",
            id = "my.list",
            config = { modes = { "visual" } },
        },
    })

    local comp = registered["my.list"]
    not_nil(comp, "list override registered")
    is_true(vim.islist(comp.config.modes), "nested list replaced")
    eq(#comp.config.modes, 1, "list has one entry")
    eq(comp.config.modes[1], "visual", "list entry from override")

    COMPONENT_DEFS["wl.test.listcomp"] = nil
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] style disables accept_returned_style ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.nodr",
            style = { fg = "#fff" },
        },
    })

    local comp = registered["my.nodr"]
    not_nil(comp, "override comp registered")
    is_false(comp.___accept_returned_style, "accept_returned_style disabled by style")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] style disables theme_aware ===")

do
    local eng = run_setup({
        global = {
            [0] = "wl.test.simple",
            id = "my.notheme",
            style = { fg = "#fff" },
        },
    })

    local comp = registered["my.notheme"]
    not_nil(comp, "override comp registered")
    is_false(comp.theme_aware, "theme_aware disabled by style override")
end

-- ---------------------------------------------------------------
print("=== M.setup: override comp[0] non-table [0] ignored ===")

do
    local eng = run_setup({
        global = {
            [0] = 123,
            id = "my.bad0",
            update = function() return "ok" end,
        },
    })

    local comp = registered["my.bad0"]
    not_nil(comp, "comp with non-string [0] registered")
    eq(comp.update(), "ok", "own update used")
end

-- ====================================================================
-- Summary
-- ====================================================================
restore_vim_api()

local ok = helper.summary()
os.exit(ok and 0 or 1)
