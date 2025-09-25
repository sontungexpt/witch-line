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
	-- Serialize value for hashing
	local function simple_serialize(v)
		local t = type(v)
		if t == "string" then
			return v
		elseif t == "number" then
			return tostring(v)
		elseif t == "boolean" then
			return v and "1" or "0"
		elseif t == "function" then
			return string.dump(v)
		end
		return t
	end

	local iteration = 0

	if type(tbl) ~= "table" or next(tbl) == nil then
		return function()
			iteration = iteration + 1
			if iteration == 1 then
				return nil, nil -- No more items to process
			end
			return iteration, require("witch-line.utils.hash").fnv1a32(simple_serialize(tbl))
		end
	end

   -- Comparator for only number + string
    local function less(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
            return a < b
        elseif ta == "number" and tb == "string" then
            return true   -- numbers come before strings
        elseif ta == "string" and tb == "number" then
            return false
        else
            -- fallback: compare tostring (in case weird types slip in)
            return tostring(a) < tostring(b)
        end


	local sort, remove = table.sort, table.remove
	local fnv1a_32_concat = require("witch-line.utils.hash").fnv1a32_concat
	bulk_size = bulk_size or 10
	local keys, keys_size, key_idx = {}, 0, 1
	local buf, buf_size = {}, 0

	local queue = { tbl }
	local seen = { [tbl] = true }
	local current = nil
	return function()
		iteration = iteration + 1
		while true do
			if not current then
				current = remove(queue)
				if not current then
					-- last hash
					if buf_size > 0 then
						local hash = fnv1a_32_concat(buf, 1, buf_size)
						buf_size = 0
						return iteration, hash
					end
					return nil, nil -- No more items to process
				end

				keys, keys_size, key_idx = {}, 0, 1
				for k in pairs(current) do
					keys_size = keys_size + 1
local i = keys_size
                    while i > 1 and less(k, keys[i - 1]) do
                        keys[i] = keys[i - 1]
                        i = i - 1
                    end
                    keys[i] = k

				end
				
			end

			while key_idx <= keys_size do
				local k = keys[key_idx]
				local v = current[k]

				--- Add key
				buf_size = buf_size + 1
				buf[buf_size] = simple_serialize(k)

				-- Add value
				buf_size = buf_size + 1
				if type(v) == "table" then
					if not seen[v] then
						queue[#queue + 1] = v
						seen[v] = true
					end

					buf[buf_size] = "table_value"
				else
					buf[buf_size] = simple_serialize(v)
				end
				key_idx = key_idx + 1

				-- *2 because one for key and one for value
				if buf_size >= bulk_size * 2 then
					local hash = fnv1a_32_concat(buf)
					buf_size = 0
					return iteration, hash
				end
			end
			current = nil
		end
	end
end

return M
