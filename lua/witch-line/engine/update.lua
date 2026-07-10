local vim, type, ipairs, require = vim, type, ipairs, require
local api = vim.api

local Statusline = require("witch-line.engine.statusline")
local Highlight = require("witch-line.engine.highlight")
local CompAPI = require("witch-line.core.component_api")

local Registry = require("witch-line.engine.registry")
local ManagedComps = Registry.ManagedComps
local DepGraphKind = Registry.DepGraphKind
local iterate_dependent_ids = Registry.iterate_dependent_ids

local Resolver = require("witch-line.engine.resolver")
local Proxy = require("witch-line.engine.proxy")


local M = {}

local hide_single_comp
local update_single_comp
local update_comp
local update_comp_by_ids


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

---@type table<CompId, {[1]: any,[2]: integer}>
local inherited_style_cache = {}

local resolve_inherited_style = function(comp, initial_style, ...)
    local cid = comp.id
    local requires_recompute = initial_style == nil

    if not requires_recompute then
        local cache = inherited_style_cache[cid]
        if cache then
            return cache[1], false, cache[2]
        end
    end

    local merged_style = initial_style

    if merged_style == nil then
        merged_style = comp.style

        if type(merged_style) == "function" then
            requires_recompute = true
            merged_style = merged_style(comp, ...)
        end
    end

    local merged_parent_count = 0
    local seen = { [cid] = true }
    local parent_id = comp.___container

    while parent_id do
        if seen[parent_id] then
            break
        end
        seen[parent_id] = true

        local parent = ManagedComps[parent_id]
        if not parent then
            break
        end

        local parent_value = parent.style

        if type(parent_value) == "function" then
            requires_recompute = true
            parent_value = parent_value(parent, ...)
        end

        if parent_value ~= nil then
            merged_parent_count = merged_parent_count + 1
            merged_style = Highlight.merge_hl(
                merged_style,
                parent_value
            )
        end

        parent_id = parent.___container
    end

    if not requires_recompute then
        local cache = {
            merged_style,
            merged_parent_count,
        }

        inherited_style_cache[cid] = cache
    end

    return merged_style, requires_recompute, merged_parent_count
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
--- @param comp ProxyComponent  Component to update.
--- @param session Session          Session for dynamic style resolution.
--- @param theme_aware boolean Optional auto-theme flag.
--- @param override_style? CompStyle  Optional style override.
--- @return boolean updated  True if highlight changed, false if skipped.
--- @return CompStyle|nil style  The resolved style, or nil if unresolved.
local function update_comp_style(comp, session, theme_aware, override_style)
    local style, force, pcount = resolve_inherited_style(
        comp,
        Highlight.allowed_style(override_style) and override_style or nil
    )

    CompAPI.normalize_style(style, theme_aware)

    local hl_name = comp.___hl_name
    if hl_name then
        if force or override_style then
            return Highlight.highlight(hl_name, style), style
        end
    else
        if pcount > 0 then
            hl_name = Highlight.make_hl_name_from_id(comp.id)
        else
            local origin = Resolver.origin_component(comp, "style")
            if origin then
                hl_name = origin.___hl_name or Highlight.make_hl_name_from_id(origin.id)
                origin.___hl_name = hl_name
            else
                hl_name = Highlight.make_hl_name_from_id(comp.id)
            end
        end
        comp.___hl_name = hl_name
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
--- @param theme_aware boolean Flag to enable auto theme.
--- @return boolean updated Whether the side highlight was changed.
--- @return string|nil hl_name The dynamic highlight name as side.
local function update_comp_side_style(comp, session, side, main_style_updated, main_style, theme_aware)
    local side_style = CompAPI.side_style(comp, side)
    ---@cast side_style CompStyle|nil|SideStyleFunc|SepStyle

    local t = type(side_style)
    local hl_name_field = CompAPI.hl_name_field(side)
    local hl_name = comp[hl_name_field]
    local dynamic = t == "function"

    local SepStyle = CompAPI.SepStyle
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
                comp[hl_name_field] = comp.___hl_name
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
    comp[hl_name_field] = hl_name
    ---@diagnostic disable-next-line: param-type-mismatch
    return Highlight.highlight(hl_name, CompAPI.normalize_style(side_style, theme_aware)), nil
end

--- Hide a component's segment. Skips if not renderable.
---@param comp ManagedComponent
hide_single_comp = function(comp)
    if comp.renderable then
        Statusline.hide_segment(comp.id, comp.win_individual and api.nvim_get_current_win() or nil)
        comp.___hidden = true
    end
end

--- Update a component and its value in the statusline.
--- @param comp ProxyComponent The component to update.
--- @param session Session The session to use for this update.
--- @return boolean hidden True if the component is hidden after the update, false otherwise.
update_single_comp = function(comp, session)
    CompAPI.pre_update(comp, session)

    local hidden = CompAPI.hidden(comp, session)

    if hidden then
        hide_single_comp(comp)
    else
        --- We still update even the component is not renderable
        local value, returned_style = CompAPI.evaluate(comp, session)

        if comp.renderable then
            if value == "" then
                hide_single_comp(comp)
                hidden = true
            else
                local cid = comp.id
                local winid = comp.win_individual and api.nvim_get_current_win() or nil
                local theme_aware = CompAPI.theme_aware(comp, session)

                -- Main part
                -- Update style first to make sure comp.___hl_name is not nil
                local style_updated, style = update_comp_style(
                    comp,
                    session,
                    theme_aware,
                    comp.___use_returned_style ~= false and returned_style or nil
                )

                Statusline.set_value(cid, value, comp.___hl_name, winid)

                --- Left part
                -- local lval, lforce = Inherit.resolve_inherited(comp, "left", nil, nil, session)
                -- if lval then
                --     lval = format_side_value(lval, lforce)
                --     if lval then
                --         local updated, lhl_name =
                --             update_comp_side_style(comp, session, "left", style_updated, style, theme_aware)
                --         if not lhl_name then -- never meet dynamic hl_name
                --             Statusline.set_side_value(cid, -1, lval, comp.___left_hl_name, lforce, winid)
                --         else
                --             Statusline.set_side_value(
                --                 cid,
                --                 -1,
                --                 lval,
                --                 lhl_name or comp.___left_hl_name,
                --                 lforce or (updated and lhl_name ~= nil),
                --                 winid
                --             )
                --         end
                --     end
                -- end

                -- --- Right part
                -- local rval, rforce = Inherit.resolve_inherited(comp, "right", nil, nil, session)
                -- if rval then
                --     rval = format_side_value(rval, rforce)
                --     if rval then
                --         local updated, rhl_name =
                --             update_comp_side_style(comp, session, "right", style_updated, style, theme_aware)
                --         if not rhl_name then -- never meet dynamic hl_name
                --             Statusline.set_side_value(cid, 1, rval, comp.___right_hl_name, rforce, winid)
                --         else
                --             Statusline.set_side_value(
                --                 cid,
                --                 1,
                --                 rval,
                --                 rhl_name or comp.___right_hl_name,
                --                 rforce or (updated and rhl_name ~= nil),
                --                 winid
                --             )
                --         end
                --     end
                -- end

                if comp.on_click then
                    local click_manager = require("witch-line.event.click")
                    Statusline.set_click_handler(cid, click_manager.register(comp), nil, winid)
                end

                comp.___hidden = false -- Reset hidden state
            end
        end
    end

    CompAPI.post_update(comp, session)
    return hidden
end


--- Update a component and its dependencies recursively.
--- Hides Visible dependents when the component becomes hidden.
---@param comp ManagedComponent The component to update.
---@param session Session The session to update in.
---@param dep_graph_kind DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
update_comp = function(comp, session, dep_graph_kind, seen)
    seen = seen or {}
    local cid = comp.id
    if seen[cid] then return end
    seen[cid] = true

    local hidden = update_single_comp(Proxy.bind(comp, session), session)

    if hidden then
        for dep_id in iterate_dependent_ids(DepGraphKind.Visible, cid) do
            if not seen[dep_id] then
                seen[dep_id] = true
                local dep = ManagedComps[dep_id]
                if dep then
                    hide_single_comp(dep)
                end
            end
        end
    end

    --- Update dependent components based on the dependency graph kind.

    --- Special case: always walk All dependents first, then walk the requested kinds.
    for dep_id in iterate_dependent_ids(DepGraphKind.All, cid) do
        if not seen[dep_id] then
            local dep = ManagedComps[dep_id]
            if dep then
                update_comp(dep, session, DepGraphKind.All, seen)
            end
        end
    end
    --- @type DepGraphKind[]
    local kinds = type(dep_graph_kind) == "table" and dep_graph_kind or { dep_graph_kind }
    for i = 1, #kinds do
        local kind = kinds[i]
        if kind ~= DepGraphKind.All then
            for dep_id in iterate_dependent_ids(kind, cid) do
                if not seen[dep_id] then
                    local dep = ManagedComps[dep_id]
                    if dep then
                        update_comp(dep, session, kind, seen)
                    end
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
update_comp_by_ids = function(ids, session, dep_graph_kind, seen)
    seen = seen or {}
    for i = 1, #ids do
        local id = ids[i]
        if not seen[id] then
            local comp = ManagedComps[id]
            if comp then
                update_comp(comp, session, dep_graph_kind, seen)
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
        update_comp(comp, session,
            dep_graph_kind or { DepGraphKind.Event, DepGraphKind.Timer }, seen)
        if eager then
            Statusline.render()
        else
            Statusline.render_debounce()
        end
    end)
end

M.update_comp = update_comp
M.update_comp_by_ids = update_comp_by_ids
M.hide_component = hide_single_comp

return M
