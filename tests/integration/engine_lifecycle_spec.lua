--- Integration tests for engine/init.lua lifecycle.
--- Covers: setup, component mounting, dependency links, init, emergency, events/timers.

local a = require("tests.helpers.assert")

-- ====================================================================
-- Mock infrastructure
-- ====================================================================
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
    __index = function(_, id) return COMPONENT_DEFS[id] end,
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
-- Fresh module helper
-- ====================================================================
local Request

local MOCK_MODULES = {
    "witch-line.engine.init",
    "witch-line.engine.request",
}

local function fresh_engine()
    reset_mocks()
    for _, name in ipairs(MOCK_MODULES) do package.loaded[name] = nil end
    local eng = require("witch-line.engine.init")
    Request = require("witch-line.engine.request")
    return eng
end

local function run_setup(cfg)
    local eng = fresh_engine()
    eng.setup(cfg or { global = {} })
    return eng
end

-- ====================================================================
-- Tests
-- ====================================================================

print("=== Setup: global component mounting ===")

do
    run_setup({ global = {
        id = "wl.test.simple", ___builtin = true,
        update = function() return "hello" end,
    }})
    a.is_true(#mock_calls.register_cid >= 1, "component registered")
    local found = false
    for _, p in ipairs(mock_calls.push) do
        if p.cid == "wl.test.simple" then found = true end
    end
    a.is_true(found, "pushed to statusline")
end

do
    run_setup({ global = { "wl.test.simple", "wl.test.parent" } })
    a.eq(#mock_calls.register_cid, 2, "two components registered")
    a.eq(#mock_calls.push, 2, "both pushed")
end

do
    run_setup({ global = { "plain literal text" } })
    a.eq(#mock_calls.push, 1, "literal pushed")
    a.is_nil(mock_calls.push[1].cid, "literal has nil cid")
end

do
    run_setup({ global = {
        id = "wl.abstract", ___builtin = true, abstract = true,
    }})
    a.eq(#mock_calls.push, 0, "abstract not pushed")
end

-- ====================================================================
print("=== Setup: dependency links via ref ===")

do
    run_setup({ global = {
        id = "wl.test.simple", ___builtin = true,
        update = function() return "dep" end,
        ref = { events = "wl.test.parent" },
    }})
    local found = false
    for _, ld in ipairs(mock_calls.link_dependency) do
        if ld.kind == 2 and ld.source == "wl.test.parent" and ld.dep == "wl.test.simple" then
            found = true
        end
    end
    a.is_true(found, "event dependency linked")
end

-- ====================================================================
print("=== Setup: timer registration ===")

do
    run_setup({ global = {
        id = "wl.timed", ___builtin = true,
        update = function() return "tick" end,
        timing = 5000,
    }})
    a.eq(#mock_calls.register_timer, 1, "timer registered")
    a.eq(mock_calls.register_timer[1].cid, "wl.timed")
    a.eq(mock_calls.register_timer[1].timing, 5000)
end

-- ====================================================================
print("=== Setup: event registration ===")

do
    run_setup({ global = {
        id = "wl.ev", ___builtin = true,
        update = function() return "boom" end,
        events = { "BufEnter", "BufWritePost" },
    }})
    a.eq(#mock_calls.register_events, 1, "events registered")
    a.eq(mock_calls.register_events[1].cid, "wl.ev")
end

-- ====================================================================
print("=== Setup: init lifecycle ===")

do
    local init_called = false
    run_setup({ global = {
        id = "wl.inited", ___builtin = true,
        update = function() return "hello" end,
        init = function(self) init_called = true; self.___test_inited = true end,
    }})
    a.is_true(init_called, "init called")
    a.is_true(registered["wl.inited"].___test_inited, "init wrote to component")
end

-- ====================================================================
print("=== Setup: emergency (lazy=false) ===")

do
    run_setup({ global = {
        id = "wl.emergency", ___builtin = true,
        lazy = false, update = function() return "urgent" end,
    }})
    a.is_true(mock_calls.render_debounce >= 1, "render_debounce called")
end

-- ====================================================================
print("=== Setup: event/timer handler registration ===")

do
    run_setup({ global = {
        id = "wl.test.simple", ___builtin = true,
        update = function() return "x" end,
    }})
    a.not_nil(mock_calls.on_event_cb, "on_event registered")
    a.not_nil(mock_calls.on_timer_cb, "on_timer registered")
end

-- ====================================================================
print("=== Setup: per-window components ===")

do
    run_setup({
        global = { "global_literal" },
        win = function() return { "win_literal" } end,
    })
    a.eq(mock_calls.push[1].text, "global_literal", "global pushed")

    local found_win = false
    for _, events in ipairs(mock_calls.autocmd_events) do
        if type(events) == "table" then
            for _, e in ipairs(events) do
                if e == "WinEnter" or e == "WinClosed" then found_win = true end
            end
        end
    end
    a.is_true(found_win, "WinEnter autocmd created")

    if #mock_calls.autocmd_cbs > 0 then
        local cb = mock_calls.autocmd_cbs[1]
        cb({ event = "WinEnter", match = "1000" })
        a.eq(#mock_calls.schedule_cbs, 1, "win mount scheduled")
        mock_calls.schedule_cbs[1]()
        a.is_true(#mock_calls.push >= 2, "win literal pushed")
    end
end

-- ====================================================================
print("=== Request.update_comp ===")

do
    local eng = run_setup({ global = {
        id = "wl.test.simple", ___builtin = true,
        update = function() return "base" end,
    }})
    local base_render = mock_calls.render
    Request.update_comp({ id = "wl.test.simple" }, nil, true)
    a.eq(mock_calls.render, base_render + 1, "eager render")
end

do
    local eng = run_setup({ global = {
        id = "wl.test.simple", ___builtin = true,
        update = function() return "base" end,
    }})
    local base_debounce = mock_calls.render_debounce
    Request.update_comp({ id = "wl.test.simple" }, nil, false)
    a.eq(mock_calls.render_debounce, base_debounce + 1, "debounce render")
end

-- ====================================================================
-- Summary
-- ====================================================================
restore_vim_api()
local ok = a.summary()
os.exit(ok and 0 or 1)
