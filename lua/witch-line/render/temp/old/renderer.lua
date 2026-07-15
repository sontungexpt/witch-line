local concat = table.concat

local api = vim.api
local nvim_strwidth = api.nvim_strwidth
local nvim_get_option_value = api.nvim_get_option_value
local nvim_set_option_value = api.nvim_set_option_value

local Highlight = require("witch-line.render.highlight")

local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps
local Layout = require("witch-line.render.layout")
local get_layout = Layout.get_layout

local State = require("witch-line.runtime.state")
local get_states = State.get_states


local M = {}

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

local function make_hl_name_from_id(id)
    return "WL" .. (string.gsub(tostring(id), "[^%w_]", ""))
end

--- Wrap a string with Neovim statusline highlight escape sequences.
--- @param str string The string to wrap.
--- @param hl_name string|nil The highlight group name.
--- @return string
local function assign_highlight_name(str, hl_name)
    if hl_name == nil or str == "" then
        return str
    end
    return "%#" .. hl_name .. "#" .. str .. "%*"
end

--- Ensure a component has a resolved highlight group name.
--- Creates one from the component id if not yet assigned.
--- @param comp ManagedComponent
--- @return string hl_name
local function ensure_hl_name(comp)
    local hl_name = comp.___resolved_hl_name
    if hl_name then
        return hl_name
    end
    hl_name = make_hl_name_from_id(comp.id)
    comp.___resolved_hl_name = hl_name
    return hl_name
end

--- @param side "left"|"right"
--- @return string
local function hl_name_field(side)
    return side == "left" and "___left_hl_name" or "___right_hl_name"
end

--- Ensure a side (left/right) has a resolved highlight group name.
--- @param comp ManagedComponent
--- @param side "left"|"right"
--- @return string hl_name
local function ensure_side_hl_name(comp, side)
    local field = hl_name_field(side)
    local hl_name = comp[field]
    if hl_name then
        return hl_name
    end
    hl_name = make_hl_name_from_id(comp.id) .. side
    comp[field] = hl_name
    return hl_name
end




----------------------------------------------------------------------
-- Build statusline string from state
----------------------------------------------------------------------

--- Apply a dirty highlight from state and clear the dirty flag.
---@param hl_name string
---@param hl_state HighlightState
local function apply_if_dirty(hl_name, hl_state)
    if hl_state and hl_state.dirty then
        Highlight.highlight(hl_name, hl_state.style)
        hl_state.dirty = nil
    end
end

--- Build the statusline string by reading values and styles from state.
--- Applies dirty highlights as a side effect.
---@param layout CompId[]
---@param states table<CompId, CompState>
---@param skip? integer  Bitmask of slot indices to skip.
---@return string
local function build_value(layout, states, skip)
    local out, n = {}, 0
    for i = 1, #layout do
        local comp_id = layout[i]
        local s = states[comp_id]
        if s and not s.hidden then
            local val = s.value
            if val and val ~= "" then
                local comp = ManagedComps[comp_id]
                if comp then
                    local hl_name = ensure_hl_name(comp)

                    -- Apply main highlight if dirty
                    apply_if_dirty(hl_name, s.style)

                    -- Click handler
                    local ch = s.click_handler
                    if ch then
                        n = n + 1
                        out[n] = ch
                    end

                    -- Left separator
                    local left = s.left
                    if left and left ~= "" then
                        local lhs = s.left_style
                        local lhl
                        if lhs and lhs.style then
                            lhl = ensure_side_hl_name(comp, "left")
                            apply_if_dirty(lhl, lhs)
                        else
                            lhl = hl_name
                        end
                        n = n + 1
                        out[n] = assign_highlight_name(left, lhl)
                    end

                    -- Main value
                    n = n + 1
                    out[n] = assign_highlight_name(val, hl_name)

                    -- Right separator
                    local right = s.right
                    if right and right ~= "" then
                        local rhs = s.right_style
                        local rhl
                        if rhs and rhs.style then
                            rhl = ensure_side_hl_name(comp, "right")
                            apply_if_dirty(rhl, rhs)
                        else
                            rhl = hl_name
                        end
                        n = n + 1
                        out[n] = assign_highlight_name(right, rhl)
                    end

                    -- Click handler end
                    if ch then
                        n = n + 1
                        out[n] = "%X"
                    end

                    -- Widths for flex truncation
                    s.width = nvim_strwidth(val)
                    if left then s.left_width = nvim_strwidth(left) end
                    if right then s.right_width = nvim_strwidth(right) end
                end
            end
        end
    end
    local result = concat(out)
    return result ~= "" and result or " "
end

----------------------------------------------------------------------
-- Render
----------------------------------------------------------------------

---@param winid? integer
M.render = function(winid)
    local laststatus = nvim_get_option_value("laststatus", {})
    if
        (winid and not api.nvim_win_is_valid(winid))
        or laststatus == 0
        or (laststatus == 1 and #api.nvim_tabpage_list_wins(0) < 2)
    then
        return
    end

    local layout = get_layout(winid)
    local states = get_states(winid)

    local str = build_value(layout, states)
    nvim_set_option_value("statusline", str, { win = winid })
end

--- Debounced version of `M.render`.
M.render_debounce = require("witch-line.util.debounce")(M.render, 80)

return M
