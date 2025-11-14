local M = {}

--- The helper function to create a custom for default component
--- @param path string The path to the component.
--- @param override table The override table for the component.
M.comp = function(path, override)
  assert(type(path) == "string", "Path must be a string")
  assert(type(override) == "table", "Override must be a table")

  override[0] = path
  return override
end

return M
