local setmetatable, select, rawset, rawget = setmetatable, select, rawset, rawget
local M = {}

local CACHE_SCOPE_KEY = {}

--------------------------------------------------------------------------------
-- CacheScope
--------------------------------------------------------------------------------

---@class CacheScope
---@field _node table
local CacheScope = {}
CacheScope.__index = CacheScope

function CacheScope:get(key) return rawget(self._node, key) end

function CacheScope:set(key, value)
    rawset(self._node, key, value)
    return value
end

function CacheScope:memo(fn, ...)
    local result = rawget(self._node, fn)
    if result == nil then
        result = { fn(...) }
        rawset(self._node, fn, result)
    end
    return unpack(result)
end

--------------------------------------------------------------------------------
-- Session
--------------------------------------------------------------------------------

---@class Session
---@field _store? table
---@field _cache table
local Session = {}
Session.__index = Session

function Session:get(key)
    local store = self._store
    return store and store[key]
end

function Session:set(key, value)
    local store = self._store
    if store == nil then
        store = {}
        self._store = store
    end
    store[key] = value
    return value
end

function Session:cache(...)
    local node = self._cache
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local child = rawget(node, key)
        if child == nil then
            child = {}
            rawset(node, key, child)
        end
        node = child
    end
    local scope = rawget(node, CACHE_SCOPE_KEY)
    if scope == nil then
        scope = setmetatable({ _node = node }, CacheScope)
        rawset(node, CACHE_SCOPE_KEY, scope)
    end
    return scope
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local new = function()
    return setmetatable({ _cache = {} }, Session)
end

M.new = new

M.with_session = function(cb)
    cb(new())
end

return M
