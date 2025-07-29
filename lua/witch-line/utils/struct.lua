local M = {}

--- The helper function to create a custom for default component
--- @param path string The path to the component.
--- @param override table The override table for the component.
M.override_comp = function(path, override)
	return {
		[0] = path,
		override = override,
	}
end

return M
