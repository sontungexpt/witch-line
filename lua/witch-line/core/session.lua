local M = {}

--- @class SessionId : integer

--- The latest session id.
--- @type SessionId
local lastest_sid = 0

--- @type table<SessionId, Session>
local Sessions = {}

--- Allocate a new session id.
--- The backing store and memo cache are created lazily on first `set`/`memo` access.
---@return Session
local function new()
    lastest_sid = lastest_sid + 1

    local data = {}
    local cache = {}

    --- @class Session
    local session = {
        --- The session id.
        --- @type SessionId
        id = lastest_sid,
        --- Set the value in the data store.
        --- @param k any The key to store the value under.
        --- @param v any The value to store.
        --- @return any The value that was stored in the data store.
        set = function(k, v)
            data = data or {}
            data[k] = v
            return v
        end,
        --- Get the value from the data store.
        --- @param k any The key to look up in the data store.
        --- @return unknown The value from the data store, or `nil` if not found.
        get = function(k)
            return data[k]
        end,
        ---Set the value in the memo cache.
        ---@param k any The key to store the value under.
        ---@param v any The value to store.
        ---@return any The value that was stored in the cache.
        set_cache = function(k, v)
            cache[k] = v
            return v
        end,
        --- Get the value from the memo cache.
        --- @param k any The key to look up in the cache.
        --- @return unknown The value from the cache, or `nil` if not found.
        get_cache = function(k)
            return cache[k]
        end,
        --- Memoize a function call, caching the result in the memo cache.
        --- @param fn any The function to memoize.
        --- @param ... any The arguments to pass to the function.
        --- @return any The result of the function call or the cached result or the original value if not a function.
        memo = function(fn, ...)
            if type(fn) ~= "function" then
                return fn
            end

            local result = cache[fn]
            if result ~= nil then
                return unpack(result)
            end

            result = { fn(...) }
            cache[fn] = result
            return unpack(result)
        end
    }
    Sessions[lastest_sid] = session
    return session
end

--- Destroy a session and free its backing store.
--- Resets the id counter when the last session is removed.
---@param sid SessionId
local function remove(sid)
    Sessions[sid] = nil
    if next(Sessions) == nil then
        lastest_sid = 0
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
