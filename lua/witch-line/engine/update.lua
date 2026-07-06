local vim, type, ipairs, rawset, rawget, require = vim, type, ipairs, rawset, rawget, require
local api = vim.api

local Statusline = require("witch-line.engine.statusline")
local Highlight = require("witch-line.engine.highlight")
local ComponentApi = require("witch-line.core.component_api")

local Registry = require("witch-line.core.registry")
local DepGraphKind = Registry.DepGraphKind


local M = {}

local hide_component
local update_comp
local update_comp_graph
local update_comp_graph_by_ids

--- Hide a component's segment. Skips if not renderable.
---@param comp ManagedComponent
hide_component = function(comp)
    if rawget(comp, "___renderable") then
        Statusline.hide_segment(comp.id, comp.win_individual and api.nvim_get_current_win() or nil)
        rawset(comp, "___hidden", true)
    end
end

--- Normalise a side value. Dynamic non-strings become `""`, static non-strings become `nil`.
---@param val any
---@param is_func boolean
---@return string|nil
local format_side_value = function(val, is_func)
    if is_func then
        return type(val) ~= "string" and "" or val
    elseif type(val) ~= "string" then
        return nil
    end
    return val
end

--- Attach `auto_theme` to a style table if not already set.
---@param style CompStyle|nil
---@param enable_auto_theme boolean
---@return CompStyle|nil
local apply_auto_theme = function(style, enable_auto_theme)
    if type(style) == "table" then
        style.auto_theme = style.auto_theme or enable_auto_theme
    end
    return style
end

--- Update or apply a component's highlight style.
---
--- Resolves the final `style` (including overrides, inheritance, and references),
--- generates or reuses `___hl_name`, and applies it via `Highlight.highlight()`.
---
--- Logic:
--- 1. Merge local, inherited, and referenced styles using `Manager.dynamic_inherit()` and `Highlight.merge_hl()`.
--- 2. If `___hl_name` exists, reapply highlight if dynamic (`force`) or overridden (`override_style`).
--- 3. If `___hl_name` is missing, generate via `Highlight.make_hl_name_from_id()`:
---    - Assign own name if component has parents.
---    - Otherwise, reuse deepest referenced `___hl_name` if available.
--- 4. Apply highlight and update `___hl_name` cache.
---
--- @param comp ManagedComponent  Component to update.
--- @param session Session          Session for dynamic style resolution.
--- @param auto_theme boolean Optional auto-theme flag.
--- @param override_style? CompStyle  Optional style override.
--- @return boolean updated  True if highlight changed, false if skipped.
--- @return CompStyle|nil style  The resolved style, or nil if unresolved.
local function update_comp_style(comp, session, auto_theme, override_style)
    local override_style_t = type(override_style)
    local style, force, pcount = Registry.inherit(
        comp,
        "style",
        Highlight.merge_hl,
        (override_style_t == "table" or override_style_t == "string") and override_style or nil,
        session
    )

    style = apply_auto_theme(style, auto_theme)
    local hl_name = comp.___hl_name
    if hl_name then
        if force or override_style then
            return Highlight.highlight(hl_name, style), style
        end
    else
        if pcount > 0 then
            hl_name = Highlight.make_hl_name_from_id(comp.id)
        else
            local ref_comp = Registry.deepest_reference_component(comp, "style")
            if ref_comp then
                hl_name = ref_comp.___hl_name or Highlight.make_hl_name_from_id(ref_comp.id)
                rawset(ref_comp, "___hl_name", hl_name)
            else
                hl_name = Highlight.make_hl_name_from_id(comp.id)
            end
        end
        rawset(comp, "___hl_name", hl_name)
        return Highlight.highlight(hl_name, style), style
    end
    return false, style
end

--- Update and apply the highlight style for a component’s side (left or right).
---
--- This function determines and applies a side-specific highlight style
--- (e.g. separators between components in a statusline or UI block).
--- It reuses the main component style if possible or evaluates dynamic styles.
---
--- **Behavior:**
--- 1. If a custom highlight already exists and doesn’t need re-rendering, it returns early.
--- 2. If the side style is a function, it’s dynamically evaluated using `(comp, sid)`.
--- 3. If the side style is a numeric code (`SepStyle`), it derives a new highlight table
---    based on the main style:
---    - `SepFg`:  `{ fg = main_style.fg, bg = "NONE" }`
---    - `SepBg`:  `{ fg = main_style.bg, bg = "NONE" }`
---    - `Reverse`: `{ fg = main_style.bg, bg = main_style.fg }`
---    - `Inherited`: Inherit the component’s `___hl_name` directly.
---
--- **Return values:**
--- - `true`:  Style was updated and applied.
--- - `false`: No change was necessary or style was invalid.
---
--- @param comp ManagedComponent The component whose side style should be updated.
--- @param session Session The session used for dynamic style evaluation.
--- @param side "left"|"right" The side to update.
--- @param main_style_updated boolean Whether the main style was recently updated (forces re-render).
--- @param main_style? CompStyle The component’s main style used as reference.
--- @param auto_theme boolean Flag to enable auto theme.
--- @return boolean updated Whether the side highlight was changed.
--- @return string|nil hl_name The dynamic highlight name as side.
local function update_comp_side_style(comp, session, side, main_style_updated, main_style, auto_theme)
    local side_style = ComponentApi.side_style(comp, side)
    ---@cast side_style CompStyle|nil|SideStyleFunc|SepStyle

    local t = type(side_style)
    local hl_name_field = ComponentApi.hl_name_field(side)
    local hl_name = rawget(comp, hl_name_field)
    local dynamic = t == "function"

    local SepStyle = ComponentApi.SepStyle
    -- Return early if no need to update
    if
        not (
            hl_name == nil
            or dynamic
            or (
                main_style_updated
                and t == "number"
                and (
                    side_style == SepStyle.SepBg -- This is use frequently for separators
                    or side_style == SepStyle.SepFg
                    or side_style == SepStyle.Reverse
                    or side_style == SepStyle.Inherited
                )
            )
        )
    then
        return false, nil
    end

    if t == "function" then
        side_style = side_style(comp, session)
        t = type(side_style)
    end

    if t == "number" and main_style then
        if side_style == SepStyle.SepFg then
            side_style = {
                fg = main_style.fg or main_style.foreground,
                bg = "NONE",
            }
        elseif side_style == SepStyle.SepBg then
            side_style = {
                fg = main_style.bg or main_style.background,
                bg = "NONE",
            }
        elseif side_style == SepStyle.Reverse then
            side_style = {
                fg = main_style.bg or main_style.background,
                bg = main_style.fg or main_style.foreground,
            }
        elseif side_style == SepStyle.Inherited then
            if not dynamic then
                rawset(comp, hl_name_field, comp.___hl_name)
                return true, nil
            end
            -- dynamic hl name it's change between comp.___left_hl_name or comp.___hl_name continually
            return true, comp.___hl_name
        else
            --- invalid styles
            return false, nil
        end
    end
    -- Ensure highlight name exists and apply the new highlight
    hl_name = hl_name or Highlight.make_hl_name_from_id(comp.id) .. side
    rawset(comp, hl_name_field, hl_name)
    ---@diagnostic disable-next-line: param-type-mismatch
    return Highlight.highlight(hl_name, apply_auto_theme(side_style, auto_theme)), nil
end

--- Update a component and its value in the statusline.
--- @param comp ManagedComponent The component to update.
--- @param session Session The session to use for this update.
--- @return boolean hidden True if the component is hidden after the update, false otherwise.
update_comp = function(comp, session)
    local cid = comp.id
    ComponentApi.pre_update(comp, session)

    local hidden = ComponentApi.hidden(comp, session)

    if hidden then
        hide_component(comp)
    else
        local value, override_style = ComponentApi.evaluate(comp, session)

        -- A abstract component will not have indices
        -- It's just call the update function for other purpose and we not affect to the statusline
        -- So we just ignore it even the value is empty string
        if rawget(comp, "___renderable") then
            if value == "" then
                hide_component(comp)
                hidden = true
            else
                local winid = comp.win_individual and api.nvim_get_current_win() or nil
                local auto_theme = ComponentApi.auto_theme(comp, session)
                -- Main part
                -- Update style first to make sure comp.___hl_name is not nil
                local style_updated, style = update_comp_style(
                    comp,
                    session,
                    auto_theme,
                    comp.___use_returned_style ~= false and override_style or nil
                )

                Statusline.set_value(cid, value, comp.___hl_name, winid)

                --- Left part
                local lval, lforce = Registry.inherit(comp, "left", nil, nil, session)
                if lval then
                    lval = format_side_value(lval, lforce)
                    if lval then
                        local updated, lhl_name =
                            update_comp_side_style(comp, session, "left", style_updated, style, auto_theme)
                        if not lhl_name then -- never meet dynamic hl_name
                            Statusline.set_side_value(cid, -1, lval, comp.___left_hl_name, lforce, winid)
                        else
                            Statusline.set_side_value(
                                cid,
                                -1,
                                lval,
                                lhl_name or comp.___left_hl_name,
                                lforce or (updated and lhl_name ~= nil),
                                winid
                            )
                        end
                    end
                end

                --- Right part
                local rval, rforce = Registry.inherit(comp, "right", nil, nil, session)
                if rval then
                    rval = format_side_value(rval, rforce)
                    if rval then
                        local updated, rhl_name =
                            update_comp_side_style(comp, session, "right", style_updated, style, auto_theme)
                        if not rhl_name then -- never meet dynamic hl_name
                            Statusline.set_side_value(cid, 1, rval, comp.___right_hl_name, rforce, winid)
                        else
                            Statusline.set_side_value(
                                cid,
                                1,
                                rval,
                                rhl_name or comp.___right_hl_name,
                                rforce or (updated and rhl_name ~= nil),
                                winid
                            )
                        end
                    end
                end

                -- Allow to inherit on_click field
                if comp.on_click then
                    local click_manager = require("witch-line.event.click")
                    Statusline.set_click_handler(cid, click_manager.register(comp), nil, winid)
                end

                rawset(comp, "___hidden", false) -- Reset hidden state
            end
        end
    end

    ComponentApi.post_update(comp, session)
    return hidden
end


--- Update a component and its dependencies recursively.
--- Hides Visible dependents when the component becomes hidden.
---@param comp ManagedComponent The component to update.
---@param session Session The session to update in.
---@param dep_graph_kind DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
update_comp_graph = function(comp, session, dep_graph_kind, seen)
    seen = seen or {}
    local cid = comp.id
    if seen[cid] then return end
    seen[cid] = true

    local hidden = update_comp(comp, session)

    if hidden then
        for dep_id in Registry.iterate_dependent_ids(DepGraphKind.Visible, cid) do
            seen[dep_id] = true
            local dep = Registry.get_comp(dep_id)
            if dep then hide_component(dep) end
        end
    end


    if type(dep_graph_kind) == "table" then
        for _, kind in ipairs(dep_graph_kind) do
            for dep_id in Registry.iterate_dependent_ids(kind, cid) do
                if not seen[dep_id] then
                    local dep = Registry.get_comp(dep_id)
                    if dep then
                        update_comp_graph(dep, session, kind, seen)
                    end
                end
            end
        end
    elseif dep_graph_kind then
        for dep_id in Registry.iterate_dependent_ids(dep_graph_kind, cid) do
            if not seen[dep_id] then
                local dep = Registry.get_comp(dep_id)
                if dep then
                    update_comp_graph(dep, session, dep_graph_kind, seen)
                end
            end
        end
    end
end


--- Update multiple components by IDs through the dep graph.
---@param ids CompId[] The IDs of the components to update.
---@param session Session The session to update in.
---@param dep_graph_kind DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
update_comp_graph_by_ids = function(ids, session, dep_graph_kind, seen)
    seen = seen or {}
    for _, id in ipairs(ids) do
        if not seen[id] then
            local comp = Registry.get_comp(id)
            if comp then
                update_comp_graph(comp, session, dep_graph_kind, seen)
            end
        end
    end
end

--- Update a component and its deps in a new session, then debounce render.
---@param comp ManagedComponent The component to update.
---@param eager? boolean Whether to render immediately instead of debouncing.
---@param dep_graph_kind? DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
M.request_update_comp_graph = function(comp, eager, dep_graph_kind, seen)
    require("witch-line.core.session").with_session(function(session)
        update_comp_graph(comp, session, dep_graph_kind or { DepGraphKind.Event, DepGraphKind.Timer }, seen)
        if eager then
            Statusline.render()
        else
            Statusline.render_debounce()
        end
    end)
end

--- Update a component and its deps in a new session, then debounce render.
---@param comp ManagedComponent The component to update.
---@param eager? boolean Whether to render immediately instead of debouncing.
---@param dep_graph_kind? DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
M.request_update_comp_graph = function(comp, eager, dep_graph_kind, seen)
    require("witch-line.core.session").with_session(function(session)
        update_comp_graph(comp, session,
            dep_graph_kind or { DepGraphKind.Event, DepGraphKind.Timer }, seen)
        if eager then
            Statusline.render()
        else
            Statusline.render_debounce()
        end
    end)
end

M.update_comp = update_comp
M.update_comp_graph = update_comp_graph
M.update_comp_graph_by_ids = update_comp_graph_by_ids
M.hide_component = hide_component

return M
