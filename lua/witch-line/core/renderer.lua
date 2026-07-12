local type, concat = type, table.concat
local api = vim.api
local nvim_strwidth = api.nvim_strwidth
local nvim_get_option_value = api.nvim_get_option_value
local nvim_set_option_value = api.nvim_set_option_value

local Highlight = require("witch-line.core.highlight")
local CompAPI = require("witch-line.core.comp.resolver")
local Proxy = require("witch-line.core.comp.proxy")
local Resolver = require("witch-line.core.resolver")

local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps
local get_layout = Registry.get_layout

local State = require("witch-line.core.state")
local get_states = State.get_states

local BitMask = require("witch-line.util.bitmask")
local is_marked = BitMask.is_marked
local mark_bit = BitMask.mark_bit

local M = {}

----------------------------------------------------------------------
-- Highlight resolution (the only place this happens)
----------------------------------------------------------------------

--- Resolve the main highlight for a component.
--- Creates or reuses a highlight group, applies style.
---
--- @param comp ProxyComponent
--- @param theme_aware boolean
--- @param override_style? HighlightStyle
--- @param session Session
--- @return boolean applied  True if highlight was (re)applied.
--- @return HighlightStyle? style  The resolved style, or nil.
local function resolve_main_hl(comp, theme_aware, override_style, session)
    local style, dynamic, inherit_count = CompAPI.style(comp,
        function(id)
            local parent = ManagedComps[id]
            return parent and Proxy.bind(parent, session)
        end,
        Highlight.merge_hl,
        override_style,
        theme_aware
    )

    if not style then
        return false, nil
    end

    local hl_name = comp.___resolved_hl_name

    if hl_name then
        if dynamic or override_style then
            return Highlight.highlight(hl_name, style), style
        end
        return false, style
    end

    if inherit_count > 0 then
        hl_name = Highlight.make_hl_name_from_id(comp.id)
    else
        local origin = Resolver.resolve_field_owner(comp, "style")
        if origin and origin.id ~= comp.id then
            hl_name = origin.___resolved_hl_name
            if hl_name == nil then
                hl_name = Highlight.make_hl_name_from_id(origin.id)
                origin.___resolved_hl_name = hl_name
            end
        else
            hl_name = Highlight.make_hl_name_from_id(comp.id)
        end
    end

    comp.___resolved_hl_name = hl_name
    return Highlight.highlight(hl_name, style), style
end

--- Resolve a side highlight (left or right separator).
---
--- @param comp ManagedComponent
--- @param side "left"|"right"
--- @param main_hl_applied boolean
--- @param main_style? HighlightStyle
--- @param theme_aware boolean
--- @param session Session
--- @return boolean updated
--- @return string? hl_name  The resolved highlight name for the side.
local function resolve_side_hl(
    comp,
    side,
    main_hl_applied,
    main_style,
    theme_aware,
    session
)
    local hl_name_field = CompAPI.hl_name_field(side)
    local hl_name = comp[hl_name_field]

    if hl_name and not main_hl_applied then
        local raw_style = CompAPI.side_style(comp, side)
        if type(raw_style) ~= "function" then
            return false, nil
        end
    end

    local side_style, dynamic, inherited =
        CompAPI.side_style(comp, side, main_style, theme_aware, session)

    if inherited then
        if dynamic then
            return true, comp.___resolved_hl_name
        end
        if comp[hl_name_field] ~= comp.___resolved_hl_name then
            comp[hl_name_field] = comp.___resolved_hl_name
            return true, nil
        end
        return false, nil
    end

    if side_style == nil then
        return false, nil
    end

    if hl_name and not dynamic and not main_hl_applied then
        return false, nil
    end

    if hl_name == nil then
        hl_name = Highlight.make_hl_name_from_id(comp.id) .. side
        comp[hl_name_field] = hl_name
    end

    return Highlight.highlight(hl_name, side_style), nil
end

----------------------------------------------------------------------
-- Width computation
----------------------------------------------------------------------

--- Compute display width of a single component's full segment.
---@param s CompState
---@return integer
local function slot_width(s)
    local w = s.width or 0
    if w > 0 then
        w = w + (s.left_width or 0) + (s.right_width or 0)
    end
    return w
end

--- Compute total width of all visible slots in a layout.
---@param layout CompId[]
---@param states table<CompId, CompState>
---@return integer
local function total_width(layout, states)
    local sum = 0
    for i = 1, #layout do
        local s = states[layout[i]]
        if s and not s.hidden then
            sum = sum + slot_width(s)
        end
    end
    return sum
end

----------------------------------------------------------------------
-- Flex sorting
----------------------------------------------------------------------

--- Collect flex components sorted by descending priority.
---@param layout CompId[]
---@param states table<CompId, CompState>
---@return {[1]: integer, [2]: CompId}[]
local function sort_flex(layout, states)
    local sorted, n = {}, 0
    for i = 1, #layout do
        local s = states[layout[i]]
        if s and not s.hidden and s.flex then
            n = n + 1
            local l = n
            while l > 1 and s.flex > sorted[l - 1][1] do
                sorted[l] = sorted[l - 1]
                l = l - 1
            end
            sorted[l] = { s.flex, i, layout[i] }
        end
    end
    local result = {}
    for i = 1, n do
        local e = sorted[i]
        result[i] = { e[2], e[3] }
    end
    return result
end

----------------------------------------------------------------------
-- Build statusline string (resolves highlights, applies, concatenates)
----------------------------------------------------------------------

--- Build the statusline string from layout and states.
--- Resolves highlights for each component and applies them.
---@param layout CompId[]
---@param states table<CompId, CompState>
---@param session Session
---@param skip? integer  Bitmask of slot indices to skip.
---@return string
local function build_value(layout, states, session, skip)
    local out, n = {}, 0
    for i = 1, #layout do
        if not skip or not is_marked(skip, i - 1) then
            local comp_id = layout[i]
            local s = states[comp_id]
            if s and not s.hidden then
                local val = s.value
                if val and val ~= "" then
                    local comp = ManagedComps[comp_id]
                    if comp then
                        local theme_aware = CompAPI.theme_aware(comp, session)
                        local hl_applied, resolved_style = resolve_main_hl(comp, theme_aware, nil, session)
                        local hl_name = comp.___resolved_hl_name

                        -- Click handler
                        local ch = s.click_handler
                        if ch then
                            n = n + 1
                            out[n] = ch
                        end

                        -- Left separator
                        local left = s.left
                        if left and left ~= "" then
                            local _, lhl = resolve_side_hl(comp, "left", hl_applied, resolved_style, theme_aware, session)
                            n = n + 1
                            out[n] = Highlight.assign_highlight_name(left, lhl or hl_name)
                        end

                        -- Main value
                        n = n + 1
                        out[n] = Highlight.assign_highlight_name(val, hl_name)

                        -- Right separator
                        local right = s.right
                        if right and right ~= "" then
                            local _, rhl = resolve_side_hl(comp, "right", hl_applied, resolved_style, theme_aware, session)
                            n = n + 1
                            out[n] = Highlight.assign_highlight_name(right, rhl or hl_name)
                        end

                        -- Click handler end
                        if ch then
                            n = n + 1
                            out[n] = "%X"
                        end

                        -- Store widths for flex truncation
                        s.width = nvim_strwidth(val)
                        if left then s.left_width = nvim_strwidth(left) end
                        if right then s.right_width = nvim_strwidth(right) end
                    end
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

--- Render the statusline for a given window.
---@param winid? integer
---@param session Session
M.render = function(winid, session)
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

    -- Build once to resolve highlights and compute widths.
    local str = build_value(layout, states, session)

    -- Check if flex truncation is needed.
    local rendered = total_width(layout, states)
    local max_width = winid
        and api.nvim_win_get_width(winid)
        or nvim_get_option_value("columns", {})

    if rendered <= max_width then
        nvim_set_option_value("statusline", str, { win = winid })
        return
    end

    -- Flex truncation: rebuild skipping lowest-priority flex components.
    local flex_list = sort_flex(layout, states)
    local hidden_slots = 0ULL

    for i = 1, #flex_list do
        if rendered <= max_width then break end
        local slot_idx, comp_id = flex_list[i][1], flex_list[i][2]
        local s = states[comp_id]
        rendered = rendered - slot_width(s)
        hidden_slots = mark_bit(hidden_slots, slot_idx - 1)
    end

    str = build_value(layout, states, session, hidden_slots)
    nvim_set_option_value("statusline", str, { win = winid })
end

--- Debounced version of `M.render` (80ms delay).
---@param ... any  Arguments forwarded to `M.render`.
M.render_debounce = function(...)
    M.render_debounce = require("witch-line.util.debounce")(M.render, 80)
    return M.render_debounce(...)
end

return M
