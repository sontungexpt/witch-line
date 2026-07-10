local lookup_plain_value = require("witch-line.engine.resolver").resolve_plain_field

local ManagedComps = require("witch-line.engine.registry").ManagedComps
local CompAPI = require("witch-line.core.component_api")

local M = {}

--- @type table<string, table<CompId, {[1]: any,[2]: integer}>>
local inherited_cache = {}

---@param comp ManagedComponent
---@param key string
---@param merge fun(current: any, parent: any, n: integer): any
---@param initial_value? any
---@param session Session
---@param ... any
---@return any
---@return boolean
---@return integer
function M.inherit(comp, key, merge, initial_value, session, ...)
    local cid = comp.id
    local recompute_requires = initial_value ~= nil
    local key_cache

    if not recompute_requires then
        key_cache = inherited_cache[key]
        local cached = key_cache and key_cache[cid]
        if cached then
            return cached[1], false, cached[2]
        end
    end


    local seen = {}
    local merged = initial_value

    if merged == nil then
        merged = lookup_plain_value(comp, key, seen)
        if session and type(merged) == "function" then
            recompute_requires = true
            merged = session:cache(comp, key):memo(merged, ...)
        end
    end


    local n = 0
    local pid = comp.___container

    while pid do
        if seen[pid] then
            break
        end
        seen[pid] = true

        local parent = ManagedComps[pid]
        if not parent then
            break
        end

        local value = lookup_plain_value(parent, key, seen)
        if session and type(value) == "function" then
            recompute_requires = true
            value = session:cache(parent, key):memo(value, ...)
        end


        if value ~= nil then
            n = n + 1
            merged = merge(merged, value, n)
        end


        pid = parent.___container
    end


    if not merged then
        local cache = { merged, n }
        if recompute_requires then
            session:cache("inherit:" .. key):set(cid, cache)
        else
            if key_cache then
                key_cache[cid] = cache
            else
                inherited_cache[key] = { [cid] = cache }
            end
        end
    end


    return merged, recompute_requires, n
end
