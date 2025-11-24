local type, pairs, tostring, uv, getinfo = type, pairs, tostring, vim.uv or vim.loop, debug.getinfo

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
	end
	return t
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
--- @param tbl? table The table to hash.
--- @param hash_key? string Optional field key: if provided and present in a table, only that particular field is hashed instead of the full table contents.
--- @param key_priority_map? table<string, integer> Optional ranking table used for deterministic key ordering.
--- If provided:
---    - Keys with lower rank values are ordered first.
---    - Keys without rank fall back to type/value comparison.
--- If nil:
---    - All keys fall back entirely to type/value comparison.
--- @return integer A 32-bit xxHash32 value.
local hash_tbl = function(tbl, hash_key, key_priority_map)
	-- invalid type then return an 32 bit constant number
	if type(tbl) ~= "table" or not next(tbl) then
		return 0xFFFFFFFF
	end

	local st = xxh32.xxh32_init(0)
	local xxh32_update = xxh32.xxh32_update

	local stack, stack_size = { tbl }, 1
	local seen = { [tbl] = true }
	local current, keys, keys_size = nil, {}, 0
	local mtime_cache = {}
	key_priority_map = key_priority_map or {}

	while stack_size > 0 do
		current = stack[stack_size]
		stack_size = stack_size - 1

		if hash_key and current[hash_key] then
			xxh32_update(st, simple_serialize(current[hash_key]))
		else
			keys_size = 0 --- reset key buffer
			for k in pairs(current) do
				--- If is function, then check the modified time instead
				--- It is not very accurate but this is the only way to check the function modification.

				keys_size = keys_size + 1
				local i, rk = keys_size, key_priority_map[k]
				-- custom compare using pre-cached rank
				while i > 1 do
					local prev = keys[i - 1]
					local rprev = key_priority_map[prev]

					if rk then
						-- current key has rank
						-- CASE 1: Both keys have a rank → compare by rank (fastest path)
						if rprev then
							-- both ranked → compare by rank
							if rk >= rprev then
								break
							end
							-- else CASE 2: Current key has rank, previous does not → current < previous → continue shifting
						end

					-- CASE 3: Previous key has rank, current does not → current > previous → stop shifting
					elseif rprev then
						-- prev has rank, k does not -> k is bigger
						break

					-- CASE 4: Neither key has a rank → fallback to type-based + value-based comparison
					else
						-- fallback: type/value compare
						local ta, tb = type(k), type(prev)
						if not (ta == tb and k < prev or ta < tb) then
							break
						end
					end

					-- Shift the previous key forward to make room for `k`
					keys[i] = prev
					i = i - 1
				end

				keys[i] = k
			end

			for i = 1, keys_size do
				local k = keys[i]
				local v = current[k]
				xxh32_update(st, simple_serialize(k))
				-- Add value
				local v_type = type(v)
				if v_type == "table" then
					if not seen[v] then
						seen[v] = true
						stack_size = stack_size + 1
						stack[stack_size] = v
					end
					xxh32_update(st, "tbl")
				elseif v_type == "function" then
					local source = getinfo(v, "S").source
					local mtime_str = mtime_cache[source]
					if not mtime_str then
						local mtime = uv.fs_stat(source:sub(2)).mtime
						mtime_str = tostring(mtime.sec) .. tostring(mtime.nsec)
						mtime_cache[source] = mtime_str
					end
					xxh32_update(st, mtime_str)
				else
					xxh32_update(st, simple_serialize(v))
				end
			end
		end
	end
	return xxh32.xxh32_finalize(st)
end

return {
	hash_tbl = hash_tbl,
}
