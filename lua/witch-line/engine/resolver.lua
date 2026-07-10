local NIL = vim.NIL
local rawset, select, unpack = rawset, select, unpack

local ManagedComps = require("witch-line.engine.registry").ManagedComps
local BuiltinComp = require("witch-line.component")

local M = {}

--- @class RawValueResult
--- @field [1] any
--- @field [2] Component

---@type table<string, table<CompId, vim.NIL|RawValueResult>>
local raw_cache = {}

---@type table<string, table<CompId, {[1]: any,[2]: integer}>>
local inherited_cache = {}


--- Lookup a component by its ID.
--- @param id CompId
--- @return ManagedComponent|nil
local lookup_comp = function(id)
    return ManagedComps[id] or BuiltinComp[id]
end

---Walk the raw component and its `ref` chain in search of a `key`.
---@param raw_comp ManagedComponent
---@param key string
---@param seen table<CompId, boolean>
---@return RawValueResult|vim.NIL
local function find_raw_value(raw_comp, key, seen)
    local cid = raw_comp.id
    if seen[cid] then
        return NIL
    end
    seen[cid] = true

    local key_cache = raw_cache[key]
    local result = key_cache and key_cache[cid]
    if result then
        return result
    end

    local value = raw_comp[key]
    if value ~= nil then
        return { value, raw_comp }
    end

    local ref = raw_comp.ref
    if type(ref) == "table" then
        local ref_id = ref[key]
        if ref_id then
            local ref_raw = lookup_comp(ref_id)
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
            end
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

--------------------------------------------------------------------------------
-- Session-bound component proxy
--------------------------------------------------------------------------------

local SESSION = {}
local RAW_COMP = {}
local mt = {
    __newindex = function(proxy, key, value)
        rawset(proxy[RAW_COMP], key, value)
    end,
    __index = function(proxy, key)
        local session = proxy[SESSION]
        local raw_comp = proxy[RAW_COMP]

        local res = find_raw_value(raw_comp, key, {})
        if res == NIL then
            return nil
        end

        local value = res[1]
        if type(value) ~= "function" then
            return value
        end

        local origin = res[2]
        local cache = session:cache(origin)
        if origin == raw_comp then
            return function(...)
                return cache:memo(value, ...)
            end
        else
            local self = M.bind_sesion(origin, session)
            return function(...)
                local n = select("#", ...)
                local args = { ... }
                for i = 1, n do
                    local arg = args[i]
                    if arg == raw_comp or proxy == arg then
                        args[i] = self
                    end
                end
                return cache:memo(value, unpack(args))
            end
        end
    end
}

---@param comp ManagedComponent
---@param key string
---@param seen? table<CompId, boolean>
---@return any
---@return ManagedComponent|nil
function M.lookup_plain_value(comp, key, seen)
    local result = find_raw_value(comp, key, seen or {})
    if result == NIL then
        return nil, nil
    end
    return result[1], result[2]
end

---@param comp ManagedComponent
---@param key string
---@param seen? table<CompId, boolean>
---@return ManagedComponent|nil
function M.origin_component(comp, key, seen)
    local r = find_raw_value(comp, key, seen or {})
    if r == NIL then
        return nil
    end
    return r[2]
end

---@param comp ManagedComponent
---@param key string
---@param merge fun(current: any, parent: any, n: integer): any
---@param self_val? any
---@param session Session?
---@param ... any
---@return any
---@return boolean
---@return integer
function M.inherit(comp, key, merge, self_val, session, ...)
    local cid = comp.id

    local key_cache
    if not self_val then
        key_cache = inherited_cache[key]
        local cached = key_cache and key_cache[cid]
        if cached then
            return cached[1], false, cached[2]
        end
    end

    local seen = {}
    local dynamic = false
    local val = self_val

    if val == nil then
        val = M.lookup_plain_value(comp, key, seen)
        if session and type(val) == "function" then
            dynamic = true
            val = session:cache(comp, key):memo(val, ...)
        end
    end

    local n = 0
    local pid = comp.inherit

    while pid do
        local parent = ManagedComps[pid]
        if not parent then
            break
        end

        local value = M.lookup_plain_value(parent, key, seen)
        if session and type(value) == "function" then
            dynamic = true
            value = session:cache(parent, key):memo(value, ...)
        end

        if value ~= nil then
            n = n + 1
            val = merge(val, value, n)
        end

        pid = parent.inherit
    end

    if not self_val then
        local cache = { val, n }
        if dynamic then
            session:cache("inherit:" .. key):set(cid, cache)
        else
            if key_cache then
                key_cache[cid] = cache
            else
                inherited_cache[key] = { [cid] = cache }
            end
        end
    end

    return val, dynamic, n
end

---@param comp ManagedComponent
---@param session Session
---@return ManagedComponent
M.bind_sesion = function(comp, session)
    return setmetatable({ id = comp.id, [SESSION] = session, [RAW_COMP] = comp }, mt)
end

return M
