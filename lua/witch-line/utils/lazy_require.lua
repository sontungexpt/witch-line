local require, setmetatable = require, setmetatable

--- @type table<table, string>
local PathPool = {}

local lazy_meta = {
	__index = function(self, key)
		local val = require(PathPool[self])[key]
		self[key] = val
		return val
	end,
}

--- Lazily require a module without creating extra tables per field access.
--- Loads the module only on first access, then caches it.
--- @param path string The module path (e.g. "myplugin.utils")
--- @return table Proxy to the module
return function(path)
	local mod = setmetatable({}, lazy_meta)
	PathPool[mod] = path
	return mod
end

-- return lazy_require
