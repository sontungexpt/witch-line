local next, rawget, rawset, setmetatable = next, rawget, rawset, setmetatable
local NIL = vim.NIL

local IdModule = require("witch-line.constant.id")

local COMP_MODULE_PATH = "witch-line.components."

local M = {}

--- @enum DepGraphKind
local DepGraphKind = {
    Visible = 1,
    Event = 2,
    Timer = 3,
}
M.DepGraphKind = DepGraphKind

--- Three-way dependency graph.
--- Structure: { [source_id] = { [dependent_id] = true } }
--- One such table per DepGraphKind, pre-allocated at load.
---
--- EventGraph example:
---   { ["diagnostic"] = { ["my_diag"] = true },   -- my_diag inherits diagnostic
---     ["git.branch"] = { ["ext"] = true },        -- ext ref.events = "git.branch"
---   }
--- TimerGraph example:
---   { ["diagnostic"] = { ["my_diag"] = true },   -- my_diag inherits diagnostic
---     ["battery"] = { ["ext"] = true },           -- ext ref.timing = "battery"
---   }
--- VisibleGraph example:
---   { ["hidden_base"] = { ["child"] = true },     -- child ref.hidden = "hidden_base"
---   }
---
---@type table<DepGraphKind, table<CompId, table<CompId, true>>>
local DepGraph = {
    [DepGraphKind.Event] = {},
    [DepGraphKind.Timer] = {},
    [DepGraphKind.Visible] = {},
}

---@type table<CompId, ManagedComponent>
local ManagedComps = {}

--- @type CompId[]
local EmergencyIds = {}

--- Forwards definition functions
local require_by_id
local get_managed
local find_raw_value
local lookup_plain_value
local with_session
local register
local inherit

--- Load a component module by path segments.  First segment is
--- prefixed with `"witch-line.components."`.
--- @param path string[]  Segments, e.g. `{"statusline", "mode"}`.
--- @return table|nil  The resolved module table, or nil if not found.
local require = function(path)
    local component = require(COMP_MODULE_PATH .. path[1])
    for i = 2, #path do
        component = component[path[i]]
        if not component then
            return nil
        end
    end
    return component
end

--- Load a component by its module path id (derived from a DefaultId).
--- Falls back to Component.require internally.
--- @param id DefaultId
--- @return Component|nil
require_by_id = function(id)
    local path = IdModule.path(id)
    return path and require(path) or nil
end


--- Ensure a component is registered before use.
---
--- If the component has not been registered yet, it is loaded through
--- `Component.require_by_id()` and its entire inheritance chain is
--- registered first so parent lookups are always valid.
---
--- Cyclic inheritance is guarded by `visiting`.
---
--- @param id CompId Component id to ensure.
--- @param visiting? table<CompId, boolean> Tracks components currently being visited.
--- @return ManagedComponent|nil
get_managed = function(id, visiting)
    visiting = visiting or {}

    -- Prevent infinite recursion caused by cyclic inheritance.
    if visiting[id] then
        return ManagedComps[id]
    end

    -- Already registered.
    local comp = ManagedComps[id]
    if comp then
        return comp
    end

    -- Load the raw component definition.
    local raw_comp = Component.require_by_id(id)

    if not raw_comp then
        return nil
    end

    visiting[id] = true

    -- Parents must always be registered first.
    local inherit = rawget(raw_comp, "inherit")
    if inherit then
        get_managed(inherit, visiting)
    end

    visiting[id] = nil

    -- Register and return the managed component.
    return register(raw_comp)
end

--- @class RawValueResult
--- @field [1] any                     -- Raw value (or proxy function for reference lookups)
--- @field [2] ManagedComponent        -- Component where the value is originally defined
--- @field [3] ManagedComponent|nil    -- Deepest reference component in the lookup path
--- @field [4] ManagedComponent        -- Deepest inherited component in the lookup path

--- The cache of raw component values, used to avoid redundant lookups.
--- @type table<string, table<CompId, vim.NIL|RawValueResult>>
local raw_cache = {}

--- The cache of inherited values, used to avoid redundant lookups.
--- @type table<string, table<CompId, {[1]: any,[2]: integer}>>
local inherited_cache = {}

--- Internal recursive lookup for a raw (unevaluated) key value.
---
--- Lookup order:
---   1. The component's own field.
---   2. The inheritance chain (`inherit`).
---   3. The reference chain (`ref`).
---
--- The first non-nil value found is returned together with metadata describing
--- where the value originated and how it was reached.
---
--- Results are cached per `(key, component.id)` to avoid redundant traversal.
--- Missing values are cached as `vim.NIL` to distinguish them from uncached entries.
---
--- @param comp ManagedComponent       The component to start searching from.
--- @param key string                  The field name to resolve.
--- @param seen table<CompId, boolean> Tracks visited components to prevent recursive cycles.
---
--- @return RawValueResult|vim.NIL result
find_raw_value = function(comp, key, seen)
    local cid = comp.id
    if seen[cid] then
        return NIL
    end
    seen[cid] = true

    local key_cache = raw_cache[key]
    local result = key_cache and key_cache[cid]
    if result then
        return result
    end

    -- Local value
    local value = rawget(comp, key)
    if value ~= nil then
        result = { value, comp, nil, comp }

        if key_cache then
            key_cache[cid] = result
        else
            raw_cache[key] = { [cid] = result }
        end

        return result
    end

    -- Inherit chain
    local inherit_id = rawget(comp, "inherit")
    if inherit_id then
        local parent = get_managed(inherit_id)
        if parent then
            local r = find_raw_value(parent, key, seen)
            if r ~= NIL then
                result = {
                    r[1],           -- value
                    r[2],           -- origin
                    r[3],           -- last ref
                    r[4] or parent, -- last inherit
                }

                if key_cache then
                    key_cache[cid] = result
                else
                    raw_cache[key] = { [cid] = result }
                end

                return result
            end
        end
    end

    -- Reference chain
    local ref = rawget(comp, "ref")
    if type(ref) == "table" then
        local ref_id = ref[key]
        if ref_id then
            local ref_comp = get_managed(ref[key])
            if ref_comp then
                local r = find_raw_value(ref_comp, key, seen)
                if r ~= NIL then
                    local last_ref = r[3] or ref_comp
                    local value = r[1]

                    if type(value) == "function" then
                        local fn = value
                        value = function(_, ...)
                            return fn(last_ref, ...)
                        end
                    end

                    result = {
                        value,
                        r[2],     -- origin
                        last_ref, -- last ref
                        r[4],     -- last inherit
                    }

                    if key_cache then
                        key_cache[cid] = result
                    else
                        raw_cache[key] = { [cid] = result }
                    end

                    return result
                end
            end
        end
    end

    if key_cache then
        key_cache[cid] = NIL
    else
        raw_cache[key] = { [cid] = NIL }
    end

    return NIL
end

--- Perform a plain lookup for a key within a component hierarchy.
--- This function retrieves the *raw* value of a key by recursively
--- traversing inheritance (`inherit`) and reference (`ref`) chains,
--- without evaluating function-type values.
---
--- Essentially, this is a non-dynamic version of `lookup_dynamic_value`,
--- useful when you only need to know the original source of a value
--- rather than its evaluated result.
---
--- @param comp ManagedComponent            Component to start the lookup from
--- @param key string                       The key name to look up
--- @param seen table<CompId, boolean>|nil  Optional recursionl guard
--- @return nil|any raw_value The raw value found (static or unevaluated function).
--- @return nil|ManagedComponent origin The origin component where the value is defined.
--- @return nil|ManagedComponent drc The deepest reference component, or nil if not found.
lookup_plain_value = function(comp, key, seen)
    local result = find_raw_value(comp, key, seen or {})
    if result == NIL then
        return nil, nil, nil
    end
    return result[1], result[2], result[3]
end

--- Retrieve only the context component for a given key.
---
--- This returns the *final component* in the inheritance or reference chain
--- where the key's value originated — useful for context-based evaluation.
---
--- @param comp ManagedComponent            The component to start lookup from.
--- @param key string                       The key name to look up.
--- @param seen table<CompId, boolean>|nil  Optional recursion guard.
--- @return ManagedComponent|nil context    The deepest referencecomponent, or nil if not found.
M.deepest_reference_component = function(comp, key, seen)
    local r = find_raw_value(comp, key, seen or {})
    return r ~= NIL and r[3] or nil
end

inherit = function(comp, key, merge, self_val, session, ...)
    local cid = comp.id

    --------------------------------------------------------------------------
    -- Static cache lookup.
    -- Only valid when the component's own value is not overridden.
    --------------------------------------------------------------------------
    local key_cache
    if not self_val then
        key_cache = inherited_cache[key]

        local cached = key_cache and key_cache[cid]
        if cached then
            -- Cached format: { value, inherit_chain_size }
            return cached[1], false, cached[2]
        end
    end

    --------------------------------------------------------------------------
    -- `seen` prevents recursive inheritance loops.
    -- `dynamic` becomes true if any value requires runtime evaluation.
    --------------------------------------------------------------------------
    local seen = {}
    local dynamic = false

    --------------------------------------------------------------------------
    -- Resolve the component's own value.
    -- If `self_val` is supplied, it replaces the component value completely.
    --------------------------------------------------------------------------
    local val = self_val

    if val == nil then
        val = lookup_plain_value(comp, key, seen)

        if session and type(val) == "function" then
            dynamic = true
            val = session.memo(val, ...)
        end
    end

    --------------------------------------------------------------------------
    -- Walk up the inheritance chain.
    --------------------------------------------------------------------------
    local n = 0
    local pid = comp.inherit

    while pid do
        local parent = ManagedComps[pid]
        if not parent then
            break
        end

        ----------------------------------------------------------------------
        -- Resolve the parent's value.
        ----------------------------------------------------------------------
        local value = lookup_plain_value(parent, key, seen)

        ----------------------------------------------------------------------
        -- Evaluate lazy values only when a session exists.
        ----------------------------------------------------------------------
        if session and type(value) == "function" then
            dynamic = true
            value = session.memo(value, ...)
        end

        ----------------------------------------------------------------------
        -- Merge immediately.
        -- No temporary chain table is needed.
        ----------------------------------------------------------------------
        if value ~= nil then
            n = n + 1
            val = merge(val, value, n)
        end

        pid = parent.inherit
    end

    --------------------------------------------------------------------------
    -- Cache only when using the component's original value.
    --------------------------------------------------------------------------
    if not self_val then
        local cache = { val, n }

        if dynamic then
            ------------------------------------------------------------------
            -- Dynamic values are session-specific.
            ------------------------------------------------------------------
            local session_key = "inherit:" .. key
            local session_cache = session.get_cache(session_key)

            if session_cache then
                session_cache[cid] = cache
            else
                session.set_cache(session_key, {
                    [cid] = cache,
                })
            end
        else
            ------------------------------------------------------------------
            -- Static values are globally reusable.
            ------------------------------------------------------------------
            if key_cache then
                key_cache[cid] = cache
            else
                inherited_cache[key] = {
                    [cid] = cache,
                }
            end
        end
    end

    --------------------------------------------------------------------------
    -- Returns:
    --   value          : merged result
    --   dynamic        : true if any function was evaluated
    --   n              : number of inherited values merged
    --------------------------------------------------------------------------
    return val, dynamic, n
end

local session_proxy_meta = {
    __index = function(proxy, key)
        local comp = proxy._comp
        local value = lookup_plain_value(comp, key)

        if type(value) == "function" then
            local session = proxy._session
            return function(...)
                return session.memo(value, ...)
            end
        end

        return value
    end,
}

with_session = function(comp, session)
    return setmetatable({
        _comp = comp,
        _session = session,
    }, session_proxy_meta)
end


--- Assign and validate a unique id.  Built-ins (`_plug_provided`) skip generation.
--- @param comp Component  May have `id` pre-set; otherwise one is generated.
--- @return CompId The component's (validated or generated) identifier.
local resolve_comp_id = function(comp)
    local id = comp.id

    --- @cast comp DefaultComponent
    if comp._plug_provided then
        --- @cast id DefaultId
        return id
    end

    if id then
        id = IdModule.validate(id)
    else
        id = tostring(comp) .. tostring(math.random(1, 1000000))
        rawset(comp, "id", id)
    end

    --- @cast id CompId
    return id
end

local shared_comp_meta = {
    __index = function(comp, key)
        if key == "with_session" then
            return with_session
        end

        return lookup_plain_value(comp, key)
    end,
}

register = function(comp)
    local id = resolve_comp_id(comp)
    ManagedComps[id] = setmetatable(comp, shared_comp_meta)
    return id, comp
end


--- Get the list of emergency component ids.
--- @return CompId[] The list of emergency component ids.
M.get_emergency_ids = function()
    return EmergencyIds
end


--- Mark the component with the given id as an emergency component.
--- @param id CompId The component id to mark as emergency.
M.mark_emergency = function(id)
    EmergencyIds[#EmergencyIds + 1] = id
end


--- Get the component for the given id, if it exists.
--- @param id CompId The component id to retrieve.
--- @return ManagedComponent|nil The component, or `nil` if not found.
M.get_comp = function(id)
    return ManagedComps[id]
end

--- Check if the component with the given id exists.
--- @param id CompId The component id to check.
--- @return boolean `true` if the component exists, `false` otherwise.
M.is_existed = function(id)
    return ManagedComps[id] ~= nil
end

--- Register a dependency edge: when `source_id` fires, `dependent_id` is also queued.
--- @param kind DepGraphKind The kind of graph to link in.
--- @param source_id CompId The id of the component that depends on `dependent_id`.
--- @param dependent_id CompId The id of the component that is depended on by `source_id`.
M.link_dependency = function(kind, source_id, dependent_id)
    local graph = DepGraph[kind]
    local deps = graph[source_id]
    if deps then
        deps[dependent_id] = true
    else
        graph[source_id] = { [dependent_id] = true }
    end
end

--- Iterate over registered dependents of `comp_id` in the given graph kind.
--- @param kind DepGraphKind The kind of graph to iterate over.
--- @param comp_id CompId The id of the component to iterate dependents of.
--- @return fun(): CompId|nil A function that returns the next dependent id, or `nil` when done.
M.iterate_dependents = function(kind, comp_id)
    local map = DepGraph[kind][comp_id]
    if map == nil then
        return function() return nil end
    end

    local dependent_id = nil
    return function()
        dependent_id = next(map, dependent_id)
        return dependent_id
    end
end

M.inspect = function(target)
    local notifier = require("witch-line.utils.notifier")
    if target == "dep_graph" then
        notifier.info("DepGraph:\n" .. vim.inspect(DepGraph))
    elseif target == "comps" then
        notifier.info("ManagedComps:\n" .. vim.inspect(ManagedComps))
    else
        notifier.info(vim.inspect({
            DepGraph = DepGraph,
            EmergencyIds = EmergencyIds,
            Comps = ManagedComps,
        }))
    end
end

M.require_by_id = require_by_id
M.with_session = with_session
M.register = register
M.lookup_plain_value = lookup_plain_value
M.inherit = inherit

return M
