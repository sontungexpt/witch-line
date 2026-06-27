local vim, type, ipairs, rawset, rawget, require = vim, type, ipairs, rawset, rawget, require
local api = vim.api

local Statusline = require("witch-line.core.statusline")
local Event = require("witch-line.core.manager.event")
local Timer = require("witch-line.core.manager.timer")

local Registry = require("witch-line.core.manager.registry")
local is_existed = Registry.is_existed
local DepGraphKind = Registry.DepGraphKind
local require_by_id = Registry.require_by_id
local link_dependency = Registry.link_dependency

-- Lazy-loaded modules
local Highlight
Highlight = setmetatable({}, {
    __index = function(tbl, k)
        Highlight = require("witch-line.core.highlight")
        return Highlight[k]
    end
})

local ComponentEvaluator
ComponentEvaluator = setmetatable({}, {
    __index = function(tbl, k)
        ComponentEvaluator = require("witch-line.core.component.evaluator")
        return ComponentEvaluator[k]
    end
})

local M = {}


--- Forwards definition functions

local register_dependency_source
local register_combined_component
local register_component
local register_literal_comp

local hide_component
local update_comp
local update_comp_graph
local update_comp_graph_by_ids


--- Hide a component's segment. Skips if not renderable.
---@param comp ManagedComponent
hide_component = function(comp)
    if rawget(comp, "_renderable") then
        Statusline.hide_segment(comp.id, comp.win_individual and api.nvim_get_current_win() or nil)
        rawset(comp, "_hidden", true)
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
--- generates or reuses `_hl_name`, and applies it via `Highlight.highlight()`.
---
--- Logic:
--- 1. Merge local, inherited, and referenced styles using `Manager.dynamic_inherit()` and `Highlight.merge_hl()`.
--- 2. If `_hl_name` exists, reapply highlight if dynamic (`force`) or overridden (`override_style`).
--- 3. If `_hl_name` is missing, generate via `Highlight.make_hl_name_from_id()`:
---    - Assign own name if component has parents.
---    - Otherwise, reuse deepest referenced `_hl_name` if available.
--- 4. Apply highlight and update `_hl_name` cache.
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
    local hl_name = comp._hl_name
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
                hl_name = ref_comp._hl_name or Highlight.make_hl_name_from_id(ref_comp.id)
                rawset(ref_comp, "_hl_name", hl_name)
            else
                hl_name = Highlight.make_hl_name_from_id(comp.id)
            end
        end
        rawset(comp, "_hl_name", hl_name)
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
---    - `Inherited`: Inherit the component’s `_hl_name` directly.
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
    local side_style = ComponentEvaluator.side_style(comp, side)
    ---@cast side_style CompStyle|nil|SideStyleFunc|SepStyle

    local t = type(side_style)
    local hl_name_field = ComponentEvaluator.hl_name_field(side)
    local hl_name = rawget(comp, hl_name_field)
    local dynamic = t == "function"

    local SepStyle = ComponentEvaluator.SepStyle
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
                rawset(comp, hl_name_field, comp._hl_name)
                return true, nil
            end
            -- dynamic hl name it's change between comp._left_hl_name or comp._hl_name continually
            return true, comp._hl_name
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
    ComponentEvaluator.pre_update(comp, session)

    --- This part is manage by DepStoreKey.Display so we don't need to reference to the field of other component
    local min_screen_width = ComponentEvaluator.min_screen_width(comp, session)

    local hidden = min_screen_width and api.nvim_get_option_value("columns", {}) < min_screen_width
        or ComponentEvaluator.hidden(comp, session)

    if hidden then
        hide_component(comp)
    else
        local value, override_style = ComponentEvaluator.evaluate(comp, session)

        -- A abstract component will not have indices
        -- It's just call the update function for other purpose and we not affect to the statusline
        -- So we just ignore it even the value is empty string
        if rawget(comp, "_renderable") then
            if value == "" then
                hide_component(comp)
                hidden = true
            else
                local winid = comp.win_individual and api.nvim_get_current_win() or nil
                local auto_theme = ComponentEvaluator.auto_theme(comp, session)
                -- Main part
                -- Update style first to make sure comp._hl_name is not nil
                local style_updated, style = update_comp_style(
                    comp,
                    session,
                    auto_theme,
                    comp._use_returned_style ~= false and override_style or nil
                )

                Statusline.set_value(cid, value, comp._hl_name, winid)

                --- Left part
                local lval, lforce = Registry.inherit(comp, "left", nil, nil, session)
                if lval then
                    lval = format_side_value(lval, lforce)
                    if lval then
                        local updated, lhl_name =
                            update_comp_side_style(comp, session, "left", style_updated, style, auto_theme)
                        if not lhl_name then -- never meet dynamic hl_name
                            Statusline.set_side_value(cid, -1, lval, comp._left_hl_name, lforce, winid)
                        else
                            Statusline.set_side_value(
                                cid,
                                -1,
                                lval,
                                lhl_name or comp._left_hl_name,
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
                            Statusline.set_side_value(cid, 1, rval, comp._right_hl_name, rforce, winid)
                        else
                            Statusline.set_side_value(
                                cid,
                                1,
                                rval,
                                rhl_name or comp._right_hl_name,
                                rforce or (updated and rhl_name ~= nil),
                                winid
                            )
                        end
                    end
                end

                -- Allow to inherit on_click field
                if comp.on_click then
                    local click_manager = require("witch-line.core.manager.click")
                    Statusline.set_click_handler(cid, click_manager.register(comp), nil, winid)
                end

                rawset(comp, "_hidden", false) -- Reset hidden state
            end
        end
    end

    ComponentEvaluator.post_update(comp, session)
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
        for dep_id in Registry.iterate_dependents(DepGraphKind.Visible, cid) do
            seen[dep_id] = true
            local dep = Registry.get_comp(dep_id)
            if dep then hide_component(dep) end
        end
    end


    if type(dep_graph_kind) == "table" then
        for _, kind in ipairs(dep_graph_kind) do
            for dep_id in Registry.iterate_dependents(kind, cid) do
                if not seen[dep_id] then
                    local dep = Registry.get_comp(dep_id)
                    if dep then
                        update_comp_graph(dep, session, kind, seen)
                    end
                end
            end
        end
    elseif dep_graph_kind then
        for dep_id in Registry.iterate_dependents(dep_graph_kind, cid) do
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

--- Link a component's dependency to source IDs.
--- Auto-loads any source that is not yet registered.
---@param kind DepGraphKind
---@param ids CompId|CompId[]
---@param dependent_id CompId
local function register_dependency_links(kind, ids, dependent_id)
    local ids_type = type(ids)
    if ids_type == "table" then
        for _, id in ipairs(ids) do
            link_dependency(kind, id, dependent_id)

            if not is_existed(id) then
                local dep = require_by_id(id)
                if dep then
                    register_dependency_source(dep)
                end
            end
        end
    elseif ids_type == "string" then
        link_dependency(kind, ids, dependent_id)
        if not is_existed(ids) then
            local dep = require_by_id(ids)
            if dep then
                register_dependency_source(dep)
            end
        end
    end
end

--- Bind timers, events, screen-width, and win-individual triggers.
--- @param cid CompId
---@param comp ManagedComponent
local function bind_update_conditions(cid, comp)
    local cid = rawget(comp, "id")

    local timing = rawget(comp, "timing")
    if timing then
        Timer.register_timer(cid, timing)
    end

    local events = rawget(comp, "events")
    if events then
        Event.register_events(cid, events)
    end

    if rawget(comp, "min_screen_width") then
        Event.register_vim_resized(cid)
    end

    if rawget(comp, "win_individual") then
        Event.register_win_resized(cid)
    end
end

--- Register a component: wire triggers, inherit/ref meta, dep links.
---@param comp Component|table
---@return ManagedComponent
register_dependency_source = function(comp)
    if comp._loaded then
        --- @cast comp ManagedComponent
        return comp
    end

    local path = comp[0]
    if type(path) == "string" then
        local c = require_by_id(path)
        if c then
            comp = require("witch-line.core.component.override")(c, comp)
        end
    end

    local cid, managed_comp = Registry.register(comp)
    rawset(managed_comp, "_loaded", true)

    -- Use rawget to avoid triggering __index, which would recurse
    -- through lookup_plain_value → find_raw_value and crash when
    -- the component lacks a raw `id` field.
    local init_fn = rawget(managed_comp, "init")
    if type(init_fn) == "function" then
        init_fn(managed_comp)
    end

    local ref = rawget(managed_comp, "ref")
    if type(ref) == "table" then
        register_dependency_links(DepGraphKind.Event, ref.events, cid)
        register_dependency_links(DepGraphKind.Timer, ref.timing, cid)
        register_dependency_links(DepGraphKind.Visible, ref.hidden, cid)
        register_dependency_links(DepGraphKind.Visible, ref.min_screen_width, cid)
    end

    local inherit = rawget(managed_comp, "inherit")
    if inherit then
        register_dependency_links(DepGraphKind.Event, inherit, cid)
        register_dependency_links(DepGraphKind.Timer, inherit, cid)
        register_dependency_links(DepGraphKind.Visible, inherit, cid)
    end

    bind_update_conditions(cid, managed_comp)

    if rawget(managed_comp, "lazy") == false then
        Registry.mark_emergency(cid)
    end

    return managed_comp
end

--- Push component to the segment list and mark renderable.
--- Skips components without an `update` field.
---@param comp ManagedComponent
---@param winid integer|nil  Window-local list when set.
local build_indices = function(comp, winid)
    local update = rawget(comp, "update")
    if not update then
        return
    end

    local cid = comp.id

    Statusline.push(cid, "", winid)

    local flexible = rawget(comp, "flexible")
    if flexible then
        Statusline.track_flexible(cid, flexible)
    end
    rawset(comp, "_renderable", true)
end

--- @class UnprocessedRecursiveManagedComponent : ManagedComponent
--- @field [integer] CombinedComponent

--- Register a component: resolve, override, initialize, index.
--- Skips list-like tables (combined parent — children handled by caller).
---@param comp Component
---@param parent_id CompId|nil
---@param winid integer|nil  When set, marks window-local and pushes to the win-specific index.
---@return UnprocessedRecursiveManagedComponent
register_component = function(comp, parent_id, winid)
    if comp._loaded then
        --- @cast comp UnprocessedRecursiveManagedComponent
        build_indices(comp, winid)
        return comp
    end

    if not vim.islist(comp) then
        if winid then
            rawset(comp, "win_individual", true)
        end

        comp = register_dependency_source(comp)

        build_indices(comp, winid)
    end

    --- @cast comp UnprocessedRecursiveManagedComponent
    return comp
end

--- Push a literal string onto the statusline segment list.
--- Empty strings are silently ignored.
---@param comp string
---@param win_id integer|nil  Window-local segment list when set.
---@return string  The input string.
register_literal_comp = function(comp, win_id)
    if comp ~= "" then
        Statusline.push(nil, comp, win_id)
    end
    return comp
end

--- Register a combined component tree: parent first, then children recursively.
--- Strings resolve via `Component.require_by_id` or pushed as literal text.
---@param comp CombinedComponent
---@param parent_id CompId|nil
---@param winid integer|nil  Window-local statusline window id.  Pass nil for global.
---@return ManagedComponent|string|nil  The registered component or literal string.
register_combined_component = function(comp, parent_id, winid)
    local kind = type(comp)
    local managed_comp
    if kind == "string" then
        local c = require_by_id(comp)
        if not c then
            return register_literal_comp(comp, winid)
        end
        managed_comp = register_component(c, parent_id, winid)
    elseif kind == "table" and next(comp) then
        managed_comp = register_component(comp, parent_id, winid)
    else
        error("Invalid component type: " .. kind)
        return nil
    end

    for i, child in ipairs(managed_comp) do
        register_combined_component(child, managed_comp.id, winid)
        rawset(managed_comp, i, nil)
    end
    return managed_comp
end

--- Initialise global components, per-window components, event/timer handlers,
--- and emergency components.
---@param statusline UserConfig.Statusline
M.setup = function(statusline)
    register_combined_component(statusline.global)

    if statusline.win then
        local seen = {}
        api.nvim_create_autocmd({ "WinEnter", "WinClosed" }, {
            callback = function(e)
                if e.event == "WinClosed" then
                    seen[tonumber(e.match)] = nil
                    return
                end

                --- WinEnter
                local winid = api.nvim_get_current_win()
                if seen[winid] then
                    Statusline.render(winid)
                    return
                end
                seen[winid] = true
                vim.schedule(function()
                    if not api.nvim_win_is_valid(winid) then return end
                    local components = statusline.win(winid)
                    if type(components) ~= "table" then return end
                    register_combined_component(components, nil, winid)
                    Statusline.render_debounce(winid)
                end)
            end,
        })
    end

    Event.on_event(function(ids, event_info)
        require("witch-line.core.manager.session").with_session(function(session)
            if event_info then
                session.set("EventInfo", event_info)
            end
            update_comp_graph_by_ids(ids, session, DepGraphKind.Event)
            Statusline.render_debounce()
        end)
    end)

    Timer.on_timer_trigger(function(ids)
        require("witch-line.core.manager.session").with_session(function(session)
            update_comp_graph_by_ids(ids, session, DepGraphKind.Timer)
            Statusline.render_debounce()
        end)
    end)

    local emergency_ids = Registry.get_emergency_ids()
    if next(emergency_ids) ~= nil then
        require("witch-line.core.manager.session").with_session(function(session)
            update_comp_graph_by_ids(emergency_ids, session,
                { DepGraphKind.Event, DepGraphKind.Timer })
            Statusline.render_debounce()
        end)
    end
end

--- Update a component and its deps in a new session, then debounce render.
---@param comp ManagedComponent The component to update.
---@param eager? boolean Whether to render immediately instead of debouncing.
---@param dep_graph_kind? DepGraphKind|DepGraphKind[] The kind(s) of dependency graph to update.
---@param seen? table<CompId, true> A cache of seen components to avoid infinite recursion.
M.request_update_comp_graph = function(comp, eager, dep_graph_kind, seen)
    require("witch-line.core.manager.session").with_session(function(session)
        update_comp_graph(comp, session, dep_graph_kind or { DepGraphKind.Event, DepGraphKind.Timer }, seen)
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

return M
