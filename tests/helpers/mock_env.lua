--- Mock environment setup for integration tests.
--- Provides a full mock stack that isolates update.lua from real
--- Neovim dependencies while keeping core logic real.

local M = {}

--- Shared state tables (accessible by reference from preloaded mocks).
M.ManagedComps = {}
M.statusline_calls = {
    set_value = {},
    set_side_value = {},
    hide_segment = {},
    push = {},
}

--- All modules that need to be mocked via package.preload.
M.mock_modules = {
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

--- Modules that must be force-reloaded per test.
M.reload_modules = {
    "witch-line.engine.update",
}

function M.install()
    M.ManagedComps = {}
    M.statusline_calls = { set_value = {}, set_side_value = {}, hide_segment = {}, push = {} }

    package.preload["witch-line"] = function()
        return { user_config = { theme_aware = false } }
    end

    package.preload["witch-line.core.registry"] = function()
        local DepGraphKind = { Visible = 1, Event = 2, Timer = 3, All = 4 }
        return {
            DepGraphKind = DepGraphKind,
            ManagedComps = M.ManagedComps,
            register = function(id, comp)
                M.ManagedComps[id] = comp
                return comp
            end,
            get_comp = function(id) return M.ManagedComps[id] end,
            iterate_dependent_ids = function() return function() end end,
        }
    end

    package.preload["witch-line.engine.statusline"] = function()
        return {
            push = function(cid, text, winid)
                M.statusline_calls.push[#M.statusline_calls.push + 1] = {
                    cid = cid, text = text, winid = winid,
                }
            end,
            set_value = function(cid, value, hl_name, winid)
                M.statusline_calls.set_value[#M.statusline_calls.set_value + 1] = {
                    cid = cid, value = value, hl_name = hl_name, winid = winid,
                }
            end,
            set_side_value = function(cid, side, value, hl_name, force, winid)
                M.statusline_calls.set_side_value[#M.statusline_calls.set_side_value + 1] = {
                    cid = cid, side = side, value = value,
                    hl_name = hl_name, force = force, winid = winid,
                }
            end,
            hide_segment = function(cid, winid)
                M.statusline_calls.hide_segment[#M.statusline_calls.hide_segment + 1] = {
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
        return { register_events = function() end, on_event = function() end }
    end

    package.preload["witch-line.event.timer"] = function()
        return { register_timer = function() end, on_timer_trigger = function() end }
    end

    package.preload["witch-line.util.bitmask"] = function()
        return { is_marked = function() return false end, mark_bit = function() end }
    end

    package.preload["witch-line.util.notifier"] = function()
        return { info = function() end, error = function(msg) error(msg) end }
    end

    package.preload["witch-line.component"] = function()
        return setmetatable({}, { __index = function() return nil end })
    end
end

function M.uninstall()
    for _, name in ipairs(M.mock_modules) do
        package.preload[name] = nil
        package.loaded[name] = nil
    end
    for _, name in ipairs(M.reload_modules) do
        package.loaded[name] = nil
    end
end

function M.reset_calls()
    M.statusline_calls = { set_value = {}, set_side_value = {}, hide_segment = {}, push = {} }
end

--- Get the update module (force-reloaded).
---@return table update_mod
function M.get_update()
    package.loaded["witch-line.engine.update"] = nil
    return require("witch-line.engine.update")
end

--- Run update_comp on a component inside a session.
---@param update_mod table The update module.
---@param comp ManagedComponent Component to update.
---@param kind? number DepGraphKind.
---@return Session session
function M.run_update(update_mod, comp, kind)
    local session
    require("witch-line.core.session").with_session(function(s)
        session = s
        update_mod.update_comp(comp, s, kind or 1)
    end)
    return session
end

--- Find the set_value call for a component.
---@param cid string
---@return table|nil
function M.find_set_value(cid)
    for _, c in ipairs(M.statusline_calls.set_value) do
        if c.cid == cid then return c end
    end
    return nil
end

--- Find set_side_value calls for a component.
---@param cid string
---@return table|nil left, table|nil right
function M.find_side_values(cid)
    local left, right
    for _, c in ipairs(M.statusline_calls.set_side_value) do
        if c.cid == cid then
            if c.side == -1 then left = c end
            if c.side == 1 then right = c end
        end
    end
    return left, right
end

--- Register a component in ManagedComps.
---@param comp ManagedComponent
---@return ManagedComponent
function M.register(comp)
    M.ManagedComps[comp.id] = comp
    return comp
end

return M
