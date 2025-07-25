local type, pairs = type, pairs
local fn, uv, mpack = vim.fn, vim.uv or vim.loop, vim.mpack
local M = {}

local CACHED_DIR = fn.stdpath("cache") .. "/witch-line"
local CACHED_FILE = CACHED_DIR .. "/luac/cache.luac"

---- Awaful name to reduce colision with other plugins
local BYTECODE_FUNS = "___BYTECODE_FUNS___@@@@@@@"

local had_cached = false

---@class CacheStruct
---@field Highlight table
---@field EventStore table
---@field TimerStore table
---@field DepStore table
---@field Comps table
local Struct = {
	-- Highlight = {},
	-- EventStore = {},
	-- TimerStore = {},
	-- DepStore = {},
	-- Comps = {},
}

M.has_cached = function()
	return had_cached
end

M.get = function()
	return Struct
end

--- Loop key in table recursively and to string the key if it a reference
local function encode(value, seen)
	local type_tbl = type(value)
	if type_tbl == "function" then
		return string.dump(value, true)
	elseif type_tbl ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return value
	end

	for k, v in pairs(value) do
		if type(k) == "function" then
			local funs = value[BYTECODE_FUNS]
			if funs then
				funs[#funs + 1] = k
			else
				value[BYTECODE_FUNS] = { k }
			end
		end

		value[k] = encode(v, seen)
	end

	return value
end

local function decode(value)
	if type(value) ~= "table" then
		return value
	end
	for k, v in pairs(value) do
		decode(v)
	end
	local bytecode_funs = value[BYTECODE_FUNS]
	if bytecode_funs then
		for i = 1, #bytecode_funs do
			local fun = bytecode_funs[i]
			if type(fun) == "string" then
				---@diagnostic disable-next-line: deprecated
				local ok, func = pcall(loadstring, fun)
				if ok then
					value[fun] = func
				else
					vim.notify("Failed to load function from cache: " .. fun, vim.log.levels.ERROR)
				end
			else
				vim.notify("Invalid function type in cache: " .. type(fun), vim.log.levels.ERROR)
			end
		end
	end
end

decode()

---@param cache any The cache to store
---@param key "DepStore" | "EventStore" | "Highlight" | "TimerStore" | "Comps"
M.cache = function(cache, key)
	Struct[key] = cache
end

M.save = function()
	local ok, err = uv.fs_mkdir(CACHED_DIR, 493) -- 493 is 0755 in octal
	if not ok and err ~= "File exists" then
		return
	end
	local binary = mpack.encode(encode(Struct))
	local file, err = uv.fs_open(CACHED_FILE, "w", 438) -- 438 is 0666 in octal
	if not file then
		return false, "Failed to open cache file for writing: " .. err
	end

	-- local cache = encode(Struct)
	-- local file = io.open(CACHED_FILE, "w")
	-- if not file then
	-- 	return false, "Failed to open cache file for writing"
	-- end

	-- file:write("return " .. vim.inspect(cache))
	-- file:close()
	-- return true
end

M.clear = function()
	if cached then
		fn.delete(CACHED_FILE)
		cached = false
		return true
	end
	return false
end

M.read = function()
	-- local c = dofile(CACHED_FILE)
	-- if type(c) == "table" then
	-- 	Struct = c
	-- else
	-- 	error("Cache file is not a valid table: " .. CACHED_FILE)
	-- end
	local file, err = uv.fs_open(CACHED_FILE, "r", 438) -- 438 is 0666 in octal
	if not file then
		return false, "Failed to open cache file for reading: " .. err
	end

	local stat, err = uv.fs_fstat(file)
	if not stat then
		uv.fs_close(file)
		return false, "Failed to get file status: " .. err
	end

	local data, err = uv.fs_read(file, stat.size, 0)
	uv.fs_close(file)
	if not data then
		return false, "Failed to read cache file: " .. err
	end

	local ok, decoded = pcall(mpack.decode, data)
	if not ok then
		return false, "Failed to decode cache file: " .. decoded
	end

	Struct = decoded
end

return M
