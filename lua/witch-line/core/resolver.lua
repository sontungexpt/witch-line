local NIL = vim.NIL
local type = type

local ManagedComps = require("witch-line.core.registry").ManagedComps
local BuiltinComp = require("witch-line.component")

local M = {}

--- @class RawValueResult
--- @field [1] any
--- @field [2] Component

---@type table<string, table<CompId, vim.NIL|RawValueResult>>
local raw_field_cache = {}


--- Resolve a field by walking the component's `ref` chain.
---
--- The lookup starts from `raw_comp` and follows `ref[key]` recursively
--- until a non-nil value is found or the chain ends.
---
--- Results are cached per `(key, component)` pair.
---
--- @param raw_comp ManagedComponent|DefaultComponent Starting component.
--- @param key NotNil Field name to resolve.
--- @param seen table<CompId, boolean> Cycle detection table.
--- @return RawValueResult|vim.NIL result `{ value, owner }` if found, otherwise `vim.NIL`.
local function resolve_raw_field(raw_comp, key, seen)
    local cid = raw_comp.id
    if seen[cid] then
        return NIL
    end
    seen[cid] = true

    local key_cache = raw_field_cache[key]
    local result = key_cache and key_cache[cid]
    if result then
        return result
    end

    local value = raw_comp[key]
    --- If the value is not nil, return it immediately.
    if value ~= nil then
        return { value, raw_comp }
    end

    local ref = raw_comp.ref
    if type(ref) == "table" then
        local ref_id = ref[key]
        if ref_id then
            --- Lookup the referenced component.
            --- Get the raw component from the registry or builtin components if it exists and is not registered.
            local ref_raw = ManagedComps[ref_id] or BuiltinComp[ref_id]
            if ref_raw then
                result = resolve_raw_field(ref_raw, key, seen)
                if result ~= NIL then
                    if key_cache then
                        key_cache[cid] = result
                    else
                        raw_field_cache[key] = { [cid] = result }
                    end
                    return result
                end
            end
            if key_cache then
                key_cache[cid] = NIL
            else
                raw_field_cache[key] = { [cid] = NIL }
            end
            return NIL
        end
    end

    return NIL
end

--- Resolve a field without modifying callable values.
---
--- @param comp ManagedComponent|DefaultComponent Component to resolve from.
--- @param key string Field name.
--- @return any value Resolved value, or `nil`.
--- @return Component|nil owner Component where the value was found.
M.resolve_plain_field = function(comp, key)
    local r = resolve_raw_field(comp, key, {})
    if r == NIL then
        return nil, nil
    end
    return r[1], r[2]
end


--- Resolve the component that owns a field.
---
--- This performs a normal ref-chain lookup but only returns the component
--- in which the field is defined.
---
--- @param comp ManagedComponent|DefaultComponent Component to resolve from.
--- @param key string Field name.
--- @return Component|nil owner Component defining the field, or `nil`.
M.resolve_field_owner = function(comp, key)
    local r = resolve_raw_field(comp, key, {})
    if r == NIL then
        return nil
    end
    return r[2]
end


return M
