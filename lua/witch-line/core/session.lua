local setmetatable, select, rawset, rawget = setmetatable, select, rawset, rawget
local M = {}

--- Sentinel key to cache the `CacheScope` instance inside a cache node.
local CACHE_SCOPE_KEY = {}

--------------------------------------------------------------------------------
-- CacheScope
--------------------------------------------------------------------------------

---@class CacheScope
---@field _node table
local CacheScope = {}
CacheScope.__index = CacheScope

---Read a value from the cache node.
---@param key any
---@return any
function CacheScope:get(key) return rawget(self._node, key) end

---Write a value into the cache node.
---@param key any
---@param value any
---@return any
function CacheScope:set(key, value)
    rawset(self._node, key, value)
    return value
end

---Memoize a function — caches the result by `fn` reference.
---@param fn fun(...): any
---@param ... any
---@return ...
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

---Read from the session store (lazy-created).
---@param key any
---@return any
function Session:get(key)
    local store = self._store
    return store and store[key]
end

---Write to the session store (creates it on first write).
---@param key any
---@param value any
---@return any
function Session:set(key, value)
    local store = self._store
    if store == nil then
        store = {}
        self._store = store
    end
    store[key] = value
    return value
end

---Walk the cache tree and return the leaf `CacheScope`.
---Each arg is a tree level: `session:cache(comp, "key")`
---@param ... any
---@return CacheScope
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

---Create a fresh session.
---@return Session
local new = function()
    return setmetatable({ _cache = {} }, Session)
end

---Manual lifecycle — use `with_session` unless you need ownership.
---@return Session
M.new = new

---Create a temporary session, run `cb`, then discard.
---@param cb fun(session: Session)
M.with_session = function(cb)
    cb(new())
end

return M
