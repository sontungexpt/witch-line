local M = {}

--- @class SessionId : integer


--- @class Session
--- @field id SessionId
--- Retrieve a value from the session memory.
--- @field get fun(k: any): any|nil
---
--- Store a value in the session memory.
--- @field set fun(k: any, v: any): any
---
--- Retrieve a cached value from the session memo.
--- @field get_cache fun(k: any): any|nil
---
--- Store a value in the session memo.
--- @field set_cache fun(k: any, v: any): any
---
--- Retrieve or populate a memoized value for the current session.
---
--- Supported call forms:
---   1. `session:memo(factory, ...)`
---      - Uses `factory` itself as the cache key.
---      - Calls `factory(...)` once and caches the result.
--- Cached values live for the lifetime of the current session.
--- @field memo fun(key_or_factory: any, factory_or_value: any, ...: any): any

local next_sid = 0
local Sessions = {}


--- Allocate a new session id.
--- The backing store and memo cache are created lazily on first `set`/`memo` access.
---@return Session
local function new()
    local sid = next_sid
    next_sid = next_sid + 1
    local cache = {}
    Sessions[sid] = { cache = cache }
    return {
        id = sid,
        get = function(k)
            local data = Sessions[sid].data
            return data and data[k]
        end,
        set = function(k, v)
            local data = Sessions[sid].data or {}
            data[k] = v
            Sessions[sid].data = data
            return v
        end,
        set_cache = function(key, value)
            cache[key] = value
            return value
        end,
        get_cache = function(key)
            return cache[key]
        end,
        memo = function(fn, ...)
            local cached = cache[fn]
            if cached ~= nil then
                return cached[1], cached[2]
            end

            if type(fn) ~= "function" then
                error("memo: fn must be a function, got " .. type(fn))
                return
            end

            local a, b = fn(...)
            cache[fn] = { a, b }
            return a, b
        end
    }
end

--- Destroy a session and free its backing store.
--- Resets the id counter when the last session is removed.
---@param sid SessionId
local function remove(sid)
    Sessions[sid] = nil
    if next(Sessions) == nil then
        next_sid = 0
    end
end

--- Create a session, invoke the callback, then tear it down.
---@param cb fun(session: Session)
M.with_session = function(cb)
    local session = new()
    cb(session)
    remove(session.id)
end

return M
