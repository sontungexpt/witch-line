local type, pairs = type, pairs
local fn, uv, mpack = vim.fn, vim.uv or vim.loop, vim.mpack
local M = {}

local CACHED_DIR = fn.stdpath("cache") .. "/witch-line"
local CACHED_FILE = CACHED_DIR .. "/cache.luac"

---- Awkful name to reduce colision with other plugins
local V_REFS = "___BYTECODE_FUNS_________@@@_"
local K_REFS = "___BYTECODE_FUNS_KEYS_____@@@"
local META_REF = "___METATABLES____________@@@__"

local had_cached = false

--- @type table<string, table|string>
local G_REFS = {}

---@alias StructKey
---| "HighlightCache"
---| "EventStore"
---| "TimerStore"
---| "DepStore"
---| "Comps"
---| "Statusline"
---| "StatuslineSize"
---| "G_REFS"
---| "Urgents"

---@type table<StructKey, any>
local Struct = {
	-- Highlight = {},
	-- EventStore = {},
	-- TimerStore = {},
	-- DepStore = {},
	-- Comps = {},
	-- Statusline = {},
	-- StatuslineSize = 0,
}

--- Check if the cache has been read
M.has_cached = function()
	return had_cached
end

--- Get the Struct table
--- @return table<StructKey, any>
M.get = function()
	return Struct
end

--- Set the Struct table from cache
--- @param struct table<StructKey, any>|nil The struct to set, if nil it will reset to an empty table
local set_struct_from_cache = function(struct)
	Struct = struct or {}
	G_REFS = Struct.G_REFS or G_REFS
	Struct.G_REFS = nil
end

--- Encode references in a table recursively
--- @param value any The value to encode
--- @param mode string The mode of encoding, can be "v" for values, "k" for keys, or "kv" for both
--- @return string|nil The encoded value or nil if the value is not encodable
local function deep_encode_refs(value, mode)
	local value_type = type(value)
	local str_hash = tostring(value)

	if value_type == "function" then
		G_REFS[str_hash] = string.dump(value, true)
		return str_hash
	elseif value_type == "string" or value_type == "number" or value_type == "boolean" then
		return value
	elseif
		value == G_REFS
		or value == Struct
		or value_type == "thread"
		or value_type == "userdata"
		or value_type == "nil"
	then
		return nil
	end

	-- table already managed
	if G_REFS[str_hash] then
		return value
	end
	G_REFS[str_hash] = value

	-- local funs = value[FUN_V_REF] or {}
	for k, v in pairs(value) do
		if mode == "v" or mode == "kv" then
			v = deep_encode_refs(v, mode)
			value[k] = v
		end

		local k_type = type(k)
		if k_type == "function" or k_type == "table" then
			local new_key = deep_encode_refs(k, mode)
			if new_key then
				value[new_key] = v
			else
				-- unsupported key type
				value[k] = nil
			end
		end
	end

	local metatable = getmetatable(value)
	if metatable then
		value[META_REF] = deep_encode_refs(metatable, mode)
	end

	return str_hash
end

--- Decode references in a table recursively
--- @param value any The value to decode
--- @param mode string The mode of decoding, can be "v" for values, "k" for keys, or "kv" for both
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return any The decoded value
local function deep_decode_refs(value, mode, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return value
	end
	seen[value] = true

	for k, v in pairs(value) do
		if type(v) == "string" then
			if mode == "v" or mode == "kv" then
				v = G_REFS[v]
				if type(v) == "table" then
					v = deep_decode_refs(v, mode, seen)
				elseif v then
					-- func
					v = loadstring(v)
				end
				value[k] = v
			end
		end
		if type(k) == "string" then
			if mode == "k" or mode == "kv" then
				local old_k = G_REFS[k]
				if type(old_k) == "table" then
					old_k = deep_decode_refs(old_k, mode, seen)
				elseif old_k then
					-- func
					---@diagnostic disable-next-line: cast-local-type
					old_k = loadstring(old_k)
				end
				if old_k then
					value[old_k] = v
					value[k] = nil
				end
			end
		end
	end

	local meta_ref = value[META_REF]
	if not meta_ref or type(meta_ref) ~= "string" then
		return value
	end
	local metatable = G_REFS[meta_ref]
	if type(metatable) == "table" then
		setmetatable(value, metatable)
		value[META_REF] = nil
	end

	return value
end

--- Loop key in table recursively and to string the key if it a reference
--- @param value any The value to encode
--- @param mode string The mode of encoding, can be "v" for values, "k" for keys, or "kv" for both
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return any The encoded value
local function encode_funcs(value, mode, seen)
	local value_type = type(value)
	if value_type == "function" then
		return string.dump(value, true)
	elseif value_type == "string" or value_type == "number" or value_type == "boolean" then
		return value
	elseif value_type == "thread" or value_type == "userdata" or value_type == "nil" then
		return nil
	end

	seen = seen or {}
	if seen[value] then
		return value
	end

	seen[value] = true
	setmetatable(value, nil) -- Remove metatable to avoid issues with encoding

	local funs = value[V_REFS] or {}
	local key_map = value[K_REFS] or {}

	for k, v in pairs(value) do
		if mode == "v" or mode == "kv" then
			if type(v) == "function" then
				funs[#funs + 1] = k
			end
			v = encode_funcs(v, mode, seen)
			value[k] = v
		end

		if mode == "k" or mode == "kv" then
			if type(k) == "function" then
				local bytecode = encode_funcs(k, mode, seen)
				if bytecode then
					key_map[bytecode] = v
				end
				value[k] = nil
			end
		end
	end

	if next(funs) then
		value[V_REFS] = funs
	end

	if next(key_map) then
		value[K_REFS] = key_map
	end

	return value
end

--- Decode functions in a table recursively
--- @param value any The value to decode
--- @param mode string The mode of decoding, can be "v" for values, "k" for keys, or "kv" for both
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return any The decoded value
local function decode_funcs(value, mode, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return value
	end

	for _, v in pairs(value) do
		decode_funcs(v, mode, seen)
	end

	if mode == "v" or mode == "kv" then
		local funs = value[V_REFS]
		if funs then
			for i = 1, #funs do
				local k = funs[i]
				local func = loadstring(value[k])
				if not func then
					error("Failed to load function from cache: " .. k)
				else
					value[k] = func
				end
			end
			value[V_REFS] = nil
		end
	end

	if mode == "k" or mode == "kv" then
		local key_map = value[K_REFS]
		if key_map then
			for k, v in pairs(key_map) do
				if type(k) == "string" then
					local func = loadstring(k)
					if not func then
						error("Failed to load function from cache: " .. k)
					else
						value[func] = v
					end
				else
					error("Invalid key type in cache: " .. type(k))
				end
			end
			value[K_REFS] = nil
		end
	end

	return value
end

---@param cache any The cache to store
---@param key StructKey The key to store the cache under
M.cache = function(cache, key)
	Struct[key] = cache
end

M.save = function(deep, mode)
	mode = mode or "v"
	local success = fn.mkdir(CACHED_DIR, "p")
	if success < 0 then
		return
	end

	local fd = assert(uv.fs_open(CACHED_FILE, "w", 438)) -- 438 is 0666 in octal
	Struct.G_REFS = G_REFS
	local encoded = deep and deep_encode_refs(Struct, mode) or encode_funcs(Struct, mode)
	local binary = mpack.encode(encoded)
	Struct.G_REFS = nil
	assert(uv.fs_write(fd, binary, 0))
	assert(uv.fs_close(fd))
end

M.clear = function()
	fn.delete(CACHED_FILE)
	Struct = {}
	G_REFS = {}
end

M.read = function(deep, mode)
	mode = mode or "v"
	local fd = assert(uv.fs_open(CACHED_FILE, "r", 438))
	local stat = assert(uv.fs_fstat(fd))
	local data = assert(uv.fs_read(fd, stat.size, 0))
	assert(uv.fs_close(fd))

	if not data or #data == 0 then
		return nil, nil
	end

	local decoded_raw = mpack.decode(data)
	local struct = decode_funcs(decoded_raw, mode)

	set_struct_from_cache(struct)
	had_cached = true

	return Struct, decoded_raw
end

M.read_async = function(callback, deep, mode)
	mode = mode or "v"
	uv.fs_open(CACHED_FILE, "r", 438, function(err, fd)
		if not fd and err and err:match("ENOENT") then
			return
		end

		assert(not err, err and "Failed to open cache file: " .. err)
		---@diagnostic disable-next-line: redefined-local, unused-local
		uv.fs_fstat(fd, function(err, stat)
			assert(not err, err and "Failed to stat cache file: " .. err)
			---@diagnostic disable-next-line: redefined-local, need-check-nil
			uv.fs_read(fd, stat.size, 0, function(err, data)
				assert(not err, err and "Failed to read cache file: " .. err)
				---@diagnostic disable-next-line: redefined-local
				uv.fs_close(fd, function(err)
					assert(not err, err and "Failed to close cache file: " .. err)
					if not data or #data == 0 then
						callback(nil, nil)
						return
					end
					local decoded_raw = mpack.decode(data)
					local struct = deep and deep_decode_refs(decoded_raw, mode) or decode_funcs(decoded_raw, mode)
					set_struct_from_cache(struct)

					had_cached = true
					callback(Struct, decoded_raw)
				end)
			end)
		end)
	end)
end

return M
