local vim, type, ipairs, rawset, rawget, require = vim, type, ipairs, rawset, rawget, require
local api, islist = vim.api, vim.islist

local Statusline = require("witch-line.engine.statusline")
local Event = require("witch-line.event.event")
local Timer = require("witch-line.event.timer")
local BuiltinComp = require("witch-line.component")

local Registry = require("witch-line.core.registry")
local ManagedComps = Registry.ManagedComps
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

            if not ManagedComps[id] then
                local dep = BuiltinComp[id]
                if dep then
                    load_component(dep)
                end
            end
        end
    elseif id_type == "string" then
        link_dependency(kind, comp_id, dependent_id)
        if not ManagedComps[comp_id] then
            local dep = BuiltinComp[comp_id]
            if dep then
                load_component(dep)
            end
        end
    end
end

--- Resolves the component identifier.
---
--- Uses the existing id when available, validates user-defined ids, and
--- generates a unique internal id for anonymous components.
---
--- @param comp Component|DefaultComponent
--- @return CompId id Resolved component identifier.
local function resolve_comp_id(comp)
    local id = comp.id
    if comp.___builtin then
        --- @cast id DefaultId
        return id
    elseif id then
        if type(id) == "string" and BuiltinComp[id] then
            require("witch-line.util.notifier").error("Id must be different from default id: " .. tostring(id))
        end
        return id
    else
        --- Use the component itself as the id for anonymous components.
        id = comp
        comp.id = id
        return id
    end
end

--- Loads a component, resolving its path if necessary
--- @param comp Component
--- @return ManagedComponent
load_component = function(comp, container_id)
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

    if type(comp.constructor) == "function" then
        comp.constructor(comp)
    end

    local cid = resolve_comp_id(comp)

    --- Handle dependencies links
    local delegator = comp.delegator
    if type(delegator) == "table" then
        local delegator_events, delegator_timming, delegator_hidden = delegator.events, delegator.timing,
            delegator.hidden
        if delegator_events then
            register_dependency_links(DepGraphKind.Event, delegator_events, cid)
        end
        if delegator_timming then
            register_dependency_links(DepGraphKind.Timer, delegator_timming, cid)
        end
        if delegator_hidden then
            register_dependency_links(DepGraphKind.Visible, delegator_hidden, cid)
        end
    end

    if container_id then
        register_dependency_links(DepGraphKind.All, container_id, cid)
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
---@param container_id? CompId
---@param winid? integer
---@return ManagedComponent
mount_component = function(comp, container_id, winid)
    comp.___parent_id = container_id
    if winid then
        comp.win_individual = true
    end

    local managed_comp = load_component(comp)

    -- respect renderable flag
    if comp.renderable == false then
        return managed_comp
    end

    local update = comp.update
    if not update then
        return managed_comp
    end

    local cid = comp.id
    --- @cast cid CompId

    Statusline.push(cid, "", winid)

    local flexible = comp.flexible
    if flexible then
        Statusline.track_flexible(cid, flexible)
    end

    comp.renderable = true
    return managed_comp
end

--- Push a literal string onto the statusline segment list.
--- Empty strings are silently ignored.
---@param comp string Non-empty string to push.
---@param win_id integer|nil  Window-local segment list when set.
---@return Component  The input string.
mount_literal_comp = function(comp, win_id)
    --- @type Component

    local literal_comp = {
        update = comp,
    }

    local cid = literal_comp
    literal_comp.id = cid
    Registry.register(cid, literal_comp, win_id)

    Statusline.push(nil, comp, win_id)
    return literal_comp
end

---Mount a combined component tree.
---@param comp CombinedComponent
---@param container_id CompId|nil
---@param winid integer|nil
mount_component_tree = function(comp, container_id, winid)
    local kind = type(comp)
    if kind == "string" then
        if comp == "" then
            return nil
        end
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

    if not islist(comp) then
        mount_component(comp, container_id, winid)
        container_id = comp.id
    end

    -- style
    -- left_style
    -- right_style
    -- theme_aware
    -- hidden
    -- padding
    for _, child in ipairs(comp) do
        mount_component_tree(child, container_id, winid)
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
            local comp = Registry.ManagedComps[id]
            if comp then
                comp.init(comp)
            end
        end
    end

    Event.on_event(function(ids, event_info)
        require("witch-line.engine.request").update_ids(
            ids,
            DepGraphKind.Event,
            false,
            event_info)
    end)

    Timer.on_timer_trigger(function(ids)
        require("witch-line.engine.request").update_ids(
            ids,
            DepGraphKind.Timer,
            false)
    end)

    if next(EmergencyIds) ~= nil then
        require("witch-line.engine.request").update_ids(
            EmergencyIds,
            DepGraphKind.Event,
            false)
    end
end




return M
