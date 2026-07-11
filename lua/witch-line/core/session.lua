local setmetatable, select, rawset, rawget, unpack =
    setmetatable, select, rawset, rawget, unpack

local M = {}

-- Sentinel key used to associate a CacheScope instance with a cache node.
local CACHE_SCOPE_KEY = {}

--------------------------------------------------------------------------------
-- CacheScope
--------------------------------------------------------------------------------

---Namespace providing key-value and memoization utilities for a cache node.
---@class CacheScope
---@field _node table Internal cache node.
local CacheScope = {}
CacheScope.__index = CacheScope

---Get a value from this cache scope.
---@param key any Cache key.
---@return any value Cached value, or nil if absent.
function CacheScope:get(key)
    return rawget(self._node, key)
end

---Store a value in this cache scope.
---@param key any Cache key.
---@param value any Value to store.
---@return any value The stored value.
function CacheScope:set(key, value)
    rawset(self._node, key, value)
    return value
end

---Memoize a function result within this cache scope.
---
---The function itself is used as the cache key, so each function has an
---independent cached result inside the scope.
---
---The function is executed only on the first call.
---@param fn fun(...): ...any Function to memoize.
---@param ... any Arguments passed to `fn` on cache miss.
---@return ...any Cached or newly computed results.
function CacheScope:memo(fn, ...)
    local cached = rawget(self._node, fn)

    if cached then
        return unpack(cached)
    end

    cached = { fn(...) }

    rawset(self._node, fn, cached)

    return unpack(cached)
end

--------------------------------------------------------------------------------
-- Session
--------------------------------------------------------------------------------

---Session-local storage and hierarchical cache.
---@class Session
---@field _store? table Lazy key-value storage.
---@field _cache table Tree-based cache storage.
---@field _destroy_hooks? fun(session: Session)[] Cleanup callbacks.
local Session = {}
Session.__index = Session

---Get a value from session storage.
---@param key any Storage key.
---@return any value Stored value, or nil if absent.
function Session:get(key)
    local store = self._store

    return store and rawget(store, key)
end

---Store a value in session storage.
---@param key any Storage key.
---@param value any Value to store.
---@return any value The stored value.
function Session:set(key, value)
    local store = self._store

    if store == nil then
        store = {}
        self._store = store
    end

    rawset(store, key, value)

    return value
end

---Register a callback invoked when the session is destroyed.
---
---Callbacks are executed once, in registration order.
---@param cb fun(session: Session)
function Session:on_destroy(cb)
    local hooks = self._destroy_hooks

    if hooks == nil then
        hooks = {}
        self._destroy_hooks = hooks
    end

    hooks[#hooks + 1] = cb
end

---Destroy the session.
---
---Runs all registered destroy callbacks, then releases all session-owned
---storage and cache data.
function Session:destroy()
    local hooks = self._destroy_hooks

    -- Prevent hooks registered during destruction from being executed.
    self._destroy_hooks = nil

    if hooks then
        for i = 1, #hooks do
            hooks[i](self)
        end
    end

    self._store = nil
    self._cache = nil
end

---Get a cache scope for the given path.
---
---Missing cache nodes are created lazily while traversing the path.
---Repeated calls with the same path return the same CacheScope instance.
---
---Example:
---```lua
---local hl_cache = session:cache(component, "highlight")
---```
---@param ... any Cache path segments.
---@return CacheScope scope Cache scope associated with the path.
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
        scope = setmetatable({
            _node = node,
        }, CacheScope)

        rawset(node, CACHE_SCOPE_KEY, scope)
    end

    return scope
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

---Create a new isolated session.
---@return Session session
local new = function()
    return setmetatable({
        _cache = {},
    }, Session)
end

M.new = new

---Execute a callback with a temporary session.
---
---The session is destroyed after the callback returns.
---@param cb fun(session: Session)
function M.with_session(cb)
    local session = new()
    cb(session)
    session:destroy()
end

return M
