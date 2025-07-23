local vim = vim
local opt = vim.opt
local ipairs, concat = ipairs, table.concat

local M = {}

--- @type string[], integer The list of render value of component .
local Values, ValuesSize = {}, 0

M.clear = function()
	Values = {}
	ValuesSize = 0
	opt.statusline = " "
end

M.get_size = function()
	return ValuesSize
end

M.render = function()
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
	for _, idx in ipairs(indices) do
		Values[idx] = value
	end
end

--- Sets the separator for left or right side of the component.
--- @param indices integer[]|string[] The indices of the components to set the separator for.
--- @param value string The separator value to set.
--- @param is_left boolean If true, sets the separator to the left of the component; otherwise, sets it to the right.
M.bulk_set_sep = function(indices, value, is_left)
	for _, idx in ipairs(indices) do
		local sep_idx = is_left and idx - 1 or idx + 1
		Values[sep_idx] = value
	end
end

M.set = function(idx, value)
	Values[idx] = value
end

M.get = function(idx)
	return Values[idx]
end

return M
