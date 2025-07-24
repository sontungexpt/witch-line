local Cache = setmetatable({}, {
	__mode = "k",
})

local Session = {}

---@alias SessionId function

--- @return SessionId id of new session
Session.new = function()
	local id = function() end
	Cache[id] = {}
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
--- @param id SessionId
--- @param key any
Session.get_or_init = function(id, key, initial_val)
	local session = Cache[id]
	if not session then
		error("Session with id " .. tostring(id) .. " does not exist.")
	elseif not key then
		error("Key must be provided to retrieve session data.")
	end

	local value = session[key] or initial_val
	session[key] = value

	return value
end

--- Clears the session data associated with the given session ID.
--- @param id SessionId
Session.remove = function(id)
	Cache[id] = nil
end

return Session
