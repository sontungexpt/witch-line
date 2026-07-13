--- Mock environment setup for integration tests.
--- Provides a full mock stack that isolates update.lua from real
--- Neovim dependencies while keeping core logic real.

local M = {}

--- Shared state tables (accessible by reference from preloaded mocks).
M.ManagedComps = {}

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
    "witch-line.core.state",
}

function M.install()
    M.ManagedComps = {}

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
            push = function() end,
            set_value = function() end,
            set_side_value = function() end,
            hide_segment = function() end,
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

function M.reset_calls() end

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

--- Expand short hex colors (#aaa → #aaaaaa) for nvim_set_hl.
local function expand_hex(color)
    if type(color) ~= "string" then return color end
    if color:sub(1, 1) == "#" then
        local hex = color:sub(2)
        if #hex == 3 then
            local r, g, b = hex:sub(1, 1), hex:sub(2, 2), hex:sub(3, 3)
            return "#" .. r .. r .. g .. g .. b .. b
        elseif #hex ~= 6 then
            return nil
        end
    end
    return color
end

--- Strip witch-line-only fields (theme_aware) from style for nvim_set_hl.
local function strip_wl_fields(style)
    if not style then return nil end
    local clean = {}
    for k, v in pairs(style) do
        if k ~= "theme_aware" then
            clean[k] = expand_hex(v)
        end
    end
    return clean
end

--- Find the state for a component after update.
--- Returns a table compatible with the old statusline mock API:
--- { cid, value, hl_name } where hl_name is a generated highlight group name.
---@param cid CompId
---@return table|nil
function M.find_set_value(cid)
    local State = require("witch-line.core.state")
    local states = State.get_states()
    local state = states[cid]
    if state and state.value then
        local hl_name = "WL" .. (string.gsub(tostring(cid), "[^%w_]", ""))
        local style = state.style and state.style.style
        if style and type(style) == "table" and next(style) then
            vim.api.nvim_set_hl(0, hl_name, strip_wl_fields(style))
        elseif style == nil or (type(style) == "table" and not next(style)) then
            hl_name = nil
        end
        return { cid = cid, value = state.value, hl_name = hl_name, style = style }
    end
    return nil
end

--- Find side values from state.
--- Returns tables compatible with the old statusline mock API:
--- { side, value, hl_name } where hl_name is generated.
---@param cid CompId
---@return table|nil left, table|nil right
function M.find_side_values(cid)
    local State = require("witch-line.core.state")
    local states = State.get_states()
    local state = states[cid]
    if not state then return nil, nil end

    local base_hl = "WL" .. (string.gsub(tostring(cid), "[^%w_]", ""))
    local left, right
    if state.left then
        local left_style = state.left_style and state.left_style.style
        local left_hl_name
        if left_style == 0 then
            left_hl_name = base_hl
        elseif type(left_style) == "string" then
            left_hl_name = base_hl .. "left"
            vim.api.nvim_set_hl(0, left_hl_name, { link = left_style })
        elseif left_style and type(left_style) == "number" and left_style > 0 then
            left_hl_name = base_hl .. "left"
        elseif left_style and type(left_style) == "table" and next(left_style) then
            left_hl_name = base_hl .. "left"
            vim.api.nvim_set_hl(0, left_hl_name, strip_wl_fields(left_style))
        end
        left = { side = -1, value = state.left, hl_name = left_hl_name, style = left_style }
    end
    if state.right then
        local right_style = state.right_style and state.right_style.style
        local right_hl_name
        if right_style == 0 then
            right_hl_name = base_hl
        elseif type(right_style) == "string" then
            right_hl_name = base_hl .. "right"
            vim.api.nvim_set_hl(0, right_hl_name, { link = right_style })
        elseif right_style and type(right_style) == "number" and right_style > 0 then
            right_hl_name = base_hl .. "right"
        elseif right_style and type(right_style) == "table" and next(right_style) then
            right_hl_name = base_hl .. "right"
            vim.api.nvim_set_hl(0, right_hl_name, strip_wl_fields(right_style))
        end
        right = { side = 1, value = state.right, hl_name = right_hl_name, style = right_style }
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
