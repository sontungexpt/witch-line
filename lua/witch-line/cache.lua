local type, pairs, loadstring, mpack, json = type, pairs, loadstring, vim.mpack, vim.json
local fn, uv = vim.fn, vim.uv or vim.loop
local M = {}

local CACHED_DIR = fn.stdpath("cache") .. "/witch-line"
local CACHED_FILE = CACHED_DIR .. "/cache.luac"

---Urly name to reduce collision with t==able key
local ENCODED_FUNC_KEYS = "V_REF@@__q@@$$whaw2EWdjDSldkvj23@@19"
local ENCODED_TBL_KEYS = "TBL_KEYS__dcjvlwkiwEEW3df2df ##S"
local ENCODED_META_KEY = "META_REF__df dfdjlDDW@@$__dfjowdfdadj2940"

local loaded = false

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
---| "UserConfigHashs"
---| "Disabled"

---@type table<StructKey, any>
local Struct = {
	-- HighlightCache = nil,
	-- EventStore = nil,
	-- TimerStore = nil,
	-- DepStore = nil,
	-- Comps = nil,
	-- Statusline = nil,
	-- StatuslineSize = nil,
	-- G_REFS = nil,
	-- Urgents = nil,
	-- Disabled = nil
}

--- Check if the cache has been read
M.loaded = function()
	return loaded
end

--- Check if the cache file exists and is readable
--- @return boolean|nil true if the cache file is readable, false otherwise
M.cache_readable = function()
	return uv.fs_access(CACHED_FILE, 4)
end

--- Get the Struct table
--- @param key StructKey The key to get from the Struct table
--- @return any The value associated with the key in the Struct table
M.get = function(key)
	return Struct[key]
end

M.inspect = function()
	vim.notify(vim.inspect(Struct), vim.log.levels.INFO, { title = "Witch Line Struct" })
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
--- @return string|nil The encoded value or nil if the value is not encodable
local function deep_encode_refs(value)
	local encoded_api_key = ("\0\f\t" .. math.random() .. uv.hrtime())

	local function handle()
		local value_type = type(value)
		local str_hash = encoded_api_key .. tostring(value)

		if value_type == "function" then
			G_REFS[str_hash] = string.dump(value)
			return str_hash
		elseif value_type == "string" or value_type == "number" or value_type == "boolean" then
			return value
		elseif
			value_type == "thread"
			or value_type == "userdata"
			or value_type == "nil"
			or value == G_REFS
			or value == Struct
		then
			return nil
		end

		-- table already managed
		if G_REFS[str_hash] then
			return value
		end
		G_REFS[str_hash] = value

		for k, v in pairs(value) do
			v = deep_encode_refs(v)
			value[k] = v

			local nk = deep_encode_refs(k)
			value[k] = nil
			if nk then
				value[nk] = v
			end
		end

		local metatable = getmetatable(value)
		if metatable then
			value[ENCODED_META_KEY] = deep_encode_refs(metatable)
		end

		return str_hash
	end
	handle()
end

--- Decode references in a table recursively
--- @param value any The value to decode
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return any The decoded value
local function deep_decode_refs(value, seen)
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
			v = G_REFS[v]
			if type(v) == "table" then
				v = deep_decode_refs(v, seen)
			elseif v then
				-- func
				v = loadstring(v)
			end
			value[k] = v
		end
		if type(k) == "string" then
			local old_k = G_REFS[k]
			if type(old_k) == "table" then
				old_k = deep_decode_refs(old_k, seen)
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

	local meta_ref = value[ENCODED_META_KEY]
	if not meta_ref or type(meta_ref) ~= "string" then
		return value
	end

	local metatable = G_REFS[meta_ref]
	if type(metatable) == "table" then
		setmetatable(value, metatable)
	end
	value[ENCODED_META_KEY] = nil

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
	setmetatable(value, nil)

	local funs = value[ENCODED_FUNC_KEYS] or {}
	local tbl_keys = value[ENCODED_TBL_KEYS] or {}

	for k, v in pairs(value) do
		local k_type = type(k)
		if k_type == "table" or k_type == "function" or k_type == "thread" or k_type == "userdata" then
			error("Unsupported key type: " .. k_type .. " for key: " .. vim.inspect(k))
		elseif type(v) == "function" then
			funs[#funs + 1] = k
			value[k] = encode_funcs(v, seen)
		elseif type(v) == "table" then
			v = encode_funcs(v, seen)
			if v[ENCODED_FUNC_KEYS] or v[ENCODED_TBL_KEYS] then
				tbl_keys[#tbl_keys + 1] = k
			end
			value[k] = v
		end
	end

	if next(funs) then
		value[ENCODED_FUNC_KEYS] = funs
	end

	if next(tbl_keys) then
		value[ENCODED_TBL_KEYS] = tbl_keys
	end

	return value
end

--- Decode functions in a table recursively
--- @param value any The value to decode
--- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
--- @return any The decoded value
local function decode_funcs(value, seen)
	local value_type = type(value)
	if value_type == "string" then
		local func = loadstring(value)
		return func or value
	elseif value_type ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return value
	end

	local tbl_keys = value[ENCODED_TBL_KEYS]
	if tbl_keys then
		for i = 1, #tbl_keys do
			local key = tbl_keys[i]
			local tbl = value[key]
			value[key] = decode_funcs(tbl, seen)
		end
	end

	local funs = value[ENCODED_FUNC_KEYS]
	if funs then
		for i = 1, #funs do
			local k = funs[i]
			local func, err = loadstring(value[k])
			if not func then
				error("Failed to load function from string: " .. err)
			end
			value[k] = func
		end

		--- Remove encoded function keys from the value as they are no longer needed
		value[ENCODED_FUNC_KEYS] = nil
	end
	--- Remove encoded table keys from the value as they are no longer needed
	value[ENCODED_TBL_KEYS] = nil
	return value
end

---@param cache any The cache to store
---@param key StructKey The key to store the cache under
M.cache = function(cache, key)
	Struct[key] = cache
end

--- Encode the cache to a string
--- @param deep boolean Whether to encode references deeply or not
--- @return string|nil bytecode The encoded cache as a bytecode string, or nil if encoding failed
local encode_cache = function(deep)
	local ok, encoded = pcall(function()
		if deep then
			return deep_encode_refs(Struct)
		end
		--- Can be cached if no upvalues
		return encode_funcs(Struct)
	end)

	if not ok then
		require("witch-line.utils.notifier").error("Failed to encode cache: " .. encoded)
		return nil
	end
	local binary = mpack.encode(encoded)
	-- local binary = mpack.encode(encoded)
	return binary ~= "" and binary or nil
end

--- Decode the cache from a string
--- @param data string The data to decode
--- @param deep boolean|nil Whether to decode references deeply or not
--- @return table<StructKey,any>|nil The decoded struct or nil if decoding failed
--- @return table<StructKey,any>|nil The raw decoded data, if available
local decode_cache = function(data, deep)
	if not data or #data == 0 then
		return nil, nil
	end

	local struct, decoded_raw
	benckmark(function()
		decoded_raw = mpack.decode(data)

		-- local decoded_raw = mpack.decode(data)
		struct = deep and deep_decode_refs(decoded_raw) or decode_funcs(decoded_raw)
		set_struct(struct)
	end)

	return struct, decoded_raw
end

---@diagnostic disable-next-line: unused-local
M.save = function(deep)
	local success = fn.mkdir(CACHED_DIR, "p")
	if success < 0 then
		error("Failed to create cache directory: " .. CACHED_DIR)
		return
	end

	local fd = assert(uv.fs_open(CACHED_FILE, "w", 438))
	Struct.G_REFS = G_REFS

	local bytecode = encode_cache(deep)

	if not bytecode then
		M.clear()
		assert(uv.fs_close(fd))
		return nil, nil
	end

	Struct.G_REFS = nil
	-- assert(uv.fs_write(fd, binary, 0))
	assert(uv.fs_write(fd, bytecode, 0))
	assert(uv.fs_close(fd))
end

M.clear = function()
	uv.fs_unlink(CACHED_FILE)
	Struct, G_REFS = {}, {}
end

M.read = function(deep)
	local fd, _, err = uv.fs_open(CACHED_FILE, "r", 438)
	if err and err == "ENOENT" then
		return
	end
	local stat = assert(uv.fs_fstat(fd))
	local data = assert(uv.fs_read(fd, stat.size, 0))
	assert(uv.fs_close(fd))
	loaded = true

	local struct, decoded_raw = decode_cache(data, deep)

	return struct, decoded_raw
end

--- Read the cache file asynchronously
--- @param callback fun(struct: table<StructKey,any>|nil, decoded_raw: table<StructKey,any>|nil  ) The callback to call with the decoded struct and raw data
--- @param deep boolean|nil Whether to decode references deeply or not
M.read_async = function(callback, deep)
	uv.fs_open(CACHED_FILE, "r", 438, function(err, fd)
		if err and err:find("ENOENT") then
			vim.schedule(function()
				callback(nil, nil)
			end)
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
					local struct, decoded_raw = decode_cache(data, deep)
					loaded = true
					vim.schedule(function()
						callback(struct, decoded_raw)
					end)
				end)
			end)
		end)
	end)
end

return M
