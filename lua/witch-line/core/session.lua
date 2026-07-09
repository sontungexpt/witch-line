local setmetatable, rawset, rawget = setmetatable, rawset, rawget
local M = {}

---@alias SessionId integer

---@type SessionId
local latest_sid = 0

---@type table<SessionId, Session>
local Sessions = {}

--- Sentinel key used to cache the `CacheScope` instance inside a cache node.
---@type table
local CACHE_SCOPE_KEY = {}

--------------------------------------------------------------------------------
-- Cache Scope
--------------------------------------------------------------------------------

---A cache namespace within a session.
---
---Each cache scope stores arbitrary values and memoized function results.
---Missing keys automatically fall back to the parent session store.
---@class CacheScope
---@field private _node table<any, any>
local CacheScope = {}
CacheScope.__index = CacheScope

---Gets a value from this cache scope.
---@param key any
---@return any value
function CacheScope:get(key)
    return rawget(self._node, key)
end

---Stores a value in this cache scope.
---
---@param key any
---@param value any
---@return any value
function CacheScope:set(key, value)
    rawset(self._node, key, value)
    return value
end

---Memoizes a function call.
---
---The function itself is used as the cache key.
---
---@generic R...
---@param fn fun(...): R...
---@param ... any Arguments passed to `fn`.
---@return R...
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

---Represents an isolated render session.
---
---A session contains:
---  - A lazily-created shared store.
---  - A hierarchical cache tree.
---
---@class Session
---@field id SessionId Unique session id.
---@field private _store? table<any, any> Shared session store.
---@field private _cache table<any, any> Cache tree.
local Session = {}
Session.__index = Session

---Gets a value from the session store.
---
---@param key any
---@return any value
function Session:get(key)
    local store = self._store
    return store and store[key]
end

---Stores a value in the session store.
---
---The store is created lazily on first write.
---
---@param key any
---@param value any
---@return any value
function Session:set(key, value)
    local store = self._store

    if store == nil then
        store = {}
        self._store = store
    end

    store[key] = value
    return value
end

---Gets or creates a cache scope.
---
---Each argument represents one level in the cache tree.
---
---Examples:
---```lua
---session:cache("git")
---session:cache("git", bufnr)
---session:cache(component, "highlight", winid)
---```
---
---@param ... any Cache path.
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

---Creates a new session.
---
---@return Session
local function new()
    latest_sid = latest_sid + 1

    local session = setmetatable({
        id = latest_sid,
        _cache = {},
    }, Session)

    Sessions[latest_sid] = session

    return session
end

---Destroys a session.
---
---@param sid SessionId
local function destroy(sid)
    Sessions[sid] = nil

    if next(Sessions) == nil then
        latest_sid = 0
    end
end

---Creates a temporary session.
---
---The session is automatically destroyed after the callback finishes.
---
---@param cb fun(session: Session)
function M.with_session(cb)
    local session = new()

    cb(session)

    destroy(session.id)
end

return M
