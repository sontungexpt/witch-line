local fn, uv = vim.fn, vim.uv or vim.loop

---@class Cache
local M = {}

local sep = package.config:sub(1,1)
local CACHED_DIR = fn.stdpath("cache") .. sep ..  "witch-line"
local CACHED_FILE = CACHED_DIR .. sep ..  "cache.luac"

local loaded = false

--- Check if the cache has been read and load data to ram
--- @return boolean true if the cache has been read, false otherwise
M.loaded = function()
	return loaded
end

--- Check if the cache file exists and is readable
--- @return boolean true if the cache file is readable, false otherwise
M.cache_file_readable = function()
	return uv.fs_access(CACHED_FILE, 4) == true
end


--- @alias DataKey string|number
--- @type table<DataKey, any>
local Data = {}

local load_data = function(data)
	Data = data
	loaded = true
end

--- Encapsulate Data table access
--- This is to prevent direct access to Data table from outside
--- @class Cache.DataAccessor
--- @field get fun(key: DataKey): any Get the value associated with the key in the Data table
--- @field set fun(key: DataKey, value: any): nil Set the value associated
M.DataAccessor = {
	get = function(key)
		return Data[key]
	end,
	set = function(key, value)
		Data[key] = value
	end
}


--- Inspect the Data table
M.inspect = function()
	require("witch-line.utils.notifier").info("WitchLine Cache Data\n" .. vim.inspect(Data))
end

--- Set the checksum for the current user configs
--- @param user_configs UserConfig|nil The user configs to generate the checksum from
M.checksum = function(user_configs)
	local tbl_utils = require("witch-line.utils.tbl")
  return tbl_utils.fnv1a32_hash(user_configs)
	-- local hashs = {}
	-- for i, hash in tbl_utils.fnv1a32_hash_gradually(user_configs) do
	-- 	hashs[i] = tostring(hash)
	-- end
	-- return table.concat(hashs)
end

--- Save the Data table to cache file
--- @param checksum string The checksum to save with the cache file
M.save = function(checksum)
	local success = fn.mkdir(CACHED_DIR, "p")
	if success < 0 then
		error("Failed to create cache directory: " .. CACHED_DIR)
		return
	end

	local tbl_utils = require("witch-line.utils.tbl")
	local bytecode = tbl_utils.serialize_table_as_bytecode(Data)
	if not bytecode then
		M.clear()
		return nil, nil
	end


	local fd = assert(uv.fs_open(CACHED_FILE, "w", 438))
	assert(uv.fs_write(fd, checksum .. "\0" .. bytecode, 0))
	assert(uv.fs_close(fd))
end

--- Clear the cache file and reset the Data table
M.clear = function()
	uv.fs_unlink(CACHED_FILE, function (err)
    if err then
      require("witch-line.utils.notifier").error("Error while deleting cache file: " .. err)
    else
      Data = {}
      require("witch-line.utils.notifier").info("Cache deleted successfully. Please restart Neovim for changes to take effect.")
    end
	end)
end

--- Validate the cache file content against the user configs
--- @param checksum string The checksum to validate against
--- @param content string The content of the cache file
--- @return string|nil bytecode The bytecode part of the cache file if valid, nil otherwise
local validate_expiration = function(checksum, content)
	local len = #checksum

	if content:sub(1, len) ~= checksum then
		return nil
	elseif content:byte(len + 1) ~= 0 then
		-- the next byte must be \0
		return nil
	end
	return content:sub(len + 2)
end

--- Read the data from cache file
--- @param checksum string The checksum to validate against
--- @return Cache.DataAccessor|nil The DataAccessor if the cache file is readable and valid, nil otherwise
M.read = function(checksum)
	local fd, _, err = uv.fs_open(CACHED_FILE, "r", 438)
	if err and err == "ENOENT" then
		return nil
	end
	local stat = assert(uv.fs_fstat(fd))
	local content = assert(uv.fs_read(fd, stat.size, 0))
	assert(uv.fs_close(fd))

	local tbl_utils = require("witch-line.utils.tbl")

	local bytecode = validate_expiration(checksum, content)
	if not bytecode then
		M.clear()
		return nil
	end

	local data = tbl_utils.deserialize_table_from_bytecode(bytecode)
	if not data then
		M.clear()
		return
	end

	load_data(data)

	return M.DataAccessor
end

-- --- Read the cache file asynchronously
-- --- @param callback fun(data_accessor: table<DataAccessor,any>|nil, decoded_raw: table<StructKey,any>|nil  ) The callback to call with the decoded struct and raw data
-- M.read_async = function(callback)
-- 	uv.fs_open(CACHED_FILE, "r", 438, function(err, fd)
-- 		if err and err:find("ENOENT") then
-- 			vim.schedule(function()
-- 				callback(nil)
-- 			end)
-- 			return
-- 		end

-- 		assert(not err, err and "Failed to open cache file: " .. err)
-- 		---@diagnostic disable-next-line: redefined-local, unused-local
-- 		uv.fs_fstat(fd, function(err, stat)
-- 			assert(not err, err and "Failed to stat cache file: " .. err)
-- 			---@diagnostic disable-next-line: redefined-local, need-check-nil
-- 			uv.fs_read(fd, stat.size, 0, function(err, data)
-- 				assert(not err, err and "Failed to read cache file: " .. err)
-- 				---@diagnostic disable-next-line: redefined-local
-- 				uv.fs_close(fd, function(err)
-- 					assert(not err, err and "Failed to close cache file: " .. err)
-- 					local bytecode = validate_expiration(user_configs, content)
-- 					if not bytecode then
-- 						M.clear()
-- 						return
-- 					end
-- 					local tbl_utils = require("witch-line.utils.tbl")
-- 					local data = tbl_utils.deserialize_table_from_bytecode(bytecode)

-- 					if not data then
-- 						vim.schedule(function()
-- 							M.clear()
-- 							callback(nil)
-- 						end)
-- 						return
-- 					end
-- 					load_data(data)
-- 					vim.schedule(function()
-- 						callback(M.DataAccessor)
-- 					end)
-- 				end)
-- 			end)
-- 		end)
-- 	end)
-- end

return M
