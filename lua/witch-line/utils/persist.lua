local type, pairs, tostring, load = type, pairs, tostring, load
local rshift = require("bit").rshift

local M = {} ---Urly name to reduce collision with t==able key
local META_FUNC = "__WITCH_META::FUNC::hQ92d@@GzL"
local META_TBL = "__WITCH_META::TBL::XpL3w9F@@"

--- Perform a binary search to locate the index of a given key in a sorted list.
---
--- This helper efficiently finds whether a function name (key) was encoded
--- by searching inside the sorted `meta_func` array.
--- Instead of returning a boolean, it returns the index position if found,
--- or `nil` otherwise — making it more flexible for future use cases.
---
--- Example:
--- ```lua
--- local idx = M.find_encoded_key(meta_func, "update_state")
--- if idx then
---   print("Encoded function found at index:", idx)
--- else
---   print("Not encoded")
--- end
--- ```
---
--- @param meta_func string[] Sorted list of encoded function key names.
--- @param key string Key name to search for.
--- @return integer index Index of the key if found, otherwise -1.
local function find_encoded_key(meta_func, key)
  local low, high = 1, #meta_func
  while low <= high do
    -- Bitwise shift right by 1 → faster than math.floor((low + high) / 2)
    local mid = rshift(low + high, 1)
    local mid_val = meta_func[mid]

    if key == mid_val then
      return mid
    elseif key < mid_val then
      high = mid - 1
    else
      low = mid + 1
    end
  end
  return -1
end

M.find_encoded_key = find_encoded_key

--- Check whether a given key refers to an encoded (lazy-loaded) function
--- and return its index position if found.
---
--- This function determines whether a table field corresponds to a
--- function that was serialized (encoded as bytecode).
--- It checks the `[META_FUNC]` list — which stores all encoded function keys —
--- using an efficient binary search (`find_encoded_key`).
---
--- Example:
--- ```lua
--- local idx = M.get_encoded_func_index(my_table, "on_render")
--- if idx then
---   print("Found encoded function at index:", idx)
--- else
---   print("Not encoded or invalid key")
--- end
--- ```
---
--- @param tbl table The table that may contain encoded functions.
--- @param key string The key name to check.
--- @return integer index Index position of the encoded key, or -1 if not encoded.
--- @return table|nil meta_func The metadata table (`META_FUNC`) used for lookup, or `nil` if unavailable.
local function find_encoded_func(tbl, key)
  assert(type(tbl) == "table")
  -- Retrieve metadata list of encoded function keys
  local meta_func = tbl[META_FUNC]
  if not meta_func then
    return -1, meta_func
  end
  -- Use binary search to locate index of the key
  return find_encoded_key(meta_func, key), meta_func
end

M.find_encoded_func = find_encoded_func

--- Lazily decode and prepare a function from bytecode.
---
--- This helper ensures that a serialized (bytecode) method inside a table
--- is compiled back into a callable Lua function **only when needed**.
--- Once decoded, the function is cached in-place, and its entry is removed
--- from the `[META_FUNC]` metadata list to avoid redundant decoding.
---
--- Behavior:
--- - If the value at `tbl[key]` is **already a function**, it is returned as-is.
--- - If it is a **string** and marked as encoded (via `[META_FUNC]`), the string
---   is compiled to a function using `load()` in binary mode, stored back into
---   the table, and returned.
--- - If the string is **not** marked as encoded, it is treated as a raw string.
---
--- Example:
--- ```lua
--- local func = M.lazy_decode(my_table, "on_click")
--- if type(func) == "function" then
---   func()  -- Safely invoke the lazily-decoded function
--- end
--- ```
---
--- @param tbl table The table containing the potentially encoded method.
--- @param key string The method name to decode and/or return.
--- @return any decoded The decoded function, or the original value if not encoded.
M.lazy_decode = function(tbl, key)
  -- Defensive check
  local val = tbl[key]
  if type(val) ~= "string" then
    return val
  end
  local idx, meta_func = find_encoded_func(tbl, key)
  if idx < 1 then
    -- raw string
    return val
  end

  -- Decode bytecode
  local func, err = load(val, nil, "b")
  if not func then
    error(("Failed to load function '%s' from bytecode: %s"):format(key, err))
    return
  end
  rawset(tbl, key, func)
  ---@cast meta_func table
  table.remove(meta_func, idx)
  if not meta_func[1] then
    tbl[META_FUNC] = nil
  end
  return func
end

--- Recursively serialize a table containing functions into a table of strings.
--- Only supports values of type `function`, `table`, `string`, `number`, or `boolean`.
--- Each function is converted to a Lua bytecode string using `string.dump`.
---
--- Tables are traversed recursively. To avoid infinite loops, a `seen` table is used.
--- For every table that contains functions or nested tables with functions,
--- metadata is stored under reserved keys:
---   • [META_FUNC] → a list of keys whose values were functions
---   • [META_TBL]  → a list of keys whose values are tables that contain encoded data
---
--- Example:
--- ```lua
--- local input = {
---   a = 1,
---   b = "string",
---   c = {
---     d = 2,
---     nested_func = function() print("Hello") end,
---   },
---   func1 = function() end,
---   func2 = function() end,
--- }
---
--- local result = serialize_tbl_func_rec(input)
---
--- -- Result:
--- -- {
--- --   a = 1,
--- --   b = "string",
--- --   func1 = <string>,  -- dumped function bytecode
--- --   func2 = <string>,
--- --   c = {
--- --     d = 2,
--- --     nested_func = <string>,
--- --     [META_FUNC] = { "nested_func" },
--- --   },
--- --   [META_FUNC] = { "func1", "func2" },
--- --   [META_TBL]  = { "c" },
--- -- }
--- ```
---
--- @param tbl table|function The table (or function) to serialize.
--- @param dumped_func_strip? boolean Whether to strip debug info when dumping functions.
--- @param seen table|nil Internal table to track visited tables and prevent circular references.
--- @return table|string serialized The serialized representation. Functions become bytecode strings; tables contain encoded keys.
local function serialize_tbl_funcs_rec(tbl, dumped_func_strip, seen)
  local t = type(tbl)
  if t == "function" then
    return string.dump(tbl, dumped_func_strip)
  elseif t ~= "table" then
    return tbl
  end
  seen = seen or {}

  -- Already seen this table, avoid infinite loops
  if seen[tbl] then
    return tbl
  end
  seen[tbl] = true

  local meta_func = tbl[META_FUNC] or {}
  local meta_tbl = tbl[META_TBL] or {}

  for k, v in pairs(tbl) do
    local k_type = type(k)
    if k_type ~= "string" and k_type ~= "number" and k_type ~= "boolean" then
      error("Unsupported key type: " .. k_type .. " for key: " .. vim.inspect(k))
    elseif type(v) == "function" then
      meta_func[#meta_func + 1] = k
      tbl[k] = serialize_tbl_funcs_rec(v, dumped_func_strip, seen)
    elseif type(v) == "table" then
      v = serialize_tbl_funcs_rec(v)
      if v[META_FUNC] or v[META_TBL] then
        meta_tbl[#meta_tbl + 1] = k
      end
      tbl[k] = v
    end
  end

  --- Only set the meta keys if there are encoded functions or tables
  if next(meta_func) then
    table.sort(meta_func)
    tbl[META_FUNC] = meta_func
  end

  ---	 Only set the meta keys if there are encoded functions or tables
  if next(meta_tbl) then
    table.sort(meta_tbl)
    tbl[META_TBL] = meta_tbl
  end

  return tbl
end

--- Encode functions in a table recursively
--- Support for function and table only. Other types are returned unexpected values
--- Support for table with number or string key only
--- If value is table and contains reference data as a key then  it will throw an error
--- @param value function|table The value to encode. If value is table then the function will serialize all method of the table
--- @param dumped_func_strip? boolean Whether to strip debug info when dumping functions.
--- @return string|table serialized The encoded value. If the input is a function, it returns a string. If it's a table, it returns a table with functions encoded as strings.
function M.serialize_function(value, dumped_func_strip)
  local t = type(value)
  if t == "function" then
    return string.dump(value)
  elseif t == "table" then
    return serialize_tbl_funcs_rec(value, dumped_func_strip, {})
  end
  error("Unsupported type: " .. t .. " for value: " .. vim.inspect(value))
end

--- Recursively deserialize encoded Lua tables containing functions and nested tables.
---
--- This function restores a serialized table where:
--- - Functions were encoded as Lua bytecode strings (`string.dump` results),
--- - Nested tables were tracked via metadata keys (`META_TBL`),
--- - Function keys were tracked via metadata keys (`META_FUNC`).
---
--- It safely traverses the table hierarchy, decodes all bytecode strings back into
--- callable functions using `load`, and removes metadata fields once processed.
---
--- Cyclic references are handled through the `seen` table to prevent infinite recursion.
---
--- @param tbl table The table (or bytecode string) to deserialize.
--- @param seen table|nil Internal map used to detect cyclic references (for recursion safety).
--- @return table deserialized The deserialized table (or original string if not bytecode).
local function deserialize_tbl_funcs_rec(tbl, seen)
  local t = type(tbl)
  if t == "string" then
    local func = load(tbl, nil, "b")
    -- local func = loadstring(value)
    --- @diagnostic disable-next-line
    return func or tbl
  elseif t ~= "table" then
    return tbl
  end

  seen = seen or {}
  -- Already seen this table, avoid infinite loops
  if seen[tbl] then
    return tbl
  end
  seen[tbl] = true

  local encoded_tbls = tbl[META_TBL]
  if encoded_tbls then
    --- Decode nested tables first
    for i = 1, #encoded_tbls do
      local key = encoded_tbls[i]
      tbl[key] = deserialize_tbl_funcs_rec(tbl[key], seen)
    end
  end

  --- Start decoding functions in the current table
  local funs = tbl[META_FUNC]
  if funs then
    for i = 1, #funs do
      local k = funs[i]
      -- local func, err = loadstring(value[k], k)
      local func, err = load(tbl[k], k, "b")
      if err then
        error("Failed to load function from string: " .. err)
      else
        tbl[k] = func
      end
    end

    --- Remove encoded function keys from the value as they are no longer needed
    tbl[META_FUNC] = nil
  end
  --- Remove encoded table keys from the value as they are no longer needed
  tbl[META_TBL] = nil
  return tbl
end

--- Decode functions in a table recursively or load function from string encoded by `M.encode_functions`
--- Support for string or table only. Other types are returned unexpected values
--- @param value string|table The value encoded by `M.encode_functions`
--- @return function|table deserialized The decoded value. If the input is a string, it returns a function or the original string if loading fails. If it's a table, it returns a table with strings decoded back to functions.
function M.deserialize_function(value)
  local t = type(value)
  if t == "string" then
    local func, err = load(value, nil, "b")
    if not func then
      error("Can not deserialize_function with string" .. value .. "err: " .. err)
    end
    return func
  elseif t == "table" then
    return deserialize_tbl_funcs_rec(value, {})
  end
  error("Unsupported type: " .. t .. " for value: " .. vim.inspect(value))
end

--- Serialize a Lua table into a string representation.
---
--- - Supports nested tables, primitive types (`number`, `boolean`, `string`).
--- - Optionally formats the output for readability (pretty-printing).
--- - Converts `ffi` cdata types into strings or numbers when possible.
--- - Functions in the table are first encoded using `M.serialize_function`
---   to ensure they can be safely represented as strings.
---
--- @param tbl table The table to serialize.
--- @param without_func boolean|nil Whether to skip serializing functions (default: false).
--- @param dumped_func_strip? boolean Whether to strip debug info when dumping functions.
--- @param pretty boolean|nil Whether to format the output with indentation and newlines (default: false).
--- @return string str A Lua string representation of the serialized table.
M.serialize_table = function(tbl, without_func, dumped_func_strip, pretty)
  assert(type(tbl) == "table")
  local ffi = require("ffi")
  local L = {}
  function L.serialize_value(v, indent)
    local t = type(v)
    if t == "number" or t == "boolean" then
      return tostring(v)
    elseif t == "string" then
      return string.format("%q", v)
    elseif t == "table" then
      return L.serialize_table(v, indent)
      --- Support ffi style
    elseif t == "cdata" then
      -- Check if it's a string
      if ffi.istype("const char*", v) or ffi.istype("char*", v) then
        return string.format("%q", ffi.string(v))
      elseif
          ffi.istype("int8_t", v)
          or ffi.istype("uint8_t", v)
          or ffi.istype("int16_t", v)
          or ffi.istype("uint16_t", v)
          or ffi.istype("int32_t", v)
          or ffi.istype("uint32_t", v)
          or ffi.istype("int64_t", v)
          or ffi.istype("uint64_t", v)
          or ffi.istype("float", v)
          or ffi.istype("double", v)
      then
        return tostring(tonumber(v))
      elseif ffi.istype("bool", v) then
        return tostring(v)
      else
        error("Unsupported cdata type: " .. tostring(ffi.typeof(v)))
      end
    else
      error("Unsupported type: " .. t)
    end
  end

  function L.serialize_table(t, indent)
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

  if without_func then
    return L.serialize_table(tbl)
  end
  return L.serialize_table(M.serialize_function(tbl, dumped_func_strip))
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
--- @param dumped_func_strip? boolean Whether to strip debug info when dumping functions.
--- @return string bytecode The serialized table as Lua bytecode
function M.serialize_table_as_bytecode(tbl, without_func, dumped_func_strip)
  local str = M.serialize_table(tbl, without_func, dumped_func_strip)
  local func, err = load("return " .. str)
  if not func then
    error("Failed to load table from string: " .. err)
  end
  return string.dump(func, true)
end

--- Deserialize a table from Lua bytecode.
---
--- This function reverses the serialization process performed by
--- `M.serialize_table_as_bytecode()`. It safely loads the provided
--- Lua bytecode string and reconstructs the original table structure.
---
--- If the `eager` flag is enabled, all lazily encoded (bytecode) functions
--- within the table will be immediately decoded using `M.deserialize_function()`
--- to ensure the resulting table is fully executable.
---
--- Example:
--- ```lua
--- local restored_tbl = M.deserialize_table_from_bytecode(byte_str, true)
--- print(restored_tbl.some_function())  -- now callable immediately
--- ```
---
--- @param bytecode string The Lua bytecode produced by `M.serialize_table_as_bytecode()`.
--- @param eager boolean|nil If true, eagerly decodes any encoded functions within the table.
--- @return table tbl The deserialized table with all data restored (functions decoded if `eager` is true).
--- @throws If the bytecode cannot be loaded or does not return a valid table.
function M.deserialize_table_from_bytecode(bytecode, eager)
  -- local func, err = loadstring(bytecode)
  local func, err = load(bytecode, nil, "b")
  if not func then
    error("Failed to load bytecode: " .. err)
  end
  local result = eager and M.deserialize_function(func()) or func()
  if type(result) ~= "table" then
    error("Deserialized bytecode did not return a table")
  end
  return result
end

return M
