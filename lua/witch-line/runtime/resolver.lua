local NIL = vim.NIL
local type, pairs = type, pairs

local ManagedComps = require("witch-line.core.registry").ManagedComps

local M = {}

----------------------------------------------------------------------
-- Delegate chain resolution
----------------------------------------------------------------------

---@alias RawValueResult { value: any, owner: ManagedComponent|DefaultComponent }

---@type table<string, table<CompId, vim.NIL|RawValueResult>>
local raw_field_cache = {}

--- Resolve a field by following the component's `delegate` chain.
---
--- Lookup order:
--- 1. Check the component's own field first.
--- 2. Follow `delegate[key]` references until a value is found.
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
    local value = raw_comp[key]
    if value ~= nil then
        return { value, raw_comp }
    end

    local current_id = raw_comp.id

    local field_cache = raw_field_cache[key]
    if field_cache == nil then
        field_cache = {}
        raw_field_cache[key] = field_cache
    end

    local result = field_cache[current_id]
    if result then
        return result
    end

    local seen = { [current_id] = true }

    local delegate = raw_comp.delegate
    while type(delegate) == "table" do
        local next_id = delegate[key]
        if next_id == nil or seen[next_id] then
            break
        end

        current_id = next_id
        seen[current_id] = true

        result = field_cache[current_id]
        if result then
            break
        end

        --- Get the component from the managed comps or lazy required builtin comps.
        local comp = ManagedComps[current_id] or require("witch-line.components")[current_id]
        if comp == nil then
            break
        end

        value = comp[key]
        if value ~= nil then
            result = { value, comp }
            break
        end

        delegate = comp.delegate
    end

    result = result or NIL

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
--- This performs a normal delegate-chain lookup but only returns the component
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

--- Inspect the set of cached component for debug.
--- @param key? any
--- @return table
M.inspect = function(key)
    local cache = key and raw_field_cache[key] or raw_field_cache
    require("witch-line.util.notifier").info(vim.inspect(cache))
    return cache
end

--- Clear the entire raw field cache, or cache for a specific key.
--- @param key? any
M.clear_cache = function(key)
    if key then
        raw_field_cache[key] = nil
    else
        raw_field_cache = {}
    end
end


return M
