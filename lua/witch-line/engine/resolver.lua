local NIL = vim.NIL
local type = type

local ManagedComps = require("witch-line.engine.registry").ManagedComps
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
--- @param raw_comp ManagedComponent Starting component.
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

--- @type table<function, function>
local closure_cache = {}

--- Resolve a component field.
---
--- Unlike `resolve_plain_field`, if the resolved value is a function
--- inherited from another component, this function returns a wrapped
--- closure that automatically replaces any argument equal to `comp`
--- with the component that actually owns the function.
---
--- This allows inherited methods to behave as if they were invoked on
--- their defining component.
---
--- @param comp ManagedComponent Component to resolve from.
--- @param key string Field name.
--- @return any value Resolved value, or `nil` if not found.
--- @return Component|nil owner Component where the value was found.
M.resolve_field = function(comp, key, is_comp_alias)
    local raw = resolve_raw_field(comp, key, {})
    if raw == NIL then
        return nil, nil
    end

    local value, origin = raw[1], raw[2]
    if type(value) ~= "function" or comp == origin then
        return value, origin
    end

    if closure_cache[value] then
        return closure_cache[value], origin
    end

    local closure = function(...)
        local args = { ... }
        for i = 1, select("#", ...) do
            local arg = args[i]
            if arg == comp or is_comp_alias(arg) then
                args[i] = origin
            end
        end
        return value(unpack(args))
    end

    closure_cache[value] = closure
    return closure, origin
end


--- Resolve a field without modifying callable values.
---
--- This performs the same lookup as `resolve_field` but returns the raw
--- value directly, even if it is an inherited function.
---
--- @param comp ManagedComponent Component to resolve from.
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
--- @param comp ManagedComponent Component to resolve from.
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
