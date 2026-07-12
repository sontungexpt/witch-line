local  require =  require

local CompAPI = require("witch-line.core.comp.resolver")
local Proxy = require("witch-line.core.comp.proxy")

local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps

local M = {}

----------------------------------------------------------------------
-- CompState: allocated once per component, mutated in place.
----------------------------------------------------------------------

---@class HighlightState
---@field dirty? boolean
---@field style? HighlightStyle

--- @class CompState
--- @field hidden? boolean
--- @field click_handler? string
--- @field theme_aware_enabled? boolean
---
--- @field value? string
--- @field style? HighlightState
---
--- @field left? string
--- @field left_style? HighlightState
---
--- @field right? string
--- @field right_style? HighlightState


--- @type table<CompId, CompState>
local GlobalStates = {}

local WindowStateMT = {
    __index = GlobalStates,
}

---@type table<integer, table<CompId, CompState>>
local WindowStates = setmetatable({}, {
    __index = function(t, winid)
        local state = setmetatable({}, WindowStateMT)
        rawset(t, winid, state)
        return state
    end,
})

---@param cid CompId
---@param winid? integer
---@return CompState
local function ensure_state(cid, winid)
    local states
    if winid then
        states = WindowStates[winid]
    else
        states = GlobalStates
    end

    local state = states[cid]
    if state then
        return state
    end

    state = {}

    states[cid] = state
    return state
end


--- Update the style for a component.
--- @param comp ProxyComponent
--- @param dynamic_style HighlightStyle|nil
--- @param state CompState
--- @param session Session
local function update_style(comp, dynamic_style, state, session)
    local style, dynamic = CompAPI.style(
        comp,
        function(id)
            local parent = ManagedComps[id]
            return parent and Proxy.bind(parent, session)
        end,
        dynamic_style,
        state.theme_aware_enabled
    )

    local hl_state = state.style
    if hl_state == nil then
        state.style = {
            style = style,
            dirty = true,
        }
        return
    end

    if hl_state.style == style then
        hl_state.dirty = nil
        return
    end

    hl_state.style = style
    hl_state.dirty = dynamic
end

--- Update the style for a side of a component.
--- @param comp ProxyComponent
--- @param side "left" | "right"
--- @param state CompState
--- @param session Session
local function update_side_style(
    comp,
    side,
    state,
    session
)

    local main_hl_state = state.style

    local style, dynamic, inherited, is_sep_style = CompAPI.side_style(
        comp,
        side,
        main_hl_state and main_hl_state.style,
        state.theme_aware_enabled,
        session
    )

    local field = side .. "_style"
    local hl_state = state[field]
    if hl_state == nil then
        state[field] = { style = style, dirty = true }
        return
    end

    --- style not changed
    if hl_state.style == style then
        hl_state.dirty = nil
        return
    end

    hl_state.style = style
    hl_state.dirty = dynamic and (not is_sep_style or (main_hl_state and main_hl_state.dirty))
end

--- Update a component's state.  Mutates existing CompState in place.
--- @param comp ProxyComponent The component to update.
--- @param session Session The session to use for this update.
--- @param winid number The window ID to use for this update.
--- @return boolean hidden True if the component is hidden after update.
local update_comp = function(comp, session, winid)
    CompAPI.pre_update(comp, session)

    local cid = comp.id
    local state = ensure_state(cid, winid)

    local hidden = CompAPI.hidden(comp, session)

    if hidden then
        if comp.renderable then
            state.hidden = true
        end
    else
        local value, dynamic_style = CompAPI.evaluate(comp, session)

        if comp.renderable then
            if value == "" then
                hidden = true
                state.hidden = true
            else
                state.hidden = false
                state.value = value
                state.theme_aware_enabled = CompAPI.theme_aware(comp, session)

                update_style(
                    comp,
                    dynamic_style,
                    state,
                    session
                )

                -- Left separator
                local left = CompAPI.side(
                    comp,
                    "left",
                    function(id)
                        local parent = ManagedComps[id]
                        return parent and Proxy.bind(parent, session)
                    end,
                    session
                )

                if left then
                    state.left = left
                    update_side_style(comp, "left", state, session)
                end

                -- Right separator
                local right = CompAPI.side(
                    comp,
                    "right",
                    function(id)
                        local parent = ManagedComps[id]
                        return parent and Proxy.bind(parent, session)
                    end,
                    session
                )

                if right then
                    state.right = right
                    update_side_style(comp, "right", state, session)
                end

                -- Click handler
                if comp.on_click then
                    local click_manager = require("witch-line.event.click")
                    state.click_handler = "%@v:lua." .. click_manager.register(comp) .. "@"
                end
            end
        end
    end
    CompAPI.post_update(comp, session)
    return hidden
end

----------------------------------------------------------------------
-- Exports
----------------------------------------------------------------------

--- Get the state map for a window (or global if nil).
---@param winid? integer
---@return table<CompId, CompState>
M.get_states = function(winid)
    if winid then
        return WindowStates[winid]
    end
    return GlobalStates
end

M.update_comp = update_comp

return M
