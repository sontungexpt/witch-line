--- Utility functions for table manipulation and serialization
local M = {}

local type, pairs = type, pairs

--- Removes duplicate entries from a list
--- @generic T
--- @param list T[] The list to process.
--- @return T[] unique A new list containing only unique elements from the input list.
--- @return integer number The size of the result
M.unique_list = function(list)
	local set = {}
	for i = 1, #list do
		set[list[i]] = true
	end
	local keys, n = {}, 0
	for k in pairs(set) do
		n = n + 1
		keys[n] = k
	end
	return keys, n
end

--- Creates a shallow copy of a table.
--- @generic T
--- @param tbl T The table to copy.
--- @return T copied A new table that is a shallow copy of the input table.
M.shallow_copy = function(tbl)
	local copy = {}
	for k, v in pairs(tbl) do
		copy[k] = v
	end
	return copy
end

--- Checks if all elements of one table are present in another.
--- @param a table The first table to check.
--- @param b table The second table to check against.
--- @return boolean true Returns true if all elements of `b` are in `a`, false otherwise.
M.is_superset = function(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end

	local map = {}
	for _, v in ipairs(a) do
		map[v] = true
	end

	for _, v in ipairs(b) do
		if not map[v] then
			return false
		end
	end
	return true
end

return M
