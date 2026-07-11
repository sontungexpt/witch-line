--- Tests for witch-line.engine.init
--- Tests only the public API: M.setup and M.request_update_comp_graph.
--- Internal functions (load_component, mount_component_tree, etc.) are
--- verified indirectly through side effects on mocked dependencies.
---
--- Run: nvim --headless -u tests/minimal_init.lua
---        -c "luafile tests/engine/init_spec.lua" -c "qa!"

local helper = require("tests.helper")
local eq = helper.eq
local is_true = helper.is_true
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

local DepGraphKind = { Visible = 1, Event = 2, Timer = 3 }
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
    return vim.tbl_deep_extend("force", base, overrides)
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
package.loaded["witch-line.engine.highlight"] = {}
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
--- Only the module under test needs re-loading. Mocks are set via
--- package.loaded (not preload) and reference mock_calls/registered
--- which are cleared in-place by reset_mocks().
local MOCK_MODULES = {
    "witch-line.engine.init",
}

local function fresh_engine()
    reset_mocks()
    for _, name in ipairs(MOCK_MODULES) do
        package.loaded[name] = nil
    end
    local ok, eng = pcall(require, "witch-line.engine.init")
    if not ok then error("reload failed: " .. tostring(eng)) end
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
print("=== M.setup: dependency links via ref ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "dep" end,
            ref = { events = "wl.test.parent" },
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
            ref = { events = { "wl.test.parent", "wl.test.simple" } },
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
print("=== M.request_update_comp_graph ===")

do
    local eng = run_setup({
        global = {
            id = "wl.test.simple",
            ___builtin = true,
            update = function() return "base" end,
        },
    })

    local base_render = mock_calls.render

    eng.request_update_comp_graph(
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

    eng.request_update_comp_graph(
        { id = "wl.test.simple" },
        false
    )

    eq(mock_calls.render_debounce, base_debounce + 1, "debounce render incremented")
end

-- ====================================================================
-- Summary
-- ====================================================================
restore_vim_api()

local ok = helper.summary()
os.exit(ok and 0 or 1)
