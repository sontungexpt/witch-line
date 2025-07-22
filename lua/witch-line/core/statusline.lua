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

M.bulk_set = function(indices, value)
	for _, idx in ipairs(indices) do
		Values[idx] = value
	end
end

M.set = function(idx, value)
	Values[idx] = value
end

M.get = function(idx)
	return Values[idx]
end

return M
