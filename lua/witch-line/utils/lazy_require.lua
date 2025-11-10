local require, setmetatable, rawget, rawset = require, setmetatable, rawget, rawset

local lazy_meta = {
	__index = function(self, key)
		local mod = rawget(self, "____m")
		if not mod then
			mod = require(self.____p)
			rawset(self, "____m", mod)
		end
		return mod[key]
	end,
}

--- Lazily require a module without creating extra tables per field access.
--- Loads the module only on first access, then caches it.
--- @param path string The module path (e.g. "myplugin.utils")
--- @return table Proxy to the module
local function lazy_require(path)
	return setmetatable({ ___p = path }, lazy_meta)
end

return lazy_require
