local vim, type, ipairs, rawset, require = vim, type, ipairs, rawset, require
local api, is_list = vim.api, vim.islist

local Component = require("witch-line.core.Component")
local Statusline = require("witch-line.core.statusline")
local Event = require("witch-line.core.manager.event")
local Timer = require("witch-line.core.manager.timer")

local Manager = require("witch-line.core.manager")
local DepGraphKind = Manager.DepGraphKind
local link_dependency = Manager.link_dependency

-- Lazy-loaded modules (self-replacing on first access)
local Highlight
Highlight = setmetatable({}, {
    __index = function(tbl, k)
        Highlight = require("witch-line.core.highlight")
        return Highlight[k]
    end
})

local M = {}

--- Clear a component's visual representation from the statusline.
---
--- If the component is currently rendered it is hidden via
--- `Statusline.hide_segment`.  The `_hidden` flag is set so subsequent
--- updates can skip re-render if the component remains suppressed.
---
---@param comp ManagedComponent  The component to hide.  Must have been
---           previously registered with `Manager.register`.  Only acts if
---           `comp._renderable` is truthy (i.e. the component has an
---           `update` field and has been indexed).  When `win_individual`
---           is set, the window-specific segment is hidden via
---           `api.nvim_get_current_win()`.
local hide_component = function(comp)
    if comp._renderable then
        Statusline.hide_segment(comp.id, comp.win_individual and api.nvim_get_current_win() or nil)
        rawset(comp, "_hidden", true)
    end
end

--- Normalise a side value before passing it to the statusline.
---
--- Dynamic (function-based) values that do not produce a string are
--- replaced with the empty string so the side slot still occupies space.
--- Static non-string values are discarded (`nil`).
---
---@param val any  The raw value returned by a side-field evaluator (e.g.
---                `comp.left` or `comp.right` after resolving via
---                `resolve_field(lval, comp, ctx)`).  May be any type.
---@param is_func boolean  `true` if the raw value originally came from a
---                        function invocation (i.e. the side field was a
---                        function that was called).  When `true`, non-string
---                        results become `""` instead of `nil` so the side
---                        slot preserves its space in the layout.
---@return string|nil  A string suitable for the statusline side-value API,
---                    or `nil` to skip setting the side value entirely
---                    (when the raw value was a static non-string that
---                    cannot be rendered).
local format_side_value = function(val, is_func)
    if is_func then
        return type(val) ~= "string" and "" or val
    elseif type(val) ~= "string" then
        return nil
    end
    return val
end

--- Resolve a field value: call functions with session memo, pass through others.
--- @param value any
--- @param comp ManagedComponent
--- @param ctx table
--- @return any
local function resolve_field(value, comp, ctx)
    if type(value) == "function" then
        return ctx.session:memo(value, comp, ctx)
    end
    return value
end

--- Conditionally attach `auto_theme` to a style table.
---
--- If `style` is a table and the component has auto-theming enabled (or
--- none was set yet), the table receives the `auto_theme` flag.
---
---@param style HighlightStyle|nil  The resolved style table to potentially
---                                 modify.  When nil, returned as-is.
---@param enable_auto_theme boolean  The component's auto-theme setting from
---                                  `Component.auto_theme(comp, ctx)`.
---                                  Only applied if `style.auto_theme` is
---                                  already nil/false.
---@return HighlightStyle|nil  The (possibly mutated) input `style`, returned
---                            unchanged when `style` is not a table.
local apply_auto_theme = function(style, enable_auto_theme)
    if type(style) == "table" then
        style.auto_theme = style.auto_theme or enable_auto_theme
    end
    return style
end

--- Resolve the effective style for a component, with optional override merge.
---@param comp ManagedComponent  The component whose style to resolve.
---@param ctx table  The session context (unused directly but forwarded
---                  to `Component.auto_theme`).
---@param override_style HighlightStyle|string|nil  An optional style to
---                  merge on top of the component's own style.  Usually
---                  the override returned by `Component.evaluate`.
---                  Pass nil to skip.
---@return HighlightStyle  The resolved style table with auto-theme applied.
local function resolve_comp_style(comp, ctx, override_style)
    local override_type = type(override_style)
    local style = comp.style

    if override_type == "table" or override_type == "string" then
        style = Highlight.merge_hl(override_style, style)
    end

    style = apply_auto_theme(style, Component.auto_theme(comp, ctx))

    return style
end

--- Apply the main (center) style of a component.
---
--- Computes the effective style (see `resolve_comp_style`), creates or
--- reuses a highlight group, and returns both whether the style changed
--- and the resolved style table for downstream side-style processing.
---
---@param comp ManagedComponent  The component to style.  Its `_hl_name`
---           cache is populated if this is the first call.
---@param ctx table  Session context, forwarded to `resolve_comp_style`.
---@param auto_theme boolean  Pre-computed auto-theme flag from
---                           `Component.auto_theme(comp, ctx)`.
---@param override_style HighlightStyle|string|nil  Optional override style
---                  passed through to `resolve_comp_style`.  May be nil.
---@return boolean  `true` if the highlight was freshly created or changed
---                 (used downstream to decide whether side styles derived
---                 from the main style must be re-applied).
---@return HighlightStyle|nil  The resolved style table returned by
---                 `resolve_comp_style`.  Non-nil when the highlight
---                 call succeeds; nil only if `Highlight.highlight`
---                 returns nil (unusual).
local function update_comp_style(comp, ctx, auto_theme, override_style)
    local style = resolve_comp_style(comp, ctx, override_style)
    local hl_name = comp._hl_name
    if hl_name then
        return Highlight.highlight(hl_name, style), style
    end
    hl_name = Highlight.make_hl_name_from_id(comp.id)
    rawset(comp, "_hl_name", hl_name)
    return Highlight.highlight(hl_name, style), style
end

--- Apply the left or right side style of a component.
---
--- Handles special `SepStyle` constants (`SepBg`, `SepFg`, `Reverse`,
--- `Inherited`) which derive colours from the main resolved style, as
--- well as dynamic function-based styles.
---
--- When the side style resolves to a concrete spec it is highlighted and
--- the highlight name is stored on the component.
---
---@param comp ManagedComponent  The component whose side style to update.
---           Must have `side`-specific fields (e.g. `comp.left_style`,
---           `comp._left_hl_name`).  These are mutated in-place via
---           `rawset` when the hl_name changes.
---@param ctx table  Session context, forwarded to any function-based
---                  side style for evaluation.
---@param side "left"|"right"  Which side to update.  Determines which
---                  hl_name field (`_left_hl_name` vs `_right_hl_name`)
---                  and style field (`left_style` vs `right_style`) are
---                  read/written.
---@param main_style_updated boolean  `true` if the main style changed
---                  during this update cycle.  When `false`, static (non-
---                  dynamic) side styles that reference SepStyle constants
---                  are *not* re-applied, because their derived values
---                  would be identical.
---@param main_style HighlightStyle|nil  The resolved main style from
---                  `update_comp_style`.  Used to derive fg/bg for
---                  `SepStyle.Reverse`, `SepStyle.SepFg`, etc.  May be
---                  nil if the main style could not be resolved.
---@param auto_theme boolean  Pre-computed auto-theme flag, forwarded to
---                  `apply_auto_theme` when the side style produces a
---                  concrete color table.
---@return boolean  `true` if the side highlight was updated or is
---                 inherited from the main style (caller should use the
---                 return hl_name).  `false` when no update occurred
---                 (e.g. static side style unchanged, or SepStyle
---                 constants used with nil main_style).
---@return string|nil  When non-nil, the hl_name to use for this side.
---                    When nil, the caller should use the component's
---                    cached `_left_hl_name` / `_right_hl_name` instead.
---                    A nil hl_name with `true` status means "use the
---                    main hl_name" (Inherited static case).
local function update_comp_side_style(comp, ctx, side, main_style_updated, main_style, auto_theme)
    local side_style = Component.side_style(comp, side)
    local t = type(side_style)
    local hl_name_field = Component.hl_name_field(side)
    local hl_name = comp[hl_name_field]
    local dynamic = t == "function"

    local SepStyle = Component.SepStyle
    if
        not (
            hl_name == nil
            or dynamic
            or (
                main_style_updated
                and t == "number"
                and (
                    side_style == SepStyle.SepBg
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
        side_style = side_style(comp, ctx)
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
            return true, comp._hl_name
        else
            return false, nil
        end
    end

    hl_name = hl_name or Highlight.make_hl_name_from_id(comp.id) .. side
    rawset(comp, hl_name_field, hl_name)
    ---@diagnostic disable-next-line: param-type-mismatch
    return Highlight.highlight(hl_name, apply_auto_theme(side_style, auto_theme)), nil
end

--- Update a single component: value, style, side styles, click handler.
---
--- This is the core per-component update routine.  It:
--- 1. Fires the `pre_update` hook
--- 2. Checks minimum screen width and `hidden` condition; hides if needed
--- 3. Evaluates the component value and optional override style
--- 4. Sets the main value and highlight on the statusline
--- 5. Optionally updates left/right side values and their highlights
--- 6. Registers click handlers
--- 7. Fires the `post_update` hook
---
---@param comp ManagedComponent  The component to render.  Must already be
---           registered via `Manager.register` and have `_renderable` set
---           (i.e. have an `update` field and be indexed).  Fields like
---           `comp.left`, `comp.right`, `comp.on_click` are read directly
---           and may be functions or static values.
---@param ctx table  Session context providing per-cycle memoisation and
---                  storage.  Forwarded to all component hooks and
---                  evaluators (e.g. `Component.evaluate`, side style
---                  functions, `emit_pre_update`, etc.).
local function update_comp(comp, ctx)
    local cid = comp.id
    Component.emit_pre_update(comp, ctx)

    local min_screen_width = Component.min_screen_width(comp, ctx)
    local hidden = min_screen_width and api.nvim_get_option_value("columns", {}) < min_screen_width
        or Component.hidden(comp, ctx)

    if hidden then
        hide_component(comp)
        return true
    end

    local value, override_style = Component.evaluate(comp, ctx)

    if comp._renderable then
        if value == "" then
            hide_component(comp)
        else
            local winid = comp.win_individual and api.nvim_get_current_win() or nil
            local auto_theme = Component.auto_theme(comp, ctx)
            local style_updated, style = update_comp_style(
                comp,
                ctx,
                auto_theme,
                comp._use_returned_style ~= false and override_style or nil
            )

            Statusline.set_value(cid, value, comp._hl_name, winid)

            local lval = comp.left
            if lval then
                lval = format_side_value(resolve_field(lval, comp, ctx), type(lval) == "function")
                if lval then
                    local updated, lhl_name =
                        update_comp_side_style(comp, ctx, "left", style_updated, style, auto_theme)
                    if not lhl_name then
                        Statusline.set_side_value(cid, -1, lval, comp._left_hl_name, type(lval) == "function", winid)
                    else
                        Statusline.set_side_value(
                            cid, -1, lval,
                            lhl_name or comp._left_hl_name,
                            updated or lhl_name ~= nil, winid
                        )
                    end
                end
            end

            local rval = comp.right
            if rval then
                rval = format_side_value(resolve_field(rval, comp, ctx), type(rval) == "function")
                if rval then
                    local updated, rhl_name =
                        update_comp_side_style(comp, ctx, "right", style_updated, style, auto_theme)
                    if not rhl_name then
                        Statusline.set_side_value(cid, 1, rval, comp._right_hl_name, type(rval) == "function", winid)
                    else
                        Statusline.set_side_value(
                            cid, 1, rval,
                            rhl_name or comp._right_hl_name,
                            updated or rhl_name ~= nil, winid
                        )
                    end
                end
            end

            if comp.on_click then
                Statusline.set_click_handler(cid, Component.register_click_handler(comp), nil, winid)
            end

            rawset(comp, "_hidden", false)
        end
    end

    Component.emit_post_update(comp, ctx)
end
M.update_comp = update_comp



--- Update a component and its dependencies through the dep graph.
--- Recursively walks dependents via `iterate_dependents`, deduped by `seen`.
--- When the component becomes hidden, all its Visible dependents are hidden too.
---@param comp ManagedComponent
---@param ctx table Session context
---@param dep_graph_kind DepGraphKind|DepGraphKind[]
---@param seen? table<CompId, true>
M.update_comp_graph = function(comp, ctx, dep_graph_kind, seen)
    seen = seen or {}
    local id = comp.id
    if seen[id] then return end
    seen[id] = true

    local hidden = update_comp(comp, ctx)

    if hidden then
        for dep_id in Manager.iterate_dependents(DepGraphKind.Visible, id) do
            seen[dep_id] = true
            local dep = Manager.get_comp(dep_id)
            if dep then hide_component(dep) end
        end
    end


    if type(dep_graph_kind) == "table" then
        for _, kind in ipairs(dep_graph_kind) do
            for dep_id in Manager.iterate_dependents(kind, id) do
                if not seen[dep_id] then
                    local dep = Manager.get_comp(dep_id)
                    if dep then
                        M.update_comp_graph(dep, ctx, kind, seen)
                    end
                end
            end
        end
    else
        for dep_id in Manager.iterate_dependents(dep_graph_kind, id) do
            if not seen[dep_id] then
                local dep = Manager.get_comp(dep_id)
                if dep then
                    M.update_comp_graph(dep, ctx, dep_graph_kind, seen)
                end
            end
        end
    end
end

--- Refresh a component and its dependencies in the next session.
---@param comp ManagedComponent
---@param dep_graph_kind? DepGraphKind|DepGraphKind[]
---@param seen? table<CompId, true>
M.request_update_comp_graph = function(comp, dep_graph_kind, seen)
    require("witch-line.core.Session").with_session(function(ctx)
        M.update_comp_graph(comp, ctx, dep_graph_kind or { DepGraphKind.Event, DepGraphKind.Timer }, seen)
        Statusline.render_debounce()
    end)
end



--- Update multiple components by their IDs, expanding through the dep graph.
--- Update multiple components by their IDs.
--- @param ids CompId[] The IDs of the components to update.
--- @param ctx table  Session context
--- @param dep_graph_kind DepGraphKind|DepGraphKind[] Optional.
--- @param seen table<CompId, true>|nil Optional.
function M.update_comp_graph_by_ids(ids, ctx, dep_graph_kind, seen)
    seen = seen or {}
    for _, id in ipairs(ids) do
        if not seen[id] then
            local comp = Manager.get_comp(id)
            if comp then
                M.update_comp_graph(comp, ctx, dep_graph_kind, seen)
            end
        end
    end
end

local function ensure_inherit_chain_registered(id, visiting)
    visiting = visiting or {}
    if visiting[id] then return nil end
    local existing = Manager.get_comp(id)
    if existing then return existing end
    local c = Component.require_by_id(id)
    if not c or c._loaded then return c end
    visiting[id] = true
    local ancestor = rawget(c, "inherit")
    if ancestor then
        ensure_inherit_chain_registered(ancestor, visiting)
    end
    visiting[id] = nil
    return Manager.register(c)
end

--- Register update triggers for a component (timers, events, screen-width).
---@param comp ManagedComponent
local function bind_update_conditions(comp)
    if comp.timing then
        Timer.register_timer(comp)
    end
    if comp.events then
        Event.register_events(comp)
    end
    if comp.min_screen_width then
        Event.register_vim_resized(comp)
    end
    if comp.win_individual then
        Event.register_win_resized(comp)
    end
end

local function register_dependency_links(kind, ids, dependent_id)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            link_dependency(kind, id, dependent_id)

            if not Manager.is_existed(id) then
                local dep = Component.require_by_id(id)
                if dep then
                    M.register_dependency_source(dep)
                end
            end
        end
        return
    end

    link_dependency(kind, ids, dependent_id)
    if not Manager.is_existed(ids) then
        local dep = Component.require_by_id(ids)
        if dep then
            M.register_dependency_source(dep)
        end
    end
end


--- Register an abstract (non-rendered) component for use as an event/timer
--- dependency source.  Wires triggers, inherit/ref metatable, registers
--- dependency edges in the central dep graph, then recursively registers
--- any missing deps.
---
--- Flow: bind_update_conditions → bind_dependencies → pull_missing_dependencies
---       ↓ (recursive)
---       register_abstract_component for each missing dep
---
---@param comp Component|table  Component definition (may have `[0]` path).
---@return ManagedComponent  Registered component with `_loaded` set.
M.register_dependency_source = function(comp)
    if comp._loaded then return comp end

    local comp_path = comp[0]
    if type(comp_path) == "string" then
        local c = Component.require_by_id(comp_path)
        if c then
            comp = require("witch-line.core.Component.override")(c, comp)
        end
    end

    comp = Manager.register(comp)
    rawset(comp, "_loaded", true)

    if comp.init then
        Component.emit_init(comp)
    end

    Component.setup_inherit_ref(comp)

    bind_update_conditions(comp)

    local ref = rawget(comp, "ref")
    if type(ref) == "table" then
        register_dependency_links(DepGraphKind.Event, ref.events, comp.id)
        register_dependency_links(DepGraphKind.Timer, ref.timing, comp.id)
        register_dependency_links(DepGraphKind.Visible, ref.hidden, comp.id)
        register_dependency_links(DepGraphKind.Visible, ref.min_screen_width, comp.id)
    end

    local inherit = rawget(comp, "inherit")
    if inherit then
        local ids = type(inherit) == "table" and inherit or { inherit }
        local kinds = Manager.DepGraphKinds
        local nk = #kinds
        for _, id in ipairs(ids) do
            for i = 1, nk do
                link_dependency(kinds[i], id, comp.id)
            end
            if not Manager.is_existed(id) then
                local dep = Component.require_by_id(id)
                if dep then M.register_dependency_source(dep) end
            end
        end
    end

    if comp.lazy == false then
        Manager.mark_emergency(comp.id)
    end

    return comp
end

--- Build statusline indices for a component.
---
--- Pushes the component's id onto the statusline segment list and, if
--- the component is flexible, registers it with the flex tracking
--- system.  Marks the component as renderable.
---
---@param comp ManagedComponent  The component to index.  Its `id` must
---           already be assigned.  If the component has no `update`
---           field (i.e. it is a pure container), indexing is skipped
---           and `_renderable` remains falsy.
---@param winid integer|nil  When non-nil, the index is pushed to a
---                          window-local statusline segment list rather
---                          than the global one.  Used for per-window
---                          component trees from `statusline.win()`.
local function build_indices(comp, winid)
    local update = comp.update
    if not update then
        return
    end
    local cid = comp.id

    Statusline.push(cid, "", winid)

    local flexible = comp.flexible
    if flexible then
        Statusline.track_flexible(cid, flexible)
    end
    rawset(comp, "_renderable", true)
end

--- Register a single component.
--- Resolves string id, merges overrides, registers in Manager,
--- emits init hook, sets up inheritance, binds triggers, builds indices.
--- For combined components, only the parent is processed here.
---@param comp Component  Resolved table or raw config. If list-like (numeric keys),
---           registration is skipped (combined parent — children handled by caller).
---@param parent_id CompId|nil
---@param winid integer|nil  When set, marks component window-local and pushes
---                  indices to the window-specific segment list.
---@return ManagedComponent  Fully initialised component with triggers bound.
local function register_component(comp, parent_id, winid)
    if comp._loaded then
        --- @cast comp ManagedComponent
        build_indices(comp, winid)
        return comp
    end

    Component._ensure_chain = Component._ensure_chain or ensure_inherit_chain_registered

    if not is_list(comp) then
        if winid then
            rawset(comp, "win_individual", true)
        end

        comp = M.register_dependency_source(comp)

        build_indices(comp, winid)
    end

    --- @cast comp ManagedComponent
    return comp
end

--- Register a literal string value in the statusline.
---
--- If `comp` is not the empty string it is pushed directly onto the
--- statusline segment list as a non-component literal.
---
---@param comp string  The string literal to display.  Empty string `""`
---                    is silently ignored (it would produce a zero-width
---                    segment that serves no purpose).
---@param win_id integer|nil  When non-nil, the literal is pushed to a
---                          window-local statusline segment list.
---@return string  The input `comp`, returned unchanged for convenience
---                in chained expressions.
local function register_literal_comp(comp, win_id)
    if comp ~= "" then
        Statusline.push(nil, comp, win_id)
    end
    return comp
end

--- Register a combined component tree.
---
--- Combined components have both their own definition and an ordered
--- list of children.  This function registers the parent, then
--- recursively registers each child (which may itself be combined).
--- Literal strings encountered at any level are pushed directly.
---
---@param comp CombinedComponent|DefaultId|string  The component to
---                  register.  Strings are resolved via `Component.require_by_id`
---                  first; if no component is found, they are pushed as
---                  literal text.  Tables must be non-empty; empty tables
---                  raise an error.
---@param parent_id CompId|nil  The parent component id.  Pass nil for
---                  top-level components (they have yes parent).
---@param winid integer|nil  Window-local statusline window id.  Pass nil
---                  for the global statusline.
---@return ManagedComponent|string  The registered component table (with `_loaded`,
---                  `_renderable`, etc.) or the original string if it was
---                  pushed as a literal.  Return value is the same object
---                  that was passed in (or its resolved equivalent).
function M.register_combined_component(comp, parent_id, winid)
    local kind = type(comp)
    if kind == "string" then
        --- @cast comp DefaultId
        local c = Component.require_by_id(comp)
        if not c then
            --- @cast comp string
            return register_literal_comp(comp, winid)
        end
        comp = register_component(c, parent_id, winid)
    elseif kind == "table" and next(comp) then
        comp = register_component(comp, parent_id, winid)
    else
        error("Invalid component type: " .. kind)
        return nil
    end

    for i, child in ipairs(comp) do
        --- @cast child CombinedComponent
        M.register_combined_component(child, comp.id, winid)
        rawset(comp, i, nil)
    end
    return comp
end

--- Initialise the plugin.
--- Registers global components, optional per-window components
--- (via `statusline.win`), wires event/timer handlers, processes
--- emergency (non-lazy) components registered during setup.
---@param user_configs UserConfig  Must contain `statusline.global`.
---                  `statusline.win` is optional — `(winid) → component_tree`.
function M.setup(user_configs)
    local statusline = user_configs.statusline
    --- @cast statusline UserConfig.Statusline

    M.register_combined_component(statusline.global)

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
                    M.register_combined_component(components, nil, winid)
                    Statusline.render_debounce(winid)
                end)
            end,
        })
    end

    Event.on_event(function(ids, event_info)
        require("witch-line.core.Session").with_session(function(ctx)
            if event_info then
                ctx.session:set("EventInfo", event_info)
            end
            M.update_comp_graph_by_ids(ids, ctx, DepGraphKind.Event)
            Statusline.render_debounce()
        end)
    end)

    Timer.on_timer_trigger(function(ids)
        require("witch-line.core.Session").with_session(function(ctx)
            M.update_comp_graph_by_ids(ids, ctx, DepGraphKind.Timer)
            Statusline.render_debounce()
        end)
    end)

    local emergency_ids = Manager.get_emergency_ids()
    if next(emergency_ids) ~= nil then
        require("witch-line.core.Session").with_session(function(ctx)
            M.update_comp_graph_by_ids(emergency_ids, ctx,
                { DepGraphKind.Event, DepGraphKind.Timer })
            Statusline.render_debounce()
        end)
    end
end

return M
