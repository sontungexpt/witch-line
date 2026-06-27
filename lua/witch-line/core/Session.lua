local M = {}

--- @class SessionId : integer

--- @class Session
--- @field id SessionId
--- Get the value of a key in the session data.
--- @field get fun(k: any): any|nil
--- Get the value of a key in the session data.
--- @field set fun(k: any, v: any): any
--- Get the value of a key in the memo cache.
--- @field get_cache fun(k: any): any|nil
--- Set the value of a key in the memo cache.
--- @field set_cache fun(k: any, v: any): any
--- The memo cache is used to cache the results of memoized functions.
--- @field memo fun(fn: fun(...):any, ...: any): any, ...

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

    local session = {
        id = lastest_sid,
        set = function(k, v)
            data = data or {}
            data[k] = v
            return v
        end,
        get = function(k)
            return data[k]
        end,
        set_cache = function(k, v)
            cache[k] = v
            return v
        end,
        get_cache = function(k)
            return cache[k]
        end,
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
