--- Tests for witch-line.event.event
--- Run: nvim --headless -u tests/minimal_init.lua
---        -c "luafile tests/event/init_spec.lua" -c "qa!"

local helper = require("tests.helper")
local eq = helper.eq
local is_true = helper.is_true
local is_nil = helper.is_nil
local not_nil = helper.not_nil

-- ====================================================================
-- Mock infrastructure
-- ====================================================================
local mock = {
    augroup_id = 42,
    autocmd = { calls = {}, callbacks = {} },
    work_calls = {},
}

local function reset_mocks()
    mock.autocmd.calls = {}
    mock.autocmd.callbacks = {}
    mock.work_calls = {}
end

-- ====================================================================
-- Stub dependencies via package.preload
-- ====================================================================
package.preload["witch-line.util.tbl"] = function()
    return {
        array_equal = function(a, b)
            if #a ~= #b then return false end
            for i = 1, #a do
                if a[i] ~= b[i] then return false end
            end
            return true
        end,
    }
end

package.preload["witch-line.util.debounce"] = function()
    return function(fn) return fn end
end

package.preload["witch-line.util.notifier"] = function()
    return { info = function() end }
end

-- ====================================================================
-- Stub Neovim API
-- ====================================================================
local real_api = vim.api
local real_tbl_keys = vim.tbl_keys
local real_tbl_filter = vim.tbl_filter
local real_inspect = vim.inspect

local function stub_vim_api()
    vim.api.nvim_create_augroup = function() return mock.augroup_id end
    vim.api.nvim_create_autocmd = function(events, opts)
        local idx = #mock.autocmd.calls + 1
        mock.autocmd.calls[idx] = { events = events, opts = opts }
        if opts and opts.callback then
            mock.autocmd.callbacks[idx] = opts.callback
        end
    end
    vim.tbl_keys = function(t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        return keys
    end
    vim.tbl_filter = function(fn, list)
        local result = {}
        for i = 1, #list do
            if fn(list[i]) then result[#result + 1] = list[i] end
        end
        return result
    end
    vim.inspect = function(x) return tostring(x) end
end

local function restore_vim_api()
    vim.api = real_api
    vim.tbl_keys = real_tbl_keys
    vim.tbl_filter = real_tbl_filter
    vim.inspect = real_inspect
end

stub_vim_api()

-- ====================================================================
-- Helper: fresh module per sub-test
-- ====================================================================
local MOCK_MODULES = {
    "witch-line.event.event",
    "witch-line.util.tbl",
    "witch-line.util.debounce",
    "witch-line.util.notifier",
}

local function fresh_event()
    reset_mocks()
    for _, name in ipairs(MOCK_MODULES) do
        package.loaded[name] = nil
    end
    local ok, ev = pcall(require, "witch-line.event.event")
    if not ok then error("reload failed: " .. tostring(ev)) end
    return ev
end

--- Setup: register events + call on_event
local function setup(events, cid)
    local ev = fresh_event()
    ev.register_events(cid or "cid1", events)
    ev.on_event(function(ids, event_info)
        local filtered = {}
        for _, id in ipairs(ids) do filtered[#filtered + 1] = id end
        mock.work_calls[#mock.work_calls + 1] = { ids = filtered, info = event_info }
    end)
    return ev
end

--- Fire the i-th autocmd callback with a mock event info table
local function fire_autocmd(idx, event_info)
    local cb = mock.autocmd.callbacks[idx]
    if cb then cb(event_info or {}) end
end

--- Check that autocmd call #idx has events matching the given name set
local function check_autocmd_events(idx, expected_names)
    local c = mock.autocmd.calls[idx]
    local names = type(c.events) == "string" and { c.events } or c.events
    local found = {}
    for _, n in ipairs(names) do found[n] = true end
    for _, exp in ipairs(expected_names) do
        is_true(found[exp], "autocmd includes event '" .. exp .. "'")
    end
    eq(#names, #expected_names, "autocmd events count")
end

-- ====================================================================
-- Tests
-- ====================================================================

-- ---------------------------------------------------------------
print("=== register_events: string format ===")

do
    setup("BufEnter")
    eq(#mock.autocmd.calls, 1, "one autocmd created")
    check_autocmd_events(1, { "BufEnter" })
    eq(mock.autocmd.calls[1].opts.group, 42, "correct augroup")
    is_nil(mock.autocmd.calls[1].opts.pattern, "no pattern for bare event")
end

do
    setup("BufEnter *.lua")
    local c = mock.autocmd.calls[1]
    eq(c.events, "BufEnter", "event name is a string for special event")
    eq(c.opts.pattern, "*.lua", "pattern passed to autocmd")
end

do
    setup("BufEnter *.lua, *.py")
    local c = mock.autocmd.calls[1]
    eq(c.events, "BufEnter", "event name is string")
    eq(#c.opts.pattern, 2, "two patterns")
    eq(c.opts.pattern[1], "*.lua")
    eq(c.opts.pattern[2], "*.py")
end

do
    setup("  CursorHold")
    check_autocmd_events(1, { "CursorHold" })
    is_nil(mock.autocmd.calls[1].opts.pattern, "no pattern")
end

do
    setup("User LazyLoad")
    eq(#mock.autocmd.calls, 1, "one autocmd for user event")
    local c = mock.autocmd.calls[1]
    eq(c.events, "User", "User autocmd event name")
    eq(#c.opts.pattern, 1, "one user pattern")
    eq(c.opts.pattern[1], "LazyLoad")
end

do
    setup("User LazyLoad, ColorScheme")
    local c = mock.autocmd.calls[1]
    eq(c.events, "User")
    eq(#c.opts.pattern, 2, "two user event patterns")
end

do
    setup("BufEnter *")
    check_autocmd_events(1, { "BufEnter" })
    is_nil(mock.autocmd.calls[1].opts.pattern, "star pattern dropped")
end

do
    setup("BufEnter   ")
    check_autocmd_events(1, { "BufEnter" })
    is_nil(mock.autocmd.calls[1].opts.pattern, "whitespace-only → no pattern")
end

-- ---------------------------------------------------------------
print("=== register_events: array of strings ===")

do
    setup({ "BufEnter", "BufLeave" })
    eq(#mock.autocmd.calls, 1, "single autocmd for both events")
    check_autocmd_events(1, { "BufEnter", "BufLeave" })
end

-- ---------------------------------------------------------------
print("=== on_event: special events with options ===")

do
    setup({ "BufEnter", "BufLeave" })
    local c = mock.autocmd.calls[1]
    eq(type(c.opts.group), "number", "group is set")
    not_nil(c.opts.callback, "callback registered")
end

-- ---------------------------------------------------------------
print("=== on_event: dispatch mechanism ===")

do
    local ev = fresh_event()
    ev.register_events("cid1", "BufEnter")
    ev.register_events("cid2", "BufEnter")
    ev.on_event(function(ids, _)
        mock.work_calls[#mock.work_calls + 1] = { ids = ids }
    end)

    eq(#mock.autocmd.calls, 1, "one autocmd")
    fire_autocmd(1, { event = "BufEnter" })
    eq(#mock.work_calls, 1, "work called once")
    local w = mock.work_calls[1]
    local found = {}
    for _, id in ipairs(w.ids) do found[id] = true end
    is_true(found.cid1, "cid1 dispatched")
    is_true(found.cid2, "cid2 dispatched")
    eq(#w.ids, 2, "both cids dispatched")
end

do
    local ev = fresh_event()
    ev.register_events("cid1", "User TestEvent")
    ev.on_event(function(ids, _)
        mock.work_calls[#mock.work_calls + 1] = { ids = ids }
    end)

    fire_autocmd(1, { match = "TestEvent" })
    eq(#mock.work_calls, 1, "user event dispatched")
    eq(mock.work_calls[1].ids[1], "cid1")
end

do
    local ev = fresh_event()
    ev.register_events("cid1", "InsertEnter *.lua")
    ev.on_event(function(ids, _)
        mock.work_calls[#mock.work_calls + 1] = { ids = ids }
    end)

    fire_autocmd(1, {})
    eq(#mock.work_calls, 1, "special event dispatched")
    eq(mock.work_calls[1].ids[1], "cid1")
end

do
    local ev = fresh_event()
    ev.register_events("cid1", "BufEnter")
    ev.register_events("cid1", "BufLeave")
    ev.on_event(function(ids, _)
        mock.work_calls[#mock.work_calls + 1] = { ids = ids }
    end)

    fire_autocmd(1, { event = "BufEnter" })
    eq(#mock.work_calls, 1, "work called once")
    eq(#mock.work_calls[1].ids, 1, "one unique cid")
end

-- ---------------------------------------------------------------
print("=== register_events: merging special events ===")

do
    local ev = fresh_event()
    ev.register_events("cid1", "BufEnter *.lua")
    ev.register_events("cid2", "BufEnter *.lua")
    ev.on_event(function() end)

    eq(#mock.autocmd.calls, 1, "merged into single autocmd")
    local c = mock.autocmd.calls[1]
    -- merging normalizes name to a list; just check it contains the name
    local names = type(c.events) == "string" and { c.events } or c.events
    is_true(names[1] == "BufEnter", "event name correct")
    eq(c.opts.pattern, "*.lua", "pattern preserved")
    not_nil(c.opts.callback)
end

do
    local ev = fresh_event()
    ev.register_events("cid1", "BufEnter *.lua")
    ev.register_events("cid2", "BufEnter *.py")
    ev.on_event(function() end)

    eq(#mock.autocmd.calls, 2, "two autocmds for different patterns")
end

-- ---------------------------------------------------------------
print("=== register_events: ++once modifier ===")

do
    setup("BufEnter ++once")
    local c = mock.autocmd.calls[1]
    eq(c.events, "BufEnter")
    eq(c.opts.once, true, "once=true for ++once")
    is_nil(c.opts.pattern, "no pattern")
end

do
    setup("BufEnter *.lua ++once")
    local c = mock.autocmd.calls[1]
    eq(c.events, "BufEnter")
    eq(c.opts.pattern, "*.lua")
    eq(c.opts.once, true, "once=true with pattern")
end

do
    -- ++once before pattern is NOT a modifier (must be behind patterns).
    -- Pattern area is comma-split only, so "++once *.lua" is one combined pattern.
    setup("BufEnter ++once *.lua")
    local c = mock.autocmd.calls[1]
    eq(c.events, "BufEnter")
    eq(c.opts.pattern, "++once *.lua", "space-separated tokens become single pattern")
    is_nil(c.opts.once, "once not set when ++once is before patterns")
end

do
    setup("User LazyLoad ++once")
    local c = mock.autocmd.calls[1]
    eq(c.events, "User")
    eq(c.opts.pattern, "LazyLoad")
    eq(c.opts.once, true, "once=true for user event")
end

do
    local ev = fresh_event()
    ev.register_events("cid1", "BufEnter *.lua ++once")
    ev.register_events("cid2", "BufEnter *.lua")
    ev.on_event(function() end)
    eq(#mock.autocmd.calls, 1, "++once and plain merge into one autocmd")
    local c = mock.autocmd.calls[1]
    eq(c.opts.once, true, "once propagates when any registration has it")
end

-- ---------------------------------------------------------------
print("=== register_events: edge cases ===")

do
    local ev = fresh_event()
    ev.register_events("cid1", nil)
    ev.on_event(function() end)
    eq(#mock.autocmd.calls, 0, "no autocmd for nil events")
end

do
    local ev = fresh_event()
    ev.register_events("cid1", { "", "BufEnter", "" })
    ev.on_event(function() end)
    check_autocmd_events(1, { "BufEnter" })
end

do
    local ev = fresh_event()
    ev.on_event(function() end)
    eq(#mock.autocmd.calls, 0, "no autocmds with no registrations")
end

-- ====================================================================
-- Summary
-- ====================================================================
restore_vim_api()

local ok = helper.summary()
os.exit(ok and 0 or 1)