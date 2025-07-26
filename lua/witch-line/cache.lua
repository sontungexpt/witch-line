local type, pairs = type, pairs
local fn, uv = vim.fn, vim.uv or vim.loop
local M = {}

local CACHED_DIR = fn.stdpath("cache") .. "/witch-line"
local CACHED_FILE = CACHED_DIR .. "/cache.luac"

---Urly name to reduce collision with table key
local V_REFS = "\0__3[[V_REF_\0 _d{E)))}"
local TBL_KEYS = "\0__TBL_KEYS\0_d{E)))}"

local has_cached = false

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
	return has_cached
end

--- Get the Struct table
--- @return table<StructKey, any>
M.get = function()
	return Struct
end

--- Set the Struct table from cache
--- @param struct table<StructKey, any>|nil The struct to set, if nil it will reset to an empty table
local set_struct = function(struct)
	Struct = struct or {}
	G_REFS = Struct.G_REFS or G_REFS
	Struct.G_REFS = nil
end

local benckmark = function(cb, name)
	local start = vim.loop.hrtime()
	cb()
	local elapsed = (vim.loop.hrtime() - start) / 1e6 -- Convert to milliseconds
	local file = io.open("/home/stilux/Data/Workspace/neovim-plugins/witch-line/lua/benckmark", "a")
	if file then
		--- get ms from elapsed
		file:write(string.format("%s took %.2f ms\n", name, elapsed))
		file:close()
	end
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

--- Encode functions in a table recursively
--- Support for table with number or string key only
--- If a key iss table or function it will skip
--- @param value any The value to encode
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return any The encoded value
local function encode_funcs(value, seen)
	local value_type = type(value)
	if value_type == "function" then
		local nups = debug.getinfo(value).nups
		if nups > 0 then
			error("Function with upvalues cannot be cached: " .. debug.getinfo(value).source)
		end
		return string.dump(value)
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

	local funs = value[V_REFS] or {}
	local tbl_keys = value[TBL_KEYS] or {}

	for k, v in pairs(value) do
		local k_type = type(k)
		if k_type == "table" or k_type == "function" or k_type == "thread" or k_type == "userdata" then
			value[k] = nil
		elseif type(v) == "function" then
			funs[#funs + 1] = k
			value[k] = encode_funcs(v, seen)
		elseif type(v) == "table" then
			v = encode_funcs(v, seen)
			if v[V_REFS] or v[TBL_KEYS] then
				tbl_keys[#tbl_keys + 1] = k
			end
			value[k] = v
		end
	end

	if next(funs) then
		value[V_REFS] = funs
	end

	if next(tbl_keys) then
		value[TBL_KEYS] = tbl_keys
	end

	return value
end

--- Decode functions in a table recursively
--- @param value any The value to decode
--- @param is_func boolean|nil Whether the value is a function or not
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return any The decoded value
local function decode_funcs(value, is_func, seen)
	local value_type = type(value)
	if is_func and value_type == "string" then
		return loadstring(value)
	elseif value_type ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return value
	end

	local tbl_keys = value[TBL_KEYS]
	if tbl_keys then
		for i = 1, #tbl_keys do
			local key = tbl_keys[i]
			local tbl = value[key]
			value[key] = decode_funcs(tbl, false, seen)
		end
	end

	local funs = value[V_REFS]
	-- error("decode_funcs: " .. vim.inspect(funs) .. "tbl" .. vim.inspect(value))
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
	value[TBL_KEYS] = nil
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

	local fd, err_msg, err = uv.fs_open(CACHED_FILE, "w", 438)
	if err == "ENOENT" then
		--- No cached file found
		return nil, nil
	end

	assert(not err, err_msg and "Failed to open cache file: " .. err_msg .. ". Error name " .. err)

	Struct.G_REFS = G_REFS

	local ok, encoded = pcall(function()
		if deep then
			return deep_encode_refs(Struct, mode)
		end

		--- Can be cached if no upvalues
		return encode_funcs(Struct)
	end)

	if not ok then
		require("witch-line.utils.log").warn("Failed to encode cache: " .. encoded)

		M.clear()
		assert(uv.fs_close(fd))
		return nil, nil
	end

	-- local saved_str = mpack.encode(encoded)

	-- local saved_str = "return " .. vim.inspect(encoded)

	local dumped = loadstring("return " .. vim.inspect(encoded))
	if not dumped then
		M.clear()
		assert(uv.fs_close(fd))
		return nil, nil
	end

	local bytecode = string.dump(dumped, true)

	Struct.G_REFS = nil
	-- assert(uv.fs_write(fd, binary, 0))
	assert(uv.fs_write(fd, bytecode, 0))
	assert(uv.fs_close(fd))
end

M.clear = function()
	uv.fs_unlink(CACHED_FILE)
	Struct = {}
	G_REFS = {}
end

M.read = function(deep, mode)
	mode = mode or "v"

	local fd, _, err = uv.fs_open(CACHED_FILE, "r", 438)
	if err and err == "ENOENT" then
		return
	end
	local stat = assert(uv.fs_fstat(fd))
	local data = assert(uv.fs_read(fd, stat.size, 0))
	assert(uv.fs_close(fd))

	if not data or #data == 0 then
		return nil, nil
	end

	-- local decoded_raw = dofile(CACHED_FILE)

	-- local decoded_raw = mpack.decode(data)

	--- NOTE: Fastest way
	local func = loadstring(data)
	if not func then
		return nil, nil
	end
	local decoded_raw = func()
	-- local decoded_raw = mpack.decode(data)
	--

	local struct = deep and deep_decode_refs(decoded_raw, mode) or decode_funcs(decoded_raw)

	set_struct(struct)
	has_cached = true
	-- end, "loadstring")
	return Struct, nil

	-- return Struct, decoded_raw or nil
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
					local func = loadstring(data)
					if not func then
						callback(nil, nil)
						return
					end

					-- local decoded_raw = mpack.decode(data)
					-- local struct = deep and deep_decode_refs(decoded_raw, mode) or decode_funcs(decoded_raw)

					local decoded_raw = func()
					local struct = deep and deep_decode_refs(decoded_raw, mode) or decode_funcs(decoded_raw)
					set_struct(struct)

					has_cached = true
					callback(Struct, decoded_raw)
				end)
			end)
		end)
	end)
end

return M
