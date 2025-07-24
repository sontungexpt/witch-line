local type, pairs = type, pairs
local fn = vim.fn
local M = {}

local CACHED_DIR = fn.stdpath("cache") .. "/witch-line"
local CACHED_FILE = CACHED_DIR .. "/cache.lua"

local cached = fn.filereadable(CACHED_FILE) == 1

local Struct = {
	Highlight = {},
	EventStore = {},
	TimerStore = {},
	DepStore = {},
	Comps = {},
}

M.get = function()
	return Struct
end

--- Loop key in table recursively and to string the key if it a reference
local function normalize_cache(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end

	for k, v in pairs(tbl) do
		local type_k = type(k)
		if type(v) == "table" then
			tbl[k] = normalize_cache(v)
		elseif type_k == "function" or type_k == "thread" or type_k == "thread" or type_k == "userdata" then
			tbl[tostring(k)] = v
			tbl[k] = nil
		end
	end

	return tbl
end

---@param key "DepStore" | "EventStore" | "Highlight" | "TimerStore" | "Comps"
M.cache = function(cache, key, force)
	if cached and not force then
		return
	end
	normalize_cache(cache)
	Struct[key] = cache
end

M.save = function()
	if not cached then
		fn.mkdir(CACHED_DIR, "p")
		cached = true
	end

	local cache = normalize_cache(Struct)
	local file = io.open(CACHED_FILE, "w")
	if not file then
		return false, "Failed to open cache file for writing"
	end

	file:write("return " .. vim.inspect(cache))
	file:close()
	return true
end

M.is_cached = function()
	return cached
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
	if cached then
		local c = dofile(CACHED_FILE)
		if type(c) == "table" then
			Struct = c
		else
			error("Cache file is not a valid table: " .. CACHED_FILE)
		end
	end
end

--- Revert the cache to the original functions
--- Two table have the same structure, but the cache value is does not have valid func
--- and the real value is the original function
--- @param cache table The cache table to revert
--- @param real table The real table with original functions
--- @return table
M.revert_fun = function(cache, real)
	for k, v in pairs(real) do
		if type(v) == "table" then
			cache[k] = M.revert_fun(cache[k] or {}, v)
		elseif type(v) == "function" then
			cache[k] = v
		end
	end
	return cache
end

return M
