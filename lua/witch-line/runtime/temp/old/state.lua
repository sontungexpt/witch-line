local M = {}


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
M.ensure_state = function(cid, winid)
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

--- Get the state map for a window (or global if nil).
---@param winid? integer
---@return table<CompId, CompState>
M.get_states = function(winid)
    if winid then
        return WindowStates[winid]
    end
    return GlobalStates
end

return M
