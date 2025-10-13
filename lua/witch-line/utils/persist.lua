local type, pairs, tostring, load = type, pairs, tostring, load

local M= {}
---Urly name to reduce collision with t==able key
local META_FUNC = "V_REF@@__q@@$$whaw2EWdjDSldkvj23@@19"
local META_TBL = "TBL_KEYS__dcjvlwkiwEEW3df2df ##S"

--- Encode functions in a table recursively
--- Support for function and table only. Other types are returned unexpected values
--- Support for table with number or string key only
--- If value is table and contains reference data as a key then  it will throw an error
--- @param value function|table The value to encode. If value is table then the function will serialize all method of the table
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

	-- setmetatable(value, nil)

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
		local func = load(value, nil, "b")
		-- local func = loadstring(value)
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
			-- local func, err = loadstring(value[k], k)
			local func, err = load(value[k], k, "b")
			if err then
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
  local ffi = require("ffi")
  local L = {}
  function L.serialize_value(v,indent)
    local t = type(v)
    if t == "number" or t == "boolean" then
      return tostring(v)
    elseif t == "string" then
      return string.format("%q", v)
    elseif t == "table" then
      return L.serialize_table(v,indent)
      --- Support ffi style
    elseif t == "cdata" then
      -- Check if it's a string
      if ffi.istype("const char*", v) or ffi.istype("char*", v) then
        return string.format("%q", ffi.string(v))
      elseif ffi.istype("int8_t", v) or ffi.istype("uint8_t", v) or
             ffi.istype("int16_t", v) or ffi.istype("uint16_t", v) or
             ffi.istype("int32_t", v) or ffi.istype("uint32_t", v) or
             ffi.istype("int64_t", v) or ffi.istype("uint64_t", v) or
             ffi.istype("float", v) or ffi.istype("double", v) then
        return tostring(v)
      elseif ffi.istype("bool", v) then
        return tostring(v)
      else
        error("Unsupported cdata type: " .. tostring(ffi.typeof(v)))
      end
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
	local func, err = load("return " .. str)
	if not func then
		error("Failed to load table from string: " .. err)
	end
	local result = M.deserialize_function(func())
  if type(result) ~= "table" then
    error("Deserialized string did not return a table")
  end
	return result
end

--- Serialize a table to Lua bytecode
--- @param tbl table The table to serialize
--- @return string bytecode The serialized table as Lua bytecode
function M.serialize_table_as_bytecode(tbl)
	local str = M.serialize_table(tbl,false)

	local func, err = load("return " .. str)
	if not func then
		error("Failed to load table from string: " .. err)
	end
	return string.dump(func)
end

--- Deserialize a table from Lua bytecode
--- @param bytecode string The Lua bytecode serialized by `M.serialize_table_as_bytecode
--- @return table tbl The deserialized table with functions decoded back to functions
function M.deserialize_table_from_bytecode(bytecode)
	-- local func, err = loadstring(bytecode)
	local func, err = load(bytecode, nil, "b")
	if not func then
		error("Failed to load bytecode: " .. err)
	end

	local result = M.deserialize_function(func())
  if type(result) ~= "table" then
    error("Deserialized bytecode did not return a table")
  end
	return result
end

return M
