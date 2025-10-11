local ffi = require("ffi")

ffi.cdef[[
  typedef struct {
    uint64_t id;
  } SessionId;
]]

local Store = {}
local Session = {}
local next_id = 0

--- @class SessionId

--- @return SessionId id of new session
local function new_session_id()
  next_id = next_id + 1
  local token = ffi.new("SessionId", next_id)

  ffi.gc(token, function(t)
    Store[t] = nil
  end)
  return token
end

--- @return SessionId id of new session
local new = function()
  local id = new_session_id()
	Store[id] = {}
	return id
end
Session.new = new

--- Sets the session data associated with the given session ID and key.
--- @param session_id SessionId id of the session
--- @param store_id NotNil key to retrieve session data
Session.new_store = function(session_id, store_id, value)
	local store = Store[session_id]
	if not store then
		error("Session with id " .. tostring(session_id) .. " does not exist.")
	end
	store[store_id] = value
	return value
end

--- Retrieves the session data associated with the given session ID and key.
--- If the key does not exist, it will create an empty table for that key.
--- @param session_id SessionId id of the session
--- @param store_id NotNil key to retrieve session data
Session.get_store = function(session_id, store_id)
	local store = Store[session_id]
	if not store then
		error("Session with id " .. tostring(session_id) .. " does not exist.")
	end

	local value = store[store_id]
	return value
end



--- Clears the session data associated with the given session ID.
--- @param id SessionId
local remove = function(id)
  Store[id] = nil
  ffi.gc(id, nil)  -- Remove the finalizer to avoid double-free
end
Session.remove = remove

--- Wraps a callback function in a new session.
--- This function creates a new session, calls the callback with the session ID,
--- and then removes the session when the callback is done.
--- @param cb fun(session_id: SessionId) Callback function to call if the session does not exist
Session.run_once = function(cb)
	local id = new()
	cb(id)
	remove(id)
end

return Session
