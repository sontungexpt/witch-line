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

--- Check if two arrays contain the same elements (order does not matter)
--- The function works by:
--- 1. Counting occurrences of each element in array `a`
--- 2. Decreasing those counts based on elements in array `b`
--- 3. If all counts cancel out (i.e., table `count` is empty) → arrays are equal
---
--- ⚙️ Complexity:
--- - Time: O(n)
--- - Space: O(n)
--- - Ignores element order
--- - Suitable for primitive types (number, string, boolean)
---
--- 🧩 Example:
--- ```lua
--- arrays_equal({1, 2, 3}, {3, 1, 2})   --> true
--- arrays_equal({1, 2, 3}, {1, 2, 4})   --> false
--- arrays_equal({"a", "b"}, {"b", "a"}) --> true
--- ```
---
--- @param a table The first array
--- @param b table The second array
--- @return boolean True if both arrays contain the same elements (regardless of order)
M.array_equal = function(a, b)
	local len = #a
	if len ~= #b then
		return false
	end

	-- Count element occurrences in array `a`
	local count = {}

	for i = 1, len do
		local v = a[i]
		count[v] = (count[v] or 0) + 1
	end

	-- Decrease the count for each element found in array `b`
	for i = 1, len do
		local v = b[i]
		local c = count[v]
		if not c then
			-- Element in `b` not found in `a`
			return false
		end
		if c == 1 then
			-- Remove entry when count reaches zero to keep table small
			count[v] = nil
		else
			count[v] = c - 1
		end
	end

	-- If `count` is empty, both arrays are identical
	return next(count) == nil
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
