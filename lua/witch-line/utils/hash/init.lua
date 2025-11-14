local type, pairs, dump = type, pairs, string.dump
local xxh32 = require("witch-line.utils.hash.xxhash")

--- Converts a Lua value into a deterministic byte string for hashing.
---
--- Behavior:
---   - string   → returned as-is
---   - number   → converted using `tostring()`
---   - boolean  → "1" or "0"
---   - function → serialized bytecode via `dump()`
---   - other types → represented by their type name (e.g. "nil", "table")
---
--- Note:
---   Tables are NOT serialized here; they are handled recursively outside.
--- @param v any value
--- @return string serialized Serialized value as string
local function simple_serialize(v)
  local t = type(v)
  if t == "string" then
    return v
  elseif t == "number" then
    return tostring(v)
  elseif t == "boolean" then
    return v and "1" or "0"
  elseif t == "function" then
    return dump(v, true)
  end
  return t
end

--- Comparator used to deterministically sort table keys.
---
--- Ordering rules:
---   - If types match and both are numbers or strings → normal `<` comparison.
---   - If types differ → compare by type name (string order).
--- @param a any
--- @param b any
--- @return boolean
local function less(a, b)
  local ta, tb = type(a), type(b)
  return ta == tb and a < b or ta < tb
end


--- Computes a deterministic xxHash32 hash for a Lua table.
---
--- The hash is stable across runs and independent of the table's internal order.
--- Nested tables are traversed depth-first, keys are sorted deterministically,
--- and cycles are handled by a `seen` set to avoid infinite recursion.
---
--- Behavior:
---   - If `hash_key` is provided and the table contains that field,
---     only that field is hashed for this level.
---   - Otherwise:
---        - collect all keys
---        - sort them deterministically using `less()`
---        - hash key → hash value (recursively for tables)
---   - Nested tables are pushed onto a manual stack for non-recursive traversal.
---   - `simple_serialize()` is used to convert keys/values to byte sequences.
---   - Tables already seen are skipped and replaced with the literal "vtable".
---
--- @param tbl table The table to hash.
--- @param hash_key string|nil Optional field key: if provided and present in a table, only that particular field is hashed instead of the full table contents.
--- @return integer A 32-bit xxHash32 value.
local hash_tbl = function(tbl, hash_key)
  -- invalid type then return an 32 bit constant number
  if not next(tbl) then
    return 0xFFFFFFFF
  end
  local st = xxh32.xxh32_init(0)
  local xxh32_update = xxh32.xxh32_update

  local stack, stack_size = { tbl }, 1
  local seen = { [tbl] = true }
  local current, keys, keys_size = nil, {}, 0

  while stack_size > 0 do
    current = stack[stack_size]
    stack_size = stack_size - 1

    if hash_key and current[hash_key] then
      xxh32_update(st, simple_serialize(current[hash_key]))
    else
      keys_size = 0 --- reset key buffer
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

        xxh32_update(st, simple_serialize(k))

        -- Add value
        if type(v) == "table" then
          if not seen[v] then
            seen[v] = true
            stack_size = stack_size + 1
            stack[stack_size] = v
          end
          xxh32_update(st, "tbl")
        else
          xxh32_update(st, simple_serialize(v))
        end
      end
    end
  end
  return xxh32.xxh32_finalize(st)
end


return {
  hash_tbl = hash_tbl
}
