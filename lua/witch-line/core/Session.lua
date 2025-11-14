local next = next
local Store = {}
local Session = {}

--- @class SessionId : integer
local next_id = 0

--- @return SessionId id of new session
local new = function()
  next_id = next_id + 1
  Store[next_id] = {}
  return next_id
end
Session.new = new

--- Sets the session data associated with the given session ID and key.
--- @param sid SessionId id of the session
--- @param store_id NotNil key to retrieve session data
Session.new_store = function(sid, store_id, value)
  local store = Store[sid]
  if not store then
    error("Session with id " .. tostring(sid) .. " does not exist.")
  end
  store[store_id] = value
  return value
end

--- Retrieves the session data associated with the given session ID and key.
--- If the key does not exist, it will create an empty table for that key.
--- @param sid SessionId id of the session
--- @param store_id NotNil key to retrieve session data
--- @return any|nil value associated with the key, or nil if the key does not exist
Session.get_store = function(sid, store_id)
  local store = Store[sid]
  if not store then
    error("Session with id " .. tostring(sid) .. " does not exist.")
  end
  local value = store[store_id]
  return value
end

--- Clears the session data associated with the given session ID.
--- @param id SessionId
local remove = function(id)
  Store[id] = nil
  if not next(Store) then
    next_id = 0 -- reset id counter if no sessions exist
  end
end
Session.remove = remove

--- Wraps a callback function in a new session.
--- This function creates a new session, calls the callback with the session ID,
--- and then removes the session when the callback is done.
--- @param cb fun(sid: SessionId) Callback function to call if the session does not exist
Session.with_session = function(cb)
  local id = new()
  cb(id)
  remove(id)
end

return Session
