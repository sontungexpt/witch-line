local vim, type, ipairs, require = vim, type, ipairs, require
local api = vim.api

local Statusline = require("witch-line.engine.statusline")
local Highlight = require("witch-line.engine.highlight")
local CompAPI = require("witch-line.core.comp.resolver")

local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps
local DepGraphKind = Registry.DepGraphKind
local iterate_dependent_ids = Registry.iterate_dependent_ids

local Resolver = require("witch-line.core.resolver")
local Proxy = require("witch-line.core.comp.proxy")


local M = {}

local hide_single_comp
local update_single_comp
local update_comp
local update_comp_by_ids

--- Update or apply a component's highlight style.
---
--- Resolves the final `style` (including overrides, inheritance, and references),
--- generates or reuses `___resolved_hl_name`, and applies it via `Highlight.highlight()`.
---
--- Logic:
--- 1. Merge local, inherited, and referenced styles using `Manager.dynamic_inherit()` and `Highlight.merge_hl()`.
--- 2. If `___resolved_hl_name` exists, reapply highlight if dynamic (`force`) or overridden (`override_style`).
--- 3. If `___resolved_hl_name` is missing, generate via `Highlight.make_hl_name_from_id()`:
---    - Assign own name if component has parents.
---    - Otherwise, reuse deepest referenced `___resolved_hl_name` if available.
--- 4. Apply highlight and update `___resolved_hl_name` cache.
---
--- @param comp ProxyComponent  Component to update.
--- @param theme_aware boolean Optional auto-theme flag.
--- @param override_style? CompStyle  Optional style override.
--- @param session Session  Session for dynamic style resolution.
--- @return boolean updated  True if highlight changed, false if skipped.
--- @return CompStyle|nil style  The resolved style, or nil if unresolved.
local function update_comp_style(comp, theme_aware, override_style, session)
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

    -- Existing highlight name.
    if hl_name then
        if dynamic or override_style then
            return Highlight.highlight(hl_name, style), style
        end

        return false, style
    end

    -- Component inherits from parent, so it owns a unique highlight.
    if inherit_count > 0 then
        hl_name = Highlight.make_hl_name_from_id(comp.id)
    else
        local origin = Resolver.resolve_field_owner(comp, "style")
        if origin == nil then
            return false, nil
        end

        -- Reference component without local ownership.
        if origin.id ~= comp.id then
            hl_name = origin.___resolved_hl_name
            if hl_name == nil then
                hl_name = Highlight.make_hl_name_from_id(origin.id)
                origin.___resolved_hl_name = hl_name
            end
        else
            -- Normal component.
            hl_name = Highlight.make_hl_name_from_id(comp.id)
        end
    end

    comp.___resolved_hl_name = hl_name

    return Highlight.highlight(hl_name, style), style
end

--- Update and apply the highlight style for a component side.
---
--- The function is intentionally lazy:
--- - Avoids resolving side style when existing highlight can be reused.
--- - Evaluates dynamic styles only when required.
--- - Generates highlight names only on first use.
---
---@param comp ManagedComponent Component whose side is updated.
---@param session Session Runtime context.
---@param side "left"|"right" Side to update.
---@param main_hl_applied boolean Whether main highlight changed.
---@param main_style? CompStyle Main resolved style.
---@param theme_aware boolean Enable theme adaptation.
---@return boolean updated Whether highlight changed.
---@return string|nil dynamic_hl Dynamic inherited highlight.
local function update_comp_side_style(
    comp,
    side,
    main_hl_applied,
    main_style,
    theme_aware,
    session
)
    local hl_name_field = CompAPI.hl_name_field(side)
    local hl_name = comp[hl_name_field]


    ----------------------------------------------------------------------
    -- Fast path:
    -- Existing side highlight can be reused.
    --
    -- Static side styles only need updating when main highlight changes,
    -- because separator styles may depend on main fg/bg.
    ----------------------------------------------------------------------
    if hl_name and not main_hl_applied then
        local raw_style = CompAPI.side_style(comp, side)

        -- Most common case:
        -- static custom highlight already exists.
        if type(raw_style) ~= "function" then
            return false, nil
        end
    end


    ----------------------------------------------------------------------
    -- Resolve side style lazily.
    -- Only executed when update is actually required.
    ----------------------------------------------------------------------
    local side_style, dynamic, inherited =
        CompAPI.resolved_side_style(
            comp,
            side,
            main_style,
            theme_aware,
            session
        )


    ----------------------------------------------------------------------
    -- Inherited side:
    -- Reuse component main highlight directly.
    ----------------------------------------------------------------------
    if inherited then
        -- Dynamic inherited highlight can change every render.
        if dynamic then
            return true, comp.___resolved_hl_name
        end

        if comp[hl_name_field] ~= comp.___resolved_hl_name then
            comp[hl_name_field] = comp.___resolved_hl_name
            return true, nil
        end

        return false, nil
    end


    ----------------------------------------------------------------------
    -- Invalid / disabled side.
    ----------------------------------------------------------------------
    if side_style == nil then
        return false, nil
    end


    ----------------------------------------------------------------------
    -- Static highlight reuse.
    -- After resolving we know whether it is dynamic.
    ----------------------------------------------------------------------
    if hl_name and not dynamic and not main_hl_applied then
        return false, nil
    end


    ----------------------------------------------------------------------
    -- Allocate highlight name only once.
    ----------------------------------------------------------------------
    if hl_name == nil then
        hl_name = Highlight.make_hl_name_from_id(comp.id) .. side
        comp[hl_name_field] = hl_name
    end


    ----------------------------------------------------------------------
    -- Apply highlight.
    ----------------------------------------------------------------------
    return Highlight.highlight(
        hl_name,
        side_style
    ), nil
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
        local value, dynamic_style = CompAPI.evaluate(comp, session)

        if comp.renderable then
            if value == "" then
                hide_single_comp(comp)
                hidden = true
            else
                local cid = comp.id
                local winid = comp.win_individual and api.nvim_get_current_win() or nil
                local theme_aware = CompAPI.theme_aware(comp, session)

                -- Main part
                -- Update style first to make sure comp.___resolved_hl_name is not nil
                local hl_applied, resolved_style = update_comp_style(
                    comp,
                    theme_aware,
                    dynamic_style,
                    session
                )

                Statusline.set_value(cid, value, comp.___resolved_hl_name, winid)

                --- Left part
                local lval, lforce = CompAPI.side(
                    comp,
                    "left",
                    function(id)
                        local parent = ManagedComps[id]
                        return parent and Proxy.bind(parent, session)
                    end,
                    session
                )

                if lval then
                    local updated, lhl_name =
                        update_comp_side_style(comp, "left", hl_applied, resolved_style, theme_aware, session)
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

                --- Right part
                local rval, rforce = CompAPI.side(
                    comp,
                    "right",
                    function(id)
                        local parent = ManagedComps[id]
                        return parent and Proxy.bind(parent, session)
                    end,
                    session
                )
                if rval then
                    local updated, rhl_name =
                        update_comp_side_style(comp, "right", hl_applied, resolved_style, theme_aware, session)
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
