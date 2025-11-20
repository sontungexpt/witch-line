local require, setmetatable = require, setmetatable

local lazy_meta = {
	__index = function(self, key)
		local val = require(self._________p)[key]
		self[key] = val
		return val
	end,
}

--- Lazily require a module without creating extra tables per field access.
--- Loads the module only on first access, then caches it.
--- @param path string The module path (e.g. "myplugin.utils")
--- @return table Proxy to the module
return function(path)
	return setmetatable({ _________p = path }, lazy_meta)
end

-- return lazy_require
