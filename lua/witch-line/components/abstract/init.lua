local ABSTRACT_PATH = "witch-line.components.abstract."
return setmetatable({}, {
	__index = function(_, key)
		-- ignore this module
		if key == "init" then
			return nil
		end
		local ok, module = pcall(require, ABSTRACT_PATH .. key)
		return ok and module or nil
	end,
})
