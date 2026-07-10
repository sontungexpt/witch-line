local NIL = vim.NIL
local type = type

local ManagedComps = require("witch-line.engine.registry").ManagedComps
local BuiltinComp = require("witch-line.component")

local M = {}

--- @class RawValueResult
--- @field [1] any
--- @field [2] Component

---@type table<string, table<CompId, vim.NIL|RawValueResult>>
local raw_value_cache = {}


---Walk the raw component and its `ref` chain in search of a `key`.
---@param raw_comp ManagedComponent
---@param key NotNil
---@param seen table<CompId, boolean>
---@return RawValueResult|vim.NIL
local function find_raw_value(raw_comp, key, seen)
    local cid = raw_comp.id
    if seen[cid] then
        return NIL
    end
    seen[cid] = true

    local key_cache = raw_value_cache[key]
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
                result = find_raw_value(ref_raw, key, seen)
                if result ~= NIL then
                    if key_cache then
                        key_cache[cid] = result
                    else
                        raw_value_cache[key] = { [cid] = result }
                    end
                    return result
                end
            end
            if key_cache then
                key_cache[cid] = NIL
            else
                raw_value_cache[key] = { [cid] = NIL }
            end
            return NIL
        end
    end

    return NIL
end


---@param comp ManagedComponent
---@param key string
---@param seen? table<CompId, boolean>
---@return any
---@return Component|nil
M.lookup_plain_value = function(comp, key, seen)
    local result = find_raw_value(comp, key, seen or {})
    if result == NIL then
        return nil, nil
    end
    return result[1], result[2]
end

---@param comp ManagedComponent
---@param key string
---@param seen? table<CompId, boolean>
---@return Component|nil
M.origin_component = function(comp, key, seen)
    local r = find_raw_value(comp, key, seen or {})
    if r == NIL then
        return nil
    end
    return r[2]
end


return M
