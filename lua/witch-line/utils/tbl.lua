--- Utility functions for table manipulation and serialization
local M = {}

local type, pairs, tostring, loadstring = type, pairs, tostring, loadstring

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
		return string.dump(v, true)
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
--- @param tbl any The value to hash. If it's not a table, a constant hash is returned.
--- @param hash_key string|nil A specific key in the table to use for hashing. If provided and the table contains this key, its value will be used as the hash representation of the table.
--- @return number hash The computed FNV-1a 32-bit hash of the table.
function M.fnv1a32_hash(tbl, hash_key)
	-- invalid type then return an 32 bit constant number
	if type(tbl) ~= "table" or next(tbl) == nil then
		return 0xFFFFFFFF
	end


	local str_buffer, str_buffer_size = {}, 0
	local stack, stack_size = { tbl }, 1
	local seen = { [tbl] = true }
	local current, keys, keys_size -- instance

	while stack_size > 0 do
		current = stack[stack_size]
		stack_size = stack_size - 1
		if hash_key and current[hash_key] then
			-- use specific hash for table if available
			str_buffer_size = str_buffer_size + 1
			str_buffer[str_buffer_size] = simple_serialize(current[hash_key])
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
				str_buffer_size = str_buffer_size + 1
				str_buffer[str_buffer_size] = simple_serialize(k)

				-- Add value
				str_buffer_size = str_buffer_size + 1
				if type(v) == "table" then
					if not seen[v] then
						seen[v] = true
						stack_size = stack_size + 1
						stack[stack_size] = v
					end
					str_buffer[str_buffer_size] = "vtable"
				else
					str_buffer[str_buffer_size] = simple_serialize(v)
				end
			end
		end
	end
	return require("witch-line.utils.hash").fnv1a32_fold(str_buffer, 1, str_buffer_size)
end

--- Gradually computes the FNV-1a 32-bit hash of a table.
--- This function returns an iterator that yields the hash in chunks, allowing for processing large tables without
--- blocking the main thread.
--- @param tbl any The value to hash. If it's not a table, a constant hash is returned.
--- @param bulk_size number|nil The number of key-value pairs to process in each iteration. Default is 10.
--- @param hash_key any|nil A specific key in the table to use for hashing. If provided and the table contains this key, its value will be used as the hash representation of the table.
--- @return fun(): (number|nil, number|nil) iterator An iterator function that returns the iteration count and the current hash value.
function M.fnv1a32_hash_gradually(tbl, bulk_size, hash_key)
	local iteration = 0

	-- invalid type then return an 32 bit constant number
	if type(tbl) ~= "table" or next(tbl) == nil then
		return function()
			iteration = iteration + 1
			return iteration == 2 and nil or iteration, 0xFFFFFFFF
		end
	end


	bulk_size = bulk_size or 10
	local fvn1a32_fold = require("witch-line.utils.hash").fnv1a32_fold
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
						local hash = fvn1a32_fold(buf, 1, buf_size)
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
						local hash = fvn1a32_fold(buf, 1, buf_size)
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
					local hash = fvn1a32_fold(buf, 1, buf_size)
					buf_size = 0
					return iteration, hash
				end
			end
			current = nil
		end
	end
end

-- -- Hàm serialize một giá trị bất kỳ
-- local function serialize_value(v, indent)
-- 	indent = indent or ""
-- 	local t = type(v)
-- 	if t == "number" or t == "boolean" then
-- 		return tostring(v)
-- 	elseif t == "string" then
-- 		return string.format("%q", v) -- thêm dấu nháy + escape ký tự đặc biệt
-- 	elseif t == "table" then
-- 		return serialize_table(v, indent)
-- 	else
-- 		error("Unsupported type: " .. t)
-- 	end
-- end

-- -- Hàm serialize table
-- M.serialize_table = function(tbl, indent)
-- 	indent = indent or ""
-- 	local next_indent = indent .. "  "
-- 	local parts = { "{" }

-- 	for k, v in pairs(tbl) do
-- 		local key
-- 		if type(k) == "string" and k:match("^[_%a][_%w]*$") then
-- 			key = k .. " = "
-- 		else
-- 			key = "[" .. serialize_value(k, next_indent) .. "] = "
-- 		end

-- 		table.insert(parts, "\n" .. next_indent .. key .. serialize_value(v, next_indent) .. ",")
-- 	end

-- 	table.insert(parts, "\n" .. indent .. "}")
-- 	return table.concat(parts)
-- end

---Urly name to reduce collision with t==able key
local META_FUNC = "V_REF@@__q@@$$whaw2EWdjDSldkvj23@@19"
local META_TBL = "TBL_KEYS__dcjvlwkiwEEW3df2df ##S"

--- Encode functions in a table recursively
--- Support for function and table only. Other types are returned unexpected values
--- Support for table with number or string key only
--- If value is table and contains reference data as a key then  it will throw an error
--- @param value function|table The value to encode
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return string|table The encoded value. If the input is a function, it returns a string. If it's a table, it returns a table with functions encoded as strings.
function M.serialize_function(value, seen)
	local t = type(value)
	if t == "function" then
		return string.dump(value)
	elseif t == "string" or t == "number" or t == "boolean" then
		---@diagnostic disable-next-line
		return value
	elseif t ~= "table" then
		error("Unsupported type: " .. t .. " for value: " .. vim.inspect(value))
		---@diagnostic disable-next-line
		return nil
	end
	seen = seen or {}

	-- Already seen this table, avoid infinite loops
	if seen[value] then
		return value
	end
	seen[value] = true

	setmetatable(value, nil)

	--- Store the key name of encoded functions, and table key name which contains encoded functions or table
	--- We use this to decode later
	--- Example:
	--- value = {
	---  a = 1,
	---  b = "string",
	---  c = {
	---   d = 2,
	---   nested_func = function() print("Hello") end,
	---  },
	---  func1 = <function>,
	---  func2 = <function>,
	--- }
	--- After encoding:
	--- value = {
	---  a = 1,
	---  b = "string",
	---  func1 = <string>,
	---  func2 = <string>,
	---  [META_FUNC] = {"func1", "func2"},
	---  [META_TBL] = { "c" }  -- because c contains a nested functions
	--- }
	local meta_func = value[META_FUNC] or {}
	local meta_tbl = value[META_TBL] or {}

	for k, v in pairs(value) do
		local k_type = type(k)
		if k_type ~= "string" and k_type ~= "number" and k_type ~= "boolean" then
			error("Unsupported key type: " .. k_type .. " for key: " .. vim.inspect(k))
		elseif type(v) == "function" then
			meta_func[#meta_func + 1] = k
			value[k] = M.serialize_function(v, seen)
		elseif type(v) == "table" then
			v = M.serialize_function(v, seen)
			if v[META_FUNC] or v[META_TBL] then
				meta_tbl[#meta_tbl + 1] = k
			end
			value[k] = v
		end
	end

	--- Only set the meta keys if there are encoded functions or tables
	if next(meta_func) then
		value[META_FUNC] = meta_func
	end

	---	 Only set the meta keys if there are encoded functions or tables
	if next(meta_tbl) then
		value[META_TBL] = meta_tbl
	end

	return value
end

--- Decode functions in a table recursively or load function from string encoded by `M.encode_functions`
--- Support for string or table only. Other types are returned unexpected values
--- @param value string|table The value encoded by `M.encode_functions`
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return function|table The decoded value. If the input is a string, it returns a function or the original string if loading fails. If it's a table, it returns a table with strings decoded back to functions.
function M.deserialize_function(value, seen)
	local t = type(value)
	if t == "string" then
		local func = loadstring(value)
		--- @diagnostic disable-next-line
		return func or value
	elseif t ~= "table" then
		return value
	end

	seen = seen or {}
	-- Already seen this table, avoid infinite loops
	if seen[value] then
		return value
	end
	seen[value] = true

	local encoded_tbls = value[META_TBL]
	if encoded_tbls then
		--- Decode nested tables first
		for i = 1, #encoded_tbls do
			local key = encoded_tbls[i]
			value[key] = M.deserialize_function(value[key], seen)
		end
	end


	--- Start decoding functions in the current table
	local funs = value[META_FUNC]
	if funs then
		for i = 1, #funs do
			local k = funs[i]
			local func, err = loadstring(value[k])
			if not func then
				error("Failed to load function from string: " .. err)
			else
				value[k] = func
			end
		end

		--- Remove encoded function keys from the value as they are no longer needed
		value[META_FUNC] = nil
	end
	--- Remove encoded table keys from the value as they are no longer needed
	value[META_TBL] = nil
	return value
end

--- Serialize a table to a string
--- Functions in the table are encoded to strings using `M.serialize_function`
--- @param tbl table The table to serialize
--- @return string str The serialized table as a string
M.serialize_table = function(tbl, pretty)
  assert(type(tbl) == "table")
  local L = {}
  -- function L.serialize_value(v)
  --   local t = type(v)
  --   if t == "number" or t == "boolean" then
  --     return tostring(v)
  --   elseif t == "string" then
  --     return string.format("%q", v)
  --   elseif t == "table" then
  --     return L.serialize_table(v)
  --   else
  --     error("Unsupported type: " .. t)
  --   end
  -- end
  -- function L.serialize_table(t)
  --   ---@diagnostic disable-next-line
  --   local parts = { "{" }
  --   for k, v in pairs(t) do
  --     local key
  --     if type(k) == "string" and k:match("^[_%a][_%w]*$") then
  --       key = k .. "="
  --     else
  --       key = "[" .. L.serialize_value(k) .. "]="
  --     end
  --     parts[#parts + 1] = key .. L.serialize_value(v) .. ","
  --   end
  --   parts[#parts + 1] = "}"
  --   return table.concat(parts)
  -- end
  function L.serialize_value(v,indent)
    local t = type(v)
    if t == "number" or t == "boolean" then
      return tostring(v)
    elseif t == "string" then
      return string.format("%q", v)
    elseif t == "table" then
      return L.serialize_table(v,indent)
    else
      error("Unsupported type: " .. t)
    end
  end
  function L.serialize_table(t,indent)
    ---@diagnostic disable-next-line
    indent = indent or 0
    local parts = { "{" }
    local first = true

    for k, v in pairs(t) do
      local key
      if type(k) == "string" and k:match("^[_%a][_%w]*$") then
        key = k .. "="
      else
        key = "[" .. L.serialize_value(k) .. "]="
      end
      if pretty then
        if first then
          parts[#parts + 1] = "\n"
          first = false
        end
        parts[#parts + 1] = string.rep(" ", indent + 2)
        parts[#parts + 1] = key .. L.serialize_value(v, indent + 2) .. ",\n"
      else
        parts[#parts + 1] = key .. L.serialize_value(v, indent + 2) .. ","
      end
    end
    if pretty and not first then
      parts[#parts + 1] = string.rep(" ", indent)
    end
    parts[#parts + 1] = "}"
    return table.concat(parts)
  end
  return L.serialize_table(M.serialize_function(tbl))
end

--- Deserialize a table from a strings
--- @param str string The string serialized by `M.serialize_table`
--- @return table tbl The deserialized table with functions decoded back to functions
function M.deserialize_table(str)
	local func, err = loadstring("return " .. str)
	if not func then
		error("Failed to load table from string: " .. err)
	end
	local ok, result = pcall(func)
	if not ok then
		error("Error executing loaded string: " .. result)
	end

	result = M.deserialize_function(result)
	--- @cast result table
	return result
end

--- Serialize a table to Lua bytecode
--- @param tbl table The table to serialize
--- @return string bytecode The serialized table as Lua bytecode
function M.serialize_table_as_bytecode(tbl)
	local str = M.serialize_table(tbl,false)

	local func, err = loadstring("return " .. str)
	if not func then
		error("Failed to load table from string: " .. err)
	end
	return string.dump(func)
end

--- Deserialize a table from Lua bytecode
--- @param bytecode string The Lua bytecode serialized by `M.serialize_table_as_bytecode
--- @return table tbl The deserialized table with functions decoded back to functions
function M.deserialize_table_from_bytecode(bytecode)
	local func, err = loadstring(bytecode)
	if not func then
		error("Failed to load bytecode: " .. err)
	end
	local ok, result = pcall(func)
	if not ok then
		error("Error executing loaded bytecode: " .. result)
	end
	result = M.deserialize_function(result)
	--- @cast result table
	return result
end

-- -- ví dụ
-- local t = {
-- 	name = "Carolina",
-- 	age = 29,
-- 	skills = { "Lua", "Python", "Astrology" },
-- 	info = { city = "Tien Giang", active = true }
-- }

-- print(serialize_table(t))


return M
