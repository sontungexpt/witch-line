local type, ipairs, pairs, require = type, ipairs, pairs, require
local islist = vim.islist

local BuiltinComp = require("witch-line.components")

local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps

local Dependency = require("witch-line.core.dependency")
local DepGraphKind = Dependency.DepGraphKind
local link_dependency = Dependency.link_dependency

local Layout = require("witch-line.render.layout")
local Event = require("witch-line.event.event")
local Timer = require("witch-line.event.timer")

local M = {}

local PendingInitIds = {}


--- Forwards definition functions
local load_component
local mount_component_tree
local mount_component
local mount_literal_comp

local URLY_STR = "\0\1\255"

--- Resolves the component identifier.
--- Uses the existing id when available, validates user-defined ids, and
--- generates a unique internal id for anonymous components.
--- @param comp Component|DefaultComponent
--- @return CompId id Resolved component identifier.
local resolve_id = function(comp)
    local id = comp.id
    if comp.___builtin then
        --- @cast id DefaultId
        return id
    elseif id ~= nil then
        local id_type = type(id)
        if id_type ~= "string" and id_type ~= "number" then
            require("witch-line.util.notifier").error("Id must be a string or number: " .. tostring(id))
        elseif BuiltinComp[id] then
            require("witch-line.util.notifier").error("Id must be different from default id: " .. tostring(id))
        end
        return id
    else
        --- Use the component itself as the id for anonymous components.
        id = URLY_STR .. tostring(comp) .. "\254"
        rawset(comp, "id", id)
        return id
    end
end

local DelegateDepMap = {
    events = DepGraphKind.Event,
    timing = DepGraphKind.Timer,
    hidden = DepGraphKind.Visible,
}

--- Loads a component, resolving its path if necessary
--- @param comp Component
--- @param parent_id? CompId
--- @return ManagedComponent
load_component = function(comp, parent_id)
    if comp.___loaded then
        --- @cast comp ManagedComponent
        return comp
    end

    local path = comp[0]
    if type(path) == "string" then
        local builtin = BuiltinComp[path]
        if builtin then
            comp = require("witch-line.components.util")(builtin, comp)
        end
    end

    if type(comp.constructor) == "function" then
        comp.constructor(comp)
    end

    local cid = resolve_id(comp)

    --- Handle dependencies links
    local delegate = comp.delegate
    if type(delegate) == "table" then
        for field, kind in pairs(DelegateDepMap) do
            local dependency = delegate[field]
            if dependency then
                if type(dependency) == "table" then
                    for i = 1, #dependency do
                        local id = dependency[i]

                        if ManagedComps[id] == nil then
                            local builtin = BuiltinComp[id]
                            if builtin then
                                load_component(builtin)
                            end
                        end

                        link_dependency(kind, id, cid)
                    end
                elseif ManagedComps[dependency] == nil then
                    local builtin = BuiltinComp[dependency]
                    if builtin then
                        load_component(builtin)
                    end
                    link_dependency(kind, dependency, cid)
                end
            end
        end
    end

    if parent_id then
        for field, kind in pairs(DelegateDepMap) do
            link_dependency(kind, parent_id, cid)
        end
    end

    --- Bind update conditions
    local timing = comp.timing
    if timing then
        Timer.register_timer(cid, timing)
    end

    local events = comp.events
    if events then
        Event.register_events(cid, events)
    end

    if comp.lazy == false then
        Event.register_vim_enter_once(cid)
    end

    local managed_comp = Registry.register(cid, comp)

    if type(comp.init) == "function" then
        PendingInitIds[#PendingInitIds + 1] = cid
    end


    return managed_comp
end


--- Mount a single component.
--- @param comp Component
--- @param parent_id? CompId
--- @param winid? integer
--- @return ManagedComponent
mount_component = function(comp, parent_id, winid)
    if winid then
        comp.win_individual = true
    end

    local managed_comp = load_component(comp)
    managed_comp.___parent_id = parent_id

    -- respect renderable flag
    if comp.renderable == false then
        return managed_comp
    end

    local update = comp.update
    if update then
        managed_comp.renderable = true
        Layout.add_to_layout(managed_comp.id, winid)
    end

    return managed_comp
end

--- Push a literal string onto the statusline segment list.
--- Empty strings are silently ignored.
--- @param comp string Non-empty string to push.
--- @param win_id? integer Window-local segment list when set.
--- @return Component
mount_literal_comp = function(comp, win_id)
    local id = comp .. URLY_STR
    ---@type Component
    local literal_comp = {
        id = id,
        update = comp,
    }
    Registry.register(id, literal_comp)
    Layout.add_to_layout(id, win_id)
    return literal_comp
end

--- Mount a combined component tree.
--- @param comp CombinedComponent
--- @param parent_id? CompId
--- @param winid? integer
mount_component_tree = function(comp, parent_id, winid)
    local kind = type(comp)
    if kind == "string" then
        if comp == "" then
            return nil
        end
        local required = BuiltinComp[comp]
        if required == nil then
            return mount_literal_comp(comp, winid)
        end
        comp = required
    elseif kind ~= "table" or next(comp) == nil then
        error(("Invalid combined component: expected string or non empty table, got %s (%s)")
            :format(type(comp), tostring(comp)))
        return nil
    end

    if islist(comp) == false then
        mount_component(comp, parent_id, winid)
        parent_id = comp.id
    end

    for _, child in ipairs(comp) do
        mount_component_tree(child, parent_id, winid)
    end
end

--- Initialise components with init callbacks.
local function run_init_callbacks()
    if next(PendingInitIds) ~= nil then
        for i = 1, #PendingInitIds do
            local id = PendingInitIds[i]
            local comp = ManagedComps[id]
            if comp then
                comp.init(comp)
            end
            PendingInitIds[i] = nil
        end
    end
end

--- Initialise global components, event/timer handlers,
--- and emergency components.
---@param statusline UserConfig.Statusline
M.setup = function(statusline)
    mount_component_tree(statusline.global)

    run_init_callbacks()

    Event.on_event(function(ids, event_info)
        require("witch-line.engine.scheduler").update_ids(
            ids,
            nil,
            false,
            event_info)
    end)

    Timer.on_timer_trigger(function(ids)
        require("witch-line.engine.scheduler").update_ids(
            ids,
            nil,
            false)
    end)
end

return M
