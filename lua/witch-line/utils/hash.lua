local type, pairs, string_dump = type, pairs, string.dump
local ffi = require("ffi")
local bit = require("bit")

local uint32_t = ffi.typeof("uint32_t")

-- local FNV_PRIME_32  = 0x01000193
-- local FNV_OFFSET_32 = 0x811C9DC5
local FNV_PRIME_32_FFI = uint32_t(0x01000193)
local FNV_OFFSET_32_FFI = uint32_t(0x811C9DC5)

--- Calculates the FNV-1a 32-bit hash of a string.
--- Uses FFI uint32_t for automatic 32-bit overflow (no bit.band needed).
--- @param str string The input string to hash.
--- @return integer hash The resulting FNV-1a 32-bit hash.
local fnv1a32_str = function(str)
	local len = #str
	local ptr = ffi.cast("const uint8_t*", str)
	local hash = FNV_OFFSET_32_FFI
	local bxor = bit.bxor
	for i = 0, len - 1 do
		hash = bxor(hash, ptr[i]) * FNV_PRIME_32_FFI
	end
	---@diagnostic disable-next-line: return-type-mismatch
	return tonumber(hash)
end

--- Calculates the FNV-1a 32-bit hash of concatenated strings.
--- Accepts an array of strings and optional i..j range.
--- @param strs string[] The array of strings to hash.
--- @param i integer|nil The starting index (1-based). Defaults to 1.
--- @param j integer|nil The ending index (1-based). Defaults to #strs.
--- @return integer hash The resulting FNV-1a 32-bit hash.
local fnv1a32_str_fold = function(strs, i, j)
	local last = j or #strs
	if last > 100 then
		return fnv1a32_str(table.concat(strs, "", i or 1, last))
	end

	local hash = FNV_OFFSET_32_FFI
	local bxor = bit.bxor
	for l = i or 1, last do
		local str = strs[l]
		local len = #str
		local ptr = ffi.cast("const uint8_t*", str)
		for k = 0, len - 1 do
			hash = bxor(hash, ptr[k]) * FNV_PRIME_32_FFI
		end
	end
	---@diagnostic disable-next-line: return-type-mismatch
	return tonumber(hash)
end

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
		return string_dump(v, true)
	end
	return t
end

-- Comparator for only number + string
local function less(a, b)
	local ta, tb = type(a), type(b)
	return ta == tb and a < b or ta < tb
end

--- Computes the FNV-1a 32-bit hash of a table.
--- This function handles nested tables and ensures that the hash is consistent regardless of the order of keys.
--- @param tbl table The value to hash. If it's not a table, a constant hash is returned.
--- @param hash_key string|nil A specific key in the table to use for hashing. If provided and the table contains this key, its value will be used as the hash representation of the table.
--- @return number hash The computed FNV-1a 32-bit hash of the table.
--- @note If speed is very important consider directly hash inside this function instead of calling fnv1a32 hash
local fnv1a32_tbl = function(tbl, hash_key)
	-- invalid type then return an 32 bit constant number
	if not next(tbl) then
		return 0xFFFFFFFF
	end

	local buffer, buffer_size = {}, 0
	local stack, stack_size = { tbl }, 1
	local seen = { [tbl] = true }
	local current, keys, keys_size -- instance

	while stack_size > 0 do
		current = stack[stack_size]
		stack_size = stack_size - 1

		if hash_key and current[hash_key] then
			-- use specific hash for table if available
			buffer_size = buffer_size + 1
			buffer[buffer_size] = simple_serialize(current[hash_key])
		else
			-- asign the default values
			keys, keys_size = {}, 0
			for k in pairs(current) do
				keys_size = keys_size + 1
				local i = keys_size
				while i > 1 and less(k, keys[i - 1]) do
					keys[i] = keys[i - 1]
					i = i - 1
				end
				keys[i] = k
			end

			for i = 1, keys_size do
				local k = keys[i]
				local v = current[k]

				--- Add key
				buffer_size = buffer_size + 1
				buffer[buffer_size] = simple_serialize(k)

				-- Add value
				buffer_size = buffer_size + 1
				if type(v) == "table" then
					if not seen[v] then
						seen[v] = true
						stack_size = stack_size + 1
						stack[stack_size] = v
					end
					buffer[buffer_size] = "vtable"
				else
					buffer[buffer_size] = simple_serialize(v)
				end
			end
		end
	end
	return fnv1a32_str_fold(buffer, 1, buffer_size)
end

--- Gradually computes the FNV-1a 32-bit hash of a table.
--- This function returns an iterator that yields the hash in chunks, allowing for processing large tables without blocking the main thread. @param tbl any The value to hash. If it's not a table, a constant hash is returned.
--- @param bulk_size number|nil The number of key-value pairs to process in each iteration. Default is 10.
--- @param hash_key any|nil A specific key in the table to use for hashing. If provided and the table contains this key, its value will be used as the hash representation of the table.
--- @return fun(): (number|nil, number|nil) iterator An iterator function that returns the iteration count and the current hash value.
local fnv1a32_tbl_gradually = function(tbl, bulk_size, hash_key)
	local iteration = 0

	-- invalid type then return an 32 bit constant number
	if type(tbl) ~= "table" or next(tbl) == nil then
		return function()
			iteration = iteration + 1
			return iteration == 2 and nil or iteration, 0xFFFFFFFF
		end
	end

	bulk_size = bulk_size or 10
	local buf, buf_size = {}, 0

	local stack, stack_size = { tbl }, 1
	local seen = { [tbl] = true }
	local current, keys, keys_size, key_idx -- instance

	return function()
		iteration = iteration + 1
		while true do
			if not current then
				if stack_size < 1 then
					-- last hash
					if buf_size > 0 then
						local hash = fnv1a32_str_fold(buf, 1, buf_size)
						buf_size = 0
						return iteration, hash
					end
					return nil, nil -- No more items to process
				end
				-- get and remove last positions
				-- we don't really remove last element but we decrease the size by 1 and
				-- then if we add new element we just asign new value for more performance
				current = stack[stack_size]
				stack_size = stack_size - 1
				if hash_key and current[hash_key] ~= nil then
					-- use specific hash for table if available
					buf_size = buf_size + 1
					buf[buf_size] = simple_serialize(current[hash_key])
					current = nil
					if buf_size >= bulk_size * 2 then
						local hash = fnv1a32_str_fold(buf, 1, buf_size)
						buf_size = 0
						return iteration, hash
					end

					-- return iteration, fvn1a32_fold(buf, 1, buf_size)
				end
				-- asign the default values
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
						stack_size = stack_size + 1
						stack[stack_size] = v
						seen[v] = true
					end

					buf[buf_size] = "vtable"
				else
					buf[buf_size] = simple_serialize(v)
				end
				key_idx = key_idx + 1

				-- *2 because one for key and one for value
				if buf_size >= bulk_size * 2 then
					local hash = fnv1a32_str_fold(buf, 1, buf_size)
					buf_size = 0
					return iteration, hash
				end
			end
			current = nil
		end
	end
end

local fnv1a32 = function(v, hash_key)
	local t = type(v)
	if t == "table" then
		return fnv1a32_tbl(v, hash_key)
	elseif t == "string" then
		return fnv1a32_str(v)
	elseif t == "function" then
		return fnv1a32_str(string.dump(v, true))
	end
	return 0xFFFFFFFF
end

return {
	fnv1a32_str = fnv1a32_str,
	fnv1a32_str_fold = fnv1a32_str_fold,
	fvn1a32_tbl = fnv1a32_tbl,
	fnv1a32_tbl_gradually = fnv1a32_tbl_gradually,
	fnv1a32 = fnv1a32,
}
