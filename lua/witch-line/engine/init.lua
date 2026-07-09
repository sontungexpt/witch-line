local vim, type, ipairs, rawset, rawget, require = vim, type, ipairs, rawset, rawget, require
local api = vim.api

local Statusline = require("witch-line.engine.statusline")
local Event = require("witch-line.event.event")
local Timer = require("witch-line.event.timer")
local BuiltinComp = require("witch-line.component")

local Registry = require("witch-line.core.registry")
local is_existed = Registry.is_existed
local DepGraphKind = Registry.DepGraphKind
local link_dependency = Registry.link_dependency

local M = {}

--- @type CompId[]
local EmergencyIds = {}
local PendingInitIds = {}


--- Forwards definition functions
local load_component
local mount_component_tree
local mount_component
local mount_literal_comp

--- Link a component's dependency to source IDs.
--- Auto-loads any source that is not yet registered.
---@param kind DepGraphKind
---@param comp_id CompId|CompId[]
---@param dependent_id CompId
local function register_dependency_links(kind, comp_id, dependent_id)
    local id_type = type(comp_id)
    if id_type == "table" then
        for _, id in ipairs(comp_id) do
            link_dependency(kind, id, dependent_id)

            if not is_existed(id) then
                local dep = BuiltinComp[id]
                if dep then
                    load_component(dep)
                end
            end
        end
    elseif id_type == "string" then
        link_dependency(kind, comp_id, dependent_id)
        if not is_existed(comp_id) then
            local dep = BuiltinComp[comp_id]
            if dep then
                load_component(dep)
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
        require("witch-line.engine.update").update_comp_graph(comp, session,
            dep_graph_kind or { DepGraphKind.Event, DepGraphKind.Timer }, seen)
        if eager then
            Statusline.render()
        else
            Statusline.render_debounce()
        end
    end)
end

--- Resolve a component's id.
--- - `___builtin` → return DefaultId as-is.
--- - id set → `IdModule.validate` (errors if not a string or collides with DefaultId).
--- - no id → generate a random one and store it via `rawset`.
--- @param comp Component
--- @return CompId
local function resolve_comp_id(comp)
    local id = comp.id
    if comp.___builtin then
        --- @cast id DefaultId
        return id
    elseif id then
        if type(id) ~= "string" then
            require("witch-line.util.notifier").error("Id must be a string")
        elseif BuiltinComp[id] then
            require("witch-line.util.notifier").error("Id must be different from default id: " .. tostring(id))
        end
        return id
    else
        id = tostring(comp) .. "\0"
        comp.id = id
        return id
    end
end

--- Loads a component, resolving its path if necessary
--- @param comp Component|table
--- @return ManagedComponent
load_component = function(comp)
    if comp.___loaded then
        --- @cast comp ManagedComponent
        return comp
    end

    local path = comp[0]
    if type(path) == "string" then
        local c = BuiltinComp[path]
        if c then
            comp = require("witch-line.core.override")(c, comp)
        end
    end
    comp.___loaded = true

    if type(comp.install) == "function" then
        comp.install(comp)
    end

    local cid = resolve_comp_id(comp)

    --- Handle dependencies links
    local ref = comp.ref
    if type(ref) == "table" then
        register_dependency_links(DepGraphKind.Event, ref.events, cid)
        register_dependency_links(DepGraphKind.Timer, ref.timing, cid)
        register_dependency_links(DepGraphKind.Visible, ref.hidden, cid)
    end

    -- local container_id = comp.___container
    -- if container_id then
    --     register_dependency_links(DepGraphKind.Event, container_id, cid)
    --     register_dependency_links(DepGraphKind.Timer, container_id, cid)
    --     register_dependency_links(DepGraphKind.Visible, container_id, cid)
    -- end

    --- Bind update conditions
    local timing = comp.timing
    if timing then
        Timer.register_timer(cid, timing)
    end

    local events = comp.events
    if events then
        Event.register_events(cid, events)
    end

    ---- NOTE: move this part to statusline instead
    -- -- NOTE: move this part to statusline instead
    -- if comp.win_individual then
    --     Event.register_win_resized(cid)
    -- end

    local managed_comp = Registry.register(cid, comp)

    -- Use rawget to avoid triggering __index, which would recurse
    -- through lookup_plain_value → find_raw_value and crash when
    -- the component lacks a raw `id` field.
    if type(comp.init) == "function" then
        PendingInitIds[#PendingInitIds + 1] = cid
    end

    if comp.lazy == false then
        EmergencyIds[#EmergencyIds + 1] = cid
    end

    return managed_comp
end


--- Mount a single component.
--- Loads it if needed, then attaches it to the statusline.
---@param comp Component
---@param parent_id CompId|nil
---@param winid integer|nil
mount_component = function(comp, parent_id, winid)
    if winid then
        comp.win_individual = true
    end

    load_component(comp)

    -- respect renderable flag
    if comp.renderable == false then
        return
    end

    local update = comp.update
    if not update then
        return
    end

    local cid = comp.id
    --- @cast cid CompId

    Statusline.push(cid, "", winid)

    local flexible = comp.flexible
    if flexible then
        Statusline.track_flexible(cid, flexible)
    end

    comp.renderable = true
end

--- Push a literal string onto the statusline segment list.
--- Empty strings are silently ignored.
---@param comp string
---@param win_id integer|nil  Window-local segment list when set.
---@return string  The input string.
mount_literal_comp = function(comp, win_id)
    if comp ~= "" then
        Statusline.push(nil, comp, win_id)
    end
    return comp
end

---Mount a combined component tree.
---@param comp CombinedComponent
---@param group_id CompId|nil
---@param winid integer|nil
mount_component_tree = function(comp, group_id, winid)
    local kind = type(comp)
    if kind == "string" then
        local required = BuiltinComp[comp]
        if not required then
            return mount_literal_comp(comp, winid)
        end
        comp = required
    elseif kind ~= "table" or next(comp) == nil then
        error(("Invalid combined component: expected string or non empty table, got %s (%s)")
            :format(type(comp), tostring(comp)))
        return nil
    end

    ---@cast comp Component
    if not vim.islist(comp) then
        comp.___container = group_id
        mount_component(comp, group_id, winid)
        group_id = comp.id
    end
    -- style
    -- left_style
    -- right_style
    -- auto_theme
    -- hidden
    -- padding (tuỳ)
    for _, child in ipairs(comp) do
        mount_component_tree(child, group_id, winid)
    end
end

--- Initialise global components, per-window components, event/timer handlers,
--- and emergency components.
---@param statusline UserConfig.Statusline
M.setup = function(statusline)
    mount_component_tree(statusline.global)

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
                    mount_component_tree(components, nil, winid)
                    Statusline.render_debounce(winid)
                end)
            end,
        })
    end

    if next(PendingInitIds) ~= nil then
        for i = 1, #PendingInitIds do
            local id = PendingInitIds[i]
            local comp = Registry.get_comp(id)
            if comp then
                comp.init(comp)
            end
        end
    end

    Event.on_event(function(ids, event_info)
        require("witch-line.core.session").with_session(function(session)
            if event_info then
                session:set("EventInfo", event_info)
            end
            require("witch-line.engine.update").update_comp_graph_by_ids(ids, session, DepGraphKind.Event)
            Statusline.render_debounce()
        end)
    end)

    Timer.on_timer_trigger(function(ids)
        require("witch-line.core.session").with_session(function(session)
            require("witch-line.engine.update").update_comp_graph_by_ids(ids, session, DepGraphKind.Timer)
            Statusline.render_debounce()
        end)
    end)

    if next(EmergencyIds) ~= nil then
        require("witch-line.core.session").with_session(function(session)
            require("witch-line.engine.update").update_comp_graph_by_ids(EmergencyIds, session,
                { DepGraphKind.Event, DepGraphKind.Timer })
            Statusline.render_debounce()
        end)
    end
end




return M
