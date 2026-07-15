local require = require

local Evaluator = require("witch-line.runtime.evaluator")
local StyleAPI = require("witch-line.runtime.style")
local Proxy = require("witch-line.runtime.proxy")

local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps

local State = require("witch-line.runtime.state")
local ensure_state = State.ensure_state

local M = {}

----------------------------------------------------------------------
-- Resolve parent helper (used by style phase)
----------------------------------------------------------------------

--- Build a resolve_parent function that returns ProxyComponent for a given id.
--- @param session Session
--- @return fun(id: CompId): ProxyComponent|nil
local function make_resolve_parent(session)
    return function(id)
        local parent = ManagedComps[id]
        return parent and Proxy.bind(parent, session)
    end
end

----------------------------------------------------------------------
-- Style phase helpers: resolve and store styles (no nvim_set_hl)
----------------------------------------------------------------------

--- Resolve and store the main highlight style in state.
--- @param comp ProxyComponent
--- @param resolve_parent fun(id: CompId): ProxyComponent|nil
--- @param dynamic_style HighlightStyle|nil Value-phase returned style override.
--- @param state CompState
--- @param session Session
local function resolve_main_style(comp, resolve_parent, dynamic_style, state, session)
    local style, dynamic = StyleAPI.resolve_main_style(
        comp,
        resolve_parent,
        dynamic_style,
        session
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

--- Resolve and store a side separator's style in state.
--- Converts SepStyle enums to HighlightStyle using the resolved main style.
--- @param comp ProxyComponent
--- @param side "left"|"right"
--- @param state CompState
--- @param session Session
local function resolve_side_style(comp, side, state, session)
    local raw_style, dynamic = StyleAPI.resolve_side_style(comp, side, session)

    --- Convert SepStyle enum to actual highlight style using main style
    local main_style = state.style and state.style.style
    local style
    if type(raw_style) == "number" then
        style = StyleAPI.convert_sep_style(raw_style, main_style)
    else
        style = raw_style
    end

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
    --- Mark dirty if dynamic, or if main style is dirty (separator depends on main)
    local main_dirty = state.style and state.style.dirty
    hl_state.dirty = dynamic or main_dirty
end

----------------------------------------------------------------------
-- Update pipeline
--
-- Phase 0: Lifecycle Prepare  — pre_update()
-- Phase 1: Visibility         — hidden()
-- Phase 2: Value              — update() + padding
-- Phase 3: Style              — style resolution (no nvim_set_hl)
-- Phase 4: Render             — highlight + output (renderer.lua)
----------------------------------------------------------------------

--- Update a component through Phases 0–3.  Phase 4 is handled by renderer.
--- @param comp ProxyComponent
--- @param session Session
--- @param winid? number
--- @return boolean hidden
M.update_comp = function(comp, session, winid)
    local cid = comp.id
    local state = ensure_state(cid, winid)

    ------------------------------------------------------------
    -- Phase 0: Lifecycle Prepare
    ------------------------------------------------------------
    Evaluator.pre_update(comp, session)

    ------------------------------------------------------------
    -- Phase 1: Visibility
    ------------------------------------------------------------
    local hidden = Evaluator.hidden(comp, session)

    if hidden then
        if comp.renderable then
            state.hidden = true
        end
        Evaluator.post_update(comp, session)
        return hidden
    end

    ------------------------------------------------------------
    -- Phase 2: Value
    ------------------------------------------------------------
    local value, dynamic_style = Evaluator.evaluate(comp, session)

    if not comp.renderable then
        Evaluator.post_update(comp, session)
        return hidden
    end

    if value == "" then
        state.hidden = true
        Evaluator.post_update(comp, session)
        return true
    end

    state.hidden = false
    state.value = value
    state.theme_aware_enabled = Evaluator.theme_aware(comp, session)

    ------------------------------------------------------------
    -- Phase 3: Style
    ------------------------------------------------------------
    local resolve_parent = make_resolve_parent(session)

    -- Main style
    resolve_main_style(comp, resolve_parent, dynamic_style, state, session)

    -- Left separator value + style
    local left = StyleAPI.resolve_side_value(comp, "left", resolve_parent, session)
    if left then
        state.left = left
        resolve_side_style(comp, "left", state, session)
    end

    -- Right separator value + style
    local right = StyleAPI.resolve_side_value(comp, "right", resolve_parent, session)
    if right then
        state.right = right
        resolve_side_style(comp, "right", state, session)
    end

    -- Click handler (stored for render phase)
    if comp.on_click then
        local click_manager = require("witch-line.event.click")
        state.click_handler = "%@v:lua." .. click_manager.register(comp) .. "@"
    end

    Evaluator.post_update(comp, session)
    return hidden
end

return M
