local concat, type, rawget = table.concat, type, rawget

local api = vim.api
local
nvim_strwidth,
nvim_get_option_value,
nvim_set_option_value =
    api.nvim_strwidth,
    api.nvim_get_option_value,
    api.nvim_set_option_value

-- Lazy-loaded modules (self-replacing on first access)
local Highlight
Highlight = setmetatable({}, {
    __index = function(tbl, k)
        Highlight = require("witch-line.core.highlight")
        return Highlight[k]
    end
})

local is_marked, mark_bit
is_marked = function(...)
    is_marked = require("witch-line.utils.bitmask").is_marked
    return is_marked(...)
end
mark_bit = function(...)
    mark_bit = require("witch-line.utils.bitmask").mark_bit
    return mark_bit(...)
end

local M = {}

--- @class CompState
--- @field value? string
--- @field width? integer
--- @field left? string
--- @field left_width? integer
--- @field right? string
--- @field right_width? integer
--- @field click_handler? string
--- @field flex? integer

--- @alias CompStateMap table<CompId, CompState>

--- @class Statusline
--- @field states CompStateMap
--- @field order CompId[]
--- @field lit_count integer
--- @field flexs? {[1]: integer, [2]: CompId}[]

--- @type Statusline
local GlobalStatusline = {
    states = {},
    order = {},
    lit_count = 0,
}

--- @type table<integer, Statusline>
local Statusline = {}

local win_closed_auid
setmetatable(Statusline, {
    __index = function(t, winid)
        if winid == 0 then
            local active_win = api.nvim_get_current_win()
            return Statusline[active_win]
        end

        if not win_closed_auid then
            win_closed_auid = api.nvim_create_autocmd("WinClosed", {
                callback = function(e)
                    Statusline[tonumber(e.match)] = nil
                end,
            })
        end

        local new_statusline = setmetatable({
            lit_count = 0,
            states = setmetatable({}, { __index = GlobalStatusline.states }),
        }, { __index = GlobalStatusline })

        t[winid] = new_statusline
        return new_statusline
    end,
})

--- Get the Statusline for a given window.
--- Returns GlobalStatusline when `laststatus == 3` or `winid` is nil.
---@param winid? integer
---@return Statusline
local get_statusline = function(winid)
    local laststatus = nvim_get_option_value("laststatus", {})
    if laststatus == 3 or winid == nil then
        return GlobalStatusline
    end
    return Statusline[winid]
end

--- Collect and sort flexible components by descending flex value.
--- Cache is stored on the statusline itself and cleared when order changes.
---@param statusline Statusline
---@return {integer, CompId}[]  Sorted array of {slot_index, comp_id}.
local function get_flex_sorted(statusline)
    local flex_sorted = statusline.flexs
    if flex_sorted then
        return flex_sorted
    end

    local sorted, n = {}, 0
    local comps, slots = statusline.states, statusline.order
    for i = 1, #slots do
        local flex = comps[slots[i]].flex
        if flex then
            n = n + 1
            local l = n
            while l > 1 and flex > sorted[l - 1][1] do
                sorted[l] = sorted[l - 1]
                l = l - 1
            end
            sorted[l] = { flex, i, slots[i] }
        end
    end

    flex_sorted = {}
    for i = 1, n do
        local e = sorted[i]
        flex_sorted[i] = { e[2], e[3] }
    end

    statusline.flexs = flex_sorted
    return flex_sorted
end

--- Compute the total display width of a single component slot.
---@param comp_state CompState
---@return integer
local function compute_slot_width(comp_state)
    local width = comp_state.width or 0
    if width > 0 then
        width = width + (comp_state.left_width or 0) + (comp_state.right_width or 0)
    end
    return width
end

--- Compute the total width of all slots in a statusline.
---@param win_state Statusline
---@return integer
local function compute_statusline_width(win_state)
    local total, slots, comps = 0, win_state.order, win_state.states
    for i = 1, #slots do
        total = total + compute_slot_width(comps[slots[i]])
    end
    return total
end

--- Build the statusline string value from slot states.
--- Optionally skips hidden slots via bitmask.
---@param slots CompId[]
---@param state_map CompStateMap
---@param skip_mask? integer  Bitmask of slot indices to skip.
---@return string
local function build_value(slots, state_map, skip_mask)
    local out, n = {}, 0
    for i = 1, #slots do
        if not skip_mask or not is_marked(skip_mask, i - 1) then
            local state = state_map[slots[i]]
            local val = state.value or ""
            if val ~= "" then
                local click_handler = state.click_handler
                if click_handler then
                    n = n + 1
                    out[n] = click_handler
                end

                local left, right = state.left, state.right
                if left and left ~= "" then
                    n = n + 1
                    out[n] = left
                end

                n = n + 1
                out[n] = val

                if right and right ~= "" then
                    n = n + 1
                    out[n] = right
                end

                if click_handler then
                    n = n + 1
                    out[n] = "%X"
                end
            end
        end
    end
    local result = concat(out)
    return result ~= "" and result or " "
end

--- Render the statusline for a given window.
---
--- Handles flex-based truncation when the rendered content exceeds
--- the available window width.  Debounced via `render_debounce`.
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

    local statusline = GlobalStatusline
    if laststatus ~= 3 then
        winid = winid or api.nvim_get_current_win()
        statusline = Statusline[winid]
    end

    local comp_state = statusline.states
    local flex_list = get_flex_sorted(statusline)
    local current_flex = flex_list[1]

    if not current_flex then
        nvim_set_option_value("statusline", build_value(statusline.order, comp_state), { win = winid })
        return
    end

    local rendered_width = compute_statusline_width(statusline)
    local max_width = winid and api.nvim_win_get_width(winid) or nvim_get_option_value("columns", {})

    if rendered_width <= max_width then
        nvim_set_option_value("statusline", build_value(statusline.order, comp_state), { win = winid })
        return
    end

    local flex_idx, hidden_slots = 1, 0ULL
    repeat
        local slot_id, comp_id = current_flex[1], current_flex[2]
        hidden_slots = mark_bit(hidden_slots, slot_id - 1)
        rendered_width = rendered_width - compute_slot_width(comp_state[comp_id])
        flex_idx = flex_idx + 1
        current_flex = flex_list[flex_idx]
    until rendered_width <= max_width or not current_flex

    nvim_set_option_value("statusline", build_value(statusline.order, comp_state, hidden_slots), { win = winid })
end

--- Debounced version of `M.render` (80ms delay).
---@param ... any  Arguments forwarded to `M.render`.
M.render_debounce = function(...)
    M.render_debounce = require("witch-line.utils").debounce(M.render, 80)
    return M.render_debounce(...)
end

--- Push a component value onto the statusline order.
--- Generates a numeric id when `comp_id` is nil.
---@param comp_id? CompId
---@param value string
---@param winid? integer
---@return integer slot_index
M.push = function(comp_id, value, winid)
    local statusline = get_statusline(winid)
    local slots = rawget(statusline, "order")
    if not slots then
        slots = {}
        statusline.order = slots
    end

    local new_slots_size = #slots + 1

    if not comp_id then
        comp_id = statusline.lit_count + 1
        statusline.lit_count = comp_id
    end

    local state_map = statusline.states
    if not rawget(state_map, comp_id) then
        local width = value == "" and 0 or nvim_strwidth(value)
        state_map[comp_id] = { value = value, width = width }
    end
    slots[new_slots_size] = comp_id
    return new_slots_size
end

--- @param winid? integer
--- @param comp_id CompId
local function ensure_comp_state(winid, comp_id)
    local state_map = get_statusline(winid).states
    local state = rawget(state_map, comp_id) or {}
    state_map[comp_id] = state
    return state
end

local vim_resized_auid

--- @param comp_id CompId
--- @param priority integer
--- @param winid? integer
M.track_flexible = function(comp_id, priority, winid)
    get_statusline(winid).states[comp_id].flex = priority
    if not vim_resized_auid then
        vim_resized_auid = api.nvim_create_autocmd("VimResized", {
            callback = function()
                if get_flex_sorted(get_statusline(api.nvim_get_current_win()))[1] then
                    M.render_debounce()
                end
            end,
        })
    end
end

--- @param comp_id CompId
--- @param winid? integer
M.hide_segment = function(comp_id, winid)
    local state = ensure_comp_state(winid, comp_id)
    state.value = ""
    state.width = 0
end

--- @param comp_id CompId
--- @param value string
--- @param hl_name? string
--- @param winid? integer
M.set_value = function(comp_id, value, hl_name, winid)
    local state = ensure_comp_state(winid, comp_id)
    state.width = nvim_strwidth(value)
    state.value = Highlight.assign_highlight_name(value, hl_name)
end

--- @param comp_id CompId
--- @param new_hl_name string|nil
--- @param winid? integer
M.set_hl_name = function(comp_id, new_hl_name, winid)
    local state = ensure_comp_state(winid, comp_id)
    local curr_value = state.value
    state.value = curr_value and Highlight.replace_highlight_name(curr_value, new_hl_name, 1) or curr_value
end

--- @param comp_id CompId
--- @param shift_side -1|1
--- @param value string
--- @param hl_name? string
--- @param force? boolean
--- @param winid? integer
M.set_side_value = function(comp_id, shift_side, value, hl_name, force, winid)
    local state = ensure_comp_state(winid, comp_id)
    if shift_side == -1 then
        if force or not state.left then
            state.left_width = nvim_strwidth(value)
            state.left = Highlight.assign_highlight_name(value, hl_name)
        end
    else
        if force or not state.right then
            state.right_width = nvim_strwidth(value)
            state.right = Highlight.assign_highlight_name(value, hl_name)
        end
    end
end

--- @param comp_id CompId
--- @param shift_side -1|1
--- @param new_hl_name? string
--- @param winid? integer
M.set_side_hl_name = function(comp_id, shift_side, new_hl_name, winid)
    local state = ensure_comp_state(winid, comp_id)
    local curr_value = shift_side == -1 and state.left or state.right
    local new_value = curr_value and Highlight.replace_highlight_name(curr_value, new_hl_name, 1) or curr_value
    if shift_side == -1 then
        state.left = new_value
    else
        state.right = new_value
    end
end

--- @param comp_id CompId
--- @param click_handler string
--- @param force? boolean
--- @param winid? integer
M.set_click_handler = function(comp_id, click_handler, force, winid)
    local state = ensure_comp_state(winid, comp_id)
    if force or not state.click_handler then
        state.click_handler = "%@v:lua." .. click_handler .. "@"
    end
end

--- @param winid? integer
M.inspect = function(winid)
    require("witch-line.utils.notifier").info(vim.inspect(winid and Statusline[winid] or Statusline))
end

--- @param disabled_opts? UserConfig.Disabled
M.setup = function(disabled_opts)
    if type(disabled_opts) == "table" then
        local disabled_filetypes = type(disabled_opts.filetypes) == "table" and disabled_opts.filetypes
        local disabled_buftypes = type(disabled_opts.buftypes) == "table" and disabled_opts.buftypes

        if disabled_buftypes or disabled_filetypes then
            --- For automatically toggle `laststatus` based on buffer filetype and buftype.
            local user_laststatus = nvim_get_option_value("laststatus", {})
            api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
                callback = function(e)
                    local bufnr = e.buf
                    vim.schedule(function()
                        if not api.nvim_buf_is_valid(bufnr) then
                            return
                        end

                        local disabled = (
                                disabled_filetypes
                                and vim.list_contains(
                                    disabled_filetypes,
                                    nvim_get_option_value("filetype", { buf = bufnr })
                                )
                            )
                            or (disabled_buftypes and vim.list_contains(
                                disabled_buftypes,
                                nvim_get_option_value("buftype", { buf = bufnr })
                            ))
                            or false

                        local laststatus = nvim_get_option_value("laststatus", {})
                        if not disabled and laststatus == 0 then
                            nvim_set_option_value("laststatus", user_laststatus, {})
                            M.render_debounce() -- rerender statusline after enabling
                        elseif disabled and laststatus ~= 0 then
                            user_laststatus = laststatus
                            nvim_set_option_value("laststatus", 0, {})
                        else
                            return -- no change no need to redrawstatus
                        end

                        if api.nvim_get_mode().mode == "c" then
                            vim.cmd("redrawstatus")
                        end
                    end)
                end,
            })
        end
    end
end

return M
