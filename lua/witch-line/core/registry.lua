local next, rawget, rawset, setmetatable = next, rawget, rawset, setmetatable
local NIL = vim.NIL

local BuiltinComp = require("witch-line.component")

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
---   { ["wl.diagnostic"] = { ["my_diag"] = true },   -- my_diag depends on diagnostic
---     ["wl.git.branch"] = { ["ext"] = true },        -- ext ref.events = "wl.git.branch"
---   }
--- TimerGraph example:
---   { ["wl.diagnostic"] = { ["my_diag"] = true },   -- my_diag depends on diagnostic
---     ["wl.battery"] = { ["ext"] = true },           -- ext ref.timing = "wl.battery"
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

---@type table<CompId, Component>
local ManagedComps = {}



--- Forward declarations
local find_raw_value
local lookup_plain_value
local register
local inherit


--- Ensure a raw component is loaded into ManagedComps by id.
--- Does not create a proxy (lazy).
--- @param id CompId
--- @return ManagedComponent|nil
local function ensure_loaded(id)
    local loaded = ManagedComps[id]
    if loaded then
        return loaded
    end
    return BuiltinComp[id]
end

--- @class RawValueResult
--- @field [1] any             -- Raw value
--- @field [2] Component       -- Raw component where the value is originally defined

--- The cache of raw component values, used to avoid redundant lookups.
--- @type table<string, table<CompId, vim.NIL|RawValueResult>>
local raw_cache = {}

--- The cache of inherited values, used to avoid redundant lookups.
--- @type table<string, table<CompId, {[1]: any,[2]: integer}>>
local inherited_cache = {}

--- Walk the raw component and its `ref` chain in search of a `key` field.
--- Results (including misses) are cached per `(key, cid)`.
--- @param raw_comp ManagedComponent
--- @param key string
--- @param seen table<CompId, boolean>
--- @return RawValueResult|vim.NIL
find_raw_value = function(raw_comp, key, seen)
    local cid = raw_comp.id
    if seen[cid] then
        return NIL
    end
    seen[cid] = true

    --- Cache check (only populated by ref lookups)
    local key_cache = raw_cache[key]
    local result = key_cache and key_cache[cid]
    if result then
        return result
    end

    --- Own field (normal indexing, respects component metatables)
    --- Results are NOT cached — O(1) lookup, no benefit.
    local value = raw_comp[key]
    if value ~= nil then
        return { value, raw_comp }
    end

    --- Reference chain (results are cached to avoid recursive traversal)
    local ref = raw_comp.ref
    if type(ref) == "table" then
        local ref_id = ref[key]
        if ref_id then
            local ref_raw = ensure_loaded(ref_id)
            if ref_raw then
                result = find_raw_value(ref_raw, key, seen)
                if result ~= NIL then
                    if key_cache then
                        key_cache[cid] = result
                    else
                        raw_cache[key] = { [cid] = result }
                    end
                    return result
                end
            else
                --- Cache NIL for ref misses (ref_id resolved but nothing found)
                if key_cache then
                    key_cache[cid] = NIL
                else
                    raw_cache[key] = { [cid] = NIL }
                end
                return NIL
            end
            --- Cache NIL for ref misses (ref_id resolved but nothing found)
            if key_cache then
                key_cache[cid] = NIL
            else
                raw_cache[key] = { [cid] = NIL }
            end
            return NIL
        end
    end

    return NIL
end



--- Perform a plain lookup for a key within a component hierarchy.
--- This function retrieves the *raw* value of a key by
--- traversing the reference (`ref`) chain, without evaluating
--- function-type values.
---
--- Accepts ManagedComponent (proxy or raw) and returns ManagedComponent origins.
---
--- @param comp ManagedComponent            Component to start the lookup from
--- @param key string                       The key name to look up
--- @param seen table<CompId, boolean>|nil  Optional recursion guard
--- @return nil|any raw_value The raw value found (static or unevaluated function).
--- @return nil|ManagedComponent origin The origin component where the value is defined.
lookup_plain_value = function(comp, key, seen)
    local raw_comp = ManagedComps[comp.id] or comp
    local result = find_raw_value(raw_comp, key, seen or {})
    if result == NIL then
        return nil, nil
    end
    return result[1], result[2]
end

--- Retrieve the origin component for a given key.
---
--- Returns the component that actually defines the value for `key`
--- in the reference chain — useful for context-based evaluation.
---
--- @param comp ManagedComponent  Component to start lookup from.
--- @param key string             The key name to look up.
--- @param seen? table<CompId, boolean>  Optional recursion guard.
--- @return ManagedComponent|nil  The origin component, or nil.
M.origin_component = function(comp, key, seen)
    local raw_comp = ManagedComps[comp.id] or comp
    local r = find_raw_value(raw_comp, key, seen or {})
    if r == NIL then
        return nil
    end
    return r[2]
end

--- Resolve a field by walking the inheritance chain and merging values.
---
--- Lookup order:
---   1. The component's own value (or `self_val` if provided).
---   2. Each parent in the `inherit` chain, resolved and merged in order.
---
--- Function-type values encountered during the walk are evaluated via
--- `session.memo` when a session is active, marking the result dynamic.
---
--- Results are cached per `(key, component.id)` to avoid redundant traversal.
--- Dynamic results are cached per-session; static results are cached globally.
---
--- @param comp ManagedComponent     The component to start from.
--- @param key string                The field name to resolve.
--- @param merge fun(current: any, parent: any, n: integer): any
---         Merge function: combines the current value with each parent value.
---         `current` starts as the component's own value or `self_val`.
---         `n` is the depth (1-based) of the parent being merged.
--- @param self_val? any             Skip the component's own lookup and use
---         this value as the starting point instead.
--- @param session Session          When set, function values are evaluated
---         and cached per-session. Dynamic results are stored in session cache.
--- @param ... any                    Arguments forwarded to function values
---         during evaluation via `session.memo(fn, ...)`.
---
--- @return any value    The merged result.
--- @return boolean dynamic  True if any function value was evaluated.
--- @return integer n       Number of parent values merged.
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
            val = session:cache(comp, key):memo(val, ...)
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
            value = session:cache(parent, key):memo(value, ...)
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
            session:cache(session_key):set(cid, cache)
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


---Register a component.
--- Stores the raw component in ManagedComps and creates a proxy.
---@param cid CompId
---@param comp Component
---@return ManagedComponent
register = function(cid, comp)
    ManagedComps[cid] = comp
    return comp
end


--- Get the component for the given id, if it exists.
--- Creates the proxy lazily on first access.
--- @param id CompId The component id to retrieve.
--- @return ManagedComponent|nil The component, or `nil` if not found.
M.get_comp = function(id)
    return ManagedComps[id]
end

---comment
---@param comp ManagedComponent
---@param session Session
---@return ManagedComponent
M.bind_sesion = function(comp, session)
    return setmetatable({ id = comp.id }, {
        __newindex = comp,
        __index = function(proxy, key)
            local res = find_raw_value(comp, key, {})
            if res == NIL then
                return nil
            end

            local value = res[1]
            if type(value) ~= "function" then
                return value
            end

            local origin = res[2]
            local cache = session:cache(origin, key)
            if origin == comp then
                return function(...)
                    return cache:memo(value, ...)
                end
            else
                return function(...)
                    local args = { ... }
                    local self = M.bind_sesion(origin, session)
                    for index, arg in ipairs(args) do
                        if arg == comp or proxy == arg then
                            args[index] = self
                        end
                    end
                    return cache:memo(value, unpack(args))
                end
            end
        end
    })
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
M.iterate_dependent_ids = function(kind, comp_id)
    local map = DepGraph[kind][comp_id]
    if map then
        local dependent_id = nil
        return function()
            dependent_id = next(map, dependent_id)
            return dependent_id
        end
    end

    return function() return nil end
end

M.inspect = function(target)
    local notifier = require("witch-line.util.notifier")
    if target == "dep_graph" then
        notifier.info("---- DepGraph ---- \n" .. vim.inspect(DepGraph))
    elseif target == "comps" then
        notifier.info("---- ManagedComps ---- \n" .. vim.inspect(ManagedComps))
    else
        notifier.info(vim.inspect({
            DepGraph = DepGraph,
            Comps = ManagedComps,
        }))
    end
end

M.register = register
M.lookup_plain_value = lookup_plain_value
M.inherit = inherit

return M
