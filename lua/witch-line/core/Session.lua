local Store = setmetatable({}, {
	__mode = "k",
})

local Session = {}

---@alias SessionId function

--- @return SessionId id of new session
Session.new = function()
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

return Session
