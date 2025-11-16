local vim, concat, tostring, assert = vim, table.concat, tostring, assert
local fn, uv, nvim_get_runtime_file = vim.fn, vim.uv or vim.loop, vim.api.nvim_get_runtime_file

---@class Cache
local M = {}

local sep = package.config:sub(1, 1)
local CACHED_DIR = fn.stdpath("cache") .. sep .. "witch-line"
local CACHED_FILE = CACHED_DIR .. sep .. "cache.luac"

--- The witch-line plugin dir stat to check if should expire cacche when update plug
local msec, mnsec, size = 0, 0, 0

local loaded = false

--- Create a combined checksum string based on the config checksum
--- and several runtime parameters (msec, mnsec, size).
--- This checksum is used to validate cache files and detect changes
--- in either the user configuration or environment state.
---
--- @param config_checksum any The checksum derived from the user config.
--- @return string checksum The concatenated checksum string.
local create_checksum = function(config_checksum)
	return concat({
		tostring(config_checksum),
		tostring(msec),
		tostring(mnsec),
		tostring(size),
	})
end

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
	end,
}

--- Inspect the Data table
M.inspect = function()
	require("witch-line.utils.notifier").info("WitchLine Cache Data\n" .. vim.inspect(Data))
end

--- Read modification info of the `witch-line` plugin directory.
--- Used to detect if the plugin was updated (mtime/size changed).
--- @param deep boolean|nil If true, also scans all subfiles recursively
local function read_plugin_stat(deep)
	local root_dir = nvim_get_runtime_file("**/witch-line", false)[1]
	local stat = uv.fs_stat(root_dir)
	if stat then
		size = size + stat.size
		local mtime = stat.mtime
		if mtime then
			msec, mnsec = mtime.sec, mtime.nsec
		end
	end
	if deep then
		local paths = nvim_get_runtime_file("**/witch-line/**", true)
		for i = 1, #paths do
			local p = paths[i]
			stat = uv.fs_stat(p)
			if stat then
				size = size + stat.size
				local mtime = stat.mtime
				if mtime then
					local sec, nsec = mtime.sec, mtime.nsec
					if sec > msec or nsec > mnsec then
						msec, mnsec = sec, nsec
					end
				end
			end
		end
	end
end

--- Save the current Data table to a cache file.
--- This writes the serialized bytecode (with optional function-stripping)
--- together with a checksum header, so the cache can later be validated
--- against changes in configuration or environment.
---
--- @param config_checksum integer The checksum representing the current user config state.
--- @param dumped_func_strip? boolean Whether to strip debug info when dumping functions.
M.save = function(config_checksum, dumped_func_strip)
	local success = fn.mkdir(CACHED_DIR, "p")
	if success < 0 then
		error("Failed to create cache directory: " .. CACHED_DIR)
		return
	end

	local Persist = require("witch-line.utils.persist")
	local bytecode = Persist.serialize_table_as_bytecode(Data, true, dumped_func_strip)
	if not bytecode then
		M.clear()
		return
	end

	local fd = assert(uv.fs_open(CACHED_FILE, "w", 438))
	assert(uv.fs_write(fd, concat({ create_checksum(config_checksum), "\0", bytecode }), 0))
	assert(uv.fs_close(fd))
end

--- Clear the cache file and reset the Data table.
--- @param notification boolean|nil Whether to show a user notification after clearing the cache.
M.clear = function(notification)
	uv.fs_unlink(CACHED_FILE, function(err)
		if err then
			require("witch-line.utils.notifier").error("Error while deleting cache file: " .. err)
		else
			Data = {}
			if notification then
				require("witch-line.utils.notifier").info(
					"Cache deleted successfully. Please restart Neovim for changes to take effect."
				)
			end
		end
	end)
end

--- Compute a stable checksum for the given user configurations.
--- This uses `hash_tbl()` to generate a deterministic hash string,
--- ensuring that cache invalidation happens whenever the user configs change.
---
--- @param user_configs UserConfig|nil The user configuration table to hash.
--- @return integer checksum A stable checksum representing the configuration state.
M.config_checksum = function(user_configs)
	return require("witch-line.utils.hash").hash_tbl(user_configs, "version", {
		-- For Component field
		id = 1,
		version = 2,
		inherit = 3,
		timing = 4,
		lazy = 5,
		flexible = 6,
		events = 7,
		min_screen_width = 8,
		ref = 9,
		left_style = 11,
		left = 12,
		right_style = 13,
		right = 14,
		padding = 15,
		init = 16,
		style = 17,
		temp = 18,
		static = 19,
		context = 20,
		pre_update = 21,
		update = 22,
		post_update = 23,
		hidden = 24,
		on_click = 25,

		--- For UserConfig field
		cache = 26,
		full_scan = 27,
		notification = 28,
		func_strip = 29,

		disabled = 30,
		filetypes = 31,
		buftypes = 32,

		abstracts = 33,
		components = 34,
	})
end

--- Validate the cache file content against the user configs
--- @param content string The content of the cache file
--- @return string|nil bytecode The bytecode part of the cache file if valid, nil otherwise
local validate_expiration = function(config_checksum, content)
	local checksum = create_checksum(config_checksum)
	local len = #checksum
	if content:sub(1, len) ~= checksum then
		return nil
	elseif content:byte(len + 1) ~= 0 then
		-- the next byte must be \0
		return nil
	end
	return content:sub(len + 2)
end

--- Read and validate data from the cache file.
--- This function loads the cache content, verifies the checksum header
--- against the current configuration state, and optionally performs
--- a full scan if required. If the cache is valid, a DataAccessor object
--- is returned; otherwise, the function returns nil.
--- Optionally, a notification can be shown when the cache is invalid
--- or needs to be regenerated.
---
--- @param config_checksum integer The checksum representing the current user configuration.
--- @param full_scan boolean Whether to scan all plugin stat.
--- @param notification boolean|nil Whether to show a notification when cache is invalid or refreshed.
--- @return Cache.DataAccessor|nil DataAccessor The DataAccessor if the cache is valid, or nil otherwise.
M.read = function(config_checksum, full_scan, notification)
	local fd, _, err = uv.fs_open(CACHED_FILE, "r", 438)
	if err and err == "ENOENT" then
		return nil
	end

	---@diagnostic disable: param-type-mismatch
	local stat = assert(uv.fs_fstat(fd))
	local content = assert(uv.fs_read(fd, stat.size, 0))
	assert(uv.fs_close(fd))
	---@diagnostic enable: param-type-mismatch

	read_plugin_stat(full_scan)
	local bytecode = validate_expiration(config_checksum, content)
	if not bytecode then
		M.clear(notification or true)
		return nil
	end

	local Persist = require("witch-line.utils.persist")
	local data = Persist.deserialize_table_from_bytecode(bytecode)
	if not data then
		M.clear(notification or true)
		return nil
	end

	load_data(data)

	return M.DataAccessor
end

return M
