local NIL = vim.NIL
local type, pairs = type, pairs

local ManagedComps = require("witch-line.core.registry").ManagedComps
local BuiltinComp = require("witch-line.component")

local M = {}

--- @class RawValueResult
--- @field [1] any
--- @field [2] Component

---@type table<string, table<CompId, vim.NIL|RawValueResult>>
local raw_field_cache = {}

--- Recursive reference (kept for comparison).
---
--- local function resolve_raw_field(raw_comp, key, seen)
---     local cid = raw_comp.id
---     if seen[cid] then
---         return NIL
---     end
---
---     local value = raw_comp[key]
---     --- If the value is not nil, return it immediately.
---     if value ~= nil then
---         return { value, raw_comp }
---     end
---     seen[cid] = true
---
---     local delegator = raw_comp.delegator
---     if type(delegator) == "table" then
---         local key_cache = raw_field_cache[key]
---         local result = key_cache and key_cache[cid]
---         if result then
---             return result
---         end
---
---         local delegator_id = delegator[key]
---         if delegator_id then
---             --- Lookup the referenced component.
---             --- Get the raw component from the registry or builtin components if it exists and is not registered.
---             local delegator_raw = ManagedComps[delegator_id] or BuiltinComp[delegator_id]
---             if delegator_raw then
---                 result = resolve_raw_field(delegator_raw, key, seen)
---                 if result ~= NIL then
---                     if key_cache then
---                         key_cache[cid] = result
---                     else
---                         raw_field_cache[key] = { [cid] = result }
---                     end
---                     return result
---                 end
---             end
---             if key_cache then
---                 key_cache[cid] = NIL
---             else
---                 raw_field_cache[key] = { [cid] = NIL }
---             end
---             return NIL
---         end
---     end
---
---     return NIL
--- end


--- Resolve a field by following the component's `delegator` chain.
---
--- Lookup order:
--- 1. Check the component's own field first.
--- 2. Follow `delegator[key]` references until a value is found.
--- 3. Cache the resolved result for all traversed components.
---
--- Cache behavior:
--- - Components with direct values are returned immediately and not cached.
--- - The final component providing the value is not cached.
--- - Failed lookups are cached as `vim.NIL`.
---
--- @param raw_comp ManagedComponent|DefaultComponent Starting component.
--- @param key NotNil Field to resolve.
--- @return RawValueResult|vim.NIL `{ value, owner }` if found, otherwise `vim.NIL`.
local function resolve_raw_field(raw_comp, key)
    -- Fast path: most components resolve from their own fields.
    local value = raw_comp[key]
    if value ~= nil then
        return { value, raw_comp }
    end

    local current_id = raw_comp.id

    -- Create a cache bucket for this field.
    local field_cache = raw_field_cache[key]
    if field_cache == nil then
        field_cache = {}
        raw_field_cache[key] = field_cache
    end

    -- Return previous resolution if this component was already resolved.
    local result = field_cache[current_id]
    if result then
        return result
    end

    --- Every component stepped into during traversal.
    --- Dual purpose:
    ---   1. Cycle detection — prevents infinite loops.
    ---   2. Cache set — every entry except the final component gets cached.
    ---      The final component is either the value owner (not cached by rule),
    ---      a missing component (nothing to cache), or a cycle-detected node
    ---      (never completed a delegation).
    ---@type table<CompId, true>
    local seen = { [current_id] = true }

    local delegator = raw_comp.delegator
    while type(delegator) == "table" do
        --- The next component to step into.
        local next_id = delegator[key]
        if next_id == nil or seen[next_id] then
            break
        end

        --- The current component being stepped into.
        current_id = next_id
        seen[current_id] = true

        --- Reuse a previously resolved dependency.
        result = field_cache[current_id]
        if result then
            break
        end

        --- Get the referenced component.
        local comp = ManagedComps[current_id] or BuiltinComp[current_id]
        if comp == nil then
            break
        end

        --- A value on the referenced component becomes the owner.
        value = comp[key]
        if value ~= nil then
            result = { value, comp }
            break
        end

        delegator = comp.delegator
    end

    --- Store NIL as a cached failure to distinguish it from cache miss.
    result = result or NIL

    --- Cache every traversed component except the final one.
    seen[current_id] = nil
    for id in pairs(seen) do
        field_cache[id] = result
    end

    return result
end

--- Resolve a field without modifying callable values.
---
--- @param comp ManagedComponent|DefaultComponent Component to resolve from.
--- @param key string Field name.
--- @return any value Resolved value, or `nil`.
--- @return Component|nil owner Component where the value was found.
M.resolve_plain_field = function(comp, key)
    local r = resolve_raw_field(comp, key)
    if r == NIL then
        return nil, nil
    end
    return r[1], r[2]
end


--- Resolve the component that owns a field.
---
--- This performs a normal delegator-chain lookup but only returns the component
--- in which the field is defined.
---
--- @param comp ManagedComponent|DefaultComponent Component to resolve from.
--- @param key string Field name.
--- @return Component|nil owner Component defining the field, or `nil`.
M.resolve_field_owner = function(comp, key)
    local r = resolve_raw_field(comp, key)
    if r == NIL then
        return nil
    end
    return r[2]
end


--- Get cache keys for a specific field (for testing).
---
--- @param key string Field name to inspect.
--- @return table<CompId, true> keys Set of component IDs that have cached results for this key.
M.get_cache_keys = function(key)
    local fc = raw_field_cache[key]
    if fc == nil then
        return {}
    end
    local keys = {}
    for k in pairs(fc) do
        keys[k] = true
    end
    return keys
end

return M
