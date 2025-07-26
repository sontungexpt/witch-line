local Store = setmetatable({}, {
	__mode = "k",
})

local Session = {}

--- @return SessionId id of new session
Session.new = function()
	---@class SessionId
	local id = function() end
	Store[id] = {}
	return id
end

-- --- Retrieves the session data associated with the given session ID.
-- --- @param id SessionId
-- --- @return table
-- Session.get = function(id)
-- 	local session = Cache[id]
-- 	if not session then
-- 		error("Session with id " .. tostring(id) .. " does not exist.")
-- 	end
-- 	return session
-- end

---- Retrieves the session data associated with the given session ID and key.
--- If the key does not exist, it will create an empty table for that key.
--- @param session_id SessionId id of the session
--- @param store_id NotNil key to retrieve session data
--- @param init any initial value to set if the key does not exist
Session.get_store = function(session_id, store_id, init)
	local store = Store[session_id]
	if not store then
		error("Session with id " .. tostring(session_id) .. " does not exist.")
	end

	local value = store[store_id] or init
	if not value then
		error("You must provide an initial value for the store_id: " .. tostring(store_id))
	end
	store[store_id] = value
	return value
end

--- Clears the session data associated with the given session ID.
--- @param id SessionId
Session.remove = function(id)
	Store[id] = nil
end

--- Wraps a callback function in a new session.
--- This function creates a new session, calls the callback with the session ID,
--- and then removes the session when the callback is done.
--- @param cb fun(id: SessionId) Callback function to call if the session does not exist
Session.run_once = function(cb)
	local id = Session.new()
	cb(id)
	Session.remove(id)
end

return Session
