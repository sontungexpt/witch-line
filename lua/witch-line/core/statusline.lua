local vim, concat = vim, table.concat
local opt = vim.opt
local CacheMod = require("witch-line.cache")

local M = {}
local enabled = true

--- @type string[] The list of render value of component .
local Values = {}

---@type integer
local ValuesSize = 0

--- Hidden all components by setting their values to empty strings.
M.empty_values = function()
	for i = 1, ValuesSize do
		Values[i] = ""
	end
end

M.cache = function()
	--reset the values to empty strings
	--before caching
	--because when the plugin is loaded
	--the statusline must be empty stage
	M.empty_values()
	CacheMod.cache(Values, "Statusline")
	CacheMod.cache(ValuesSize, "StatuslineSize")
end

M.load_cache = function()
	local cache = CacheMod.get()
	Values = cache.Statusline or Values
	ValuesSize = cache.StatuslineSize or ValuesSize
end

M.clear = function()
	Values = {}
	ValuesSize = 0
	opt.statusline = " "
end

M.get_size = function()
	return ValuesSize
end

M.render = function()
	if not enabled then
		opt.statusline = " "
		return
	end

	local str = concat(Values)
	opt.statusline = str ~= "" and str or " "
end

M.push = function(value)
	ValuesSize = ValuesSize + 1
	Values[ValuesSize] = value
	return ValuesSize
end

--- Sets the value for multiple components at once.
--- @param indices integer[] The indices of the components to set the value for.
--- @param value string The value to set for the specified components.
M.bulk_set = function(indices, value)
	for i = 1, #indices do
		Values[indices[i]] = value
	end
end

--- Sets the separator for left or right side of the component.
--- @param indices integer[]|string[] The indices of the components to set the separator for.
--- @param value string The separator value to set.
--- @param adjust number If true, sets the separator to the left of the component; otherwise, sets it to the right.
M.bulk_set_sep = function(indices, value, adjust)
	for i = 1, #indices do
		Values[indices[i] + adjust] = value
	end
end

M.set = function(idx, value)
	Values[idx] = value
end

M.get = function(idx)
	return Values[idx]
end

return M
