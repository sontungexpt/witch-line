local pairs = pairs
local M = {}

function M.merge_tbl(to, from, skip_type_check)
	if to == nil then
		return from
	elseif from == nil then
		return to
	end

	local to_type = type(to)
	local from_type = type(from)

	if not skip_type_check and to_type ~= from_type then
		return to
	elseif from_type ~= "table" then
		return from
	elseif to_type == "table" then
		if vim.islist(to) and vim.islist(from) then
			-- If both are lists, merge them
			for _, v in ipairs(from) do
				to[#to + 1] = v
			end
			return to
		end

		for k, v in pairs(from) do
			to[k] = M.merge_tbl(to[k], v, skip_type_check)
		end
	end
	return to
end

--- Creates a shallow copy of a table.
--- @generic T
--- @param tbl T The table to copy.
--- @return T A new table that is a shallow copy of the input table.
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
