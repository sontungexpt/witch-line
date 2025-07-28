local type, pairs, tostring = type, pairs, tostring
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

-- Iterator function: returns next hash every bulk_size elements
function M.hash_fnv1a32_iter(tbl, bulk_size)
	local loop_time = 0

	if type(tbl) ~= "table" or next(tbl) == nil then
		return function()
			if loop_time > 0 then
				return nil, nil -- No more items to process
			end
			loop_time = loop_time + 1
			return loop_time, require("witch-line.utils.hash").fnv1a32(type(tbl))
		end
	end

	-- Serialize value for hashing
	local function serialize(v)
		local t = type(v)
		if t == "string" then
			return "s:" .. v
		elseif t == "number" then
			return "n:" .. tostring(v)
		elseif t == "boolean" then
			return "b:" .. tostring(v)
		elseif t == "nil" then
			return "nil"
		else
			return "u:" .. tostring(v) -- unsupported
		end
	end

	local sort, remove, concat = table.sort, table.remove, table.concat
	local fnv1a_32 = require("witch-line.utils.hash").fnv1a32
	bulk_size = bulk_size or 10
	local queue = { tbl }
	local current = nil
	local keys, keys_size, key_idx = {}, 0, 1
	local buf, buf_size = {}, 0
	local seen = {
		[tbl] = true,
	}
	return function()
		loop_time = loop_time + 1
		while true do
			if not current then
				current = remove(queue)
				if not current then
					return nil, nil -- No more items to process
				end
				keys, keys_size, key_idx = {}, 0, 1
				for k in pairs(tbl) do
					keys_size = keys_size + 1
					keys[keys_size] = k
				end
				sort(keys)
			end
			while key_idx <= keys_size do
				local k = keys[key_idx]
				local v = current[k]

				-- Add key
				buf_size = buf_size + 1
				if type(k) == "table" then
					if not seen[k] then
						queue[#queue + 1] = k
					end
					buf[buf_size] = "table_key"
				else
					buf[buf_size] = serialize(k)
				end

				-- Add value
				buf_size = buf_size + 1
				if type(v) == "table" then
					if not seen[v] then
						queue[#queue + 1] = v
					end
					buf[buf_size] = "table_value"
				else
					buf[buf_size] = serialize(v)
				end
				key_idx = key_idx + 1

				if buf_size >= bulk_size * 2 then
					local hash = fnv1a_32(concat(buf))
					buf_size = 0
					return loop_time, hash
				end
			end
			current = nil
		end
	end
end

return M
