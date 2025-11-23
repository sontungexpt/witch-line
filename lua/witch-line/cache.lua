local vim, tostring, assert = vim, tostring, assert
local fn, uv = vim.fn, vim.uv or vim.loop

---@class Cache
local M = {}

local sep = package.config:sub(1, 1)
local CACHED_DIR = fn.stdpath("cache") .. sep .. "witch-line"
local CACHED_FILE = CACHED_DIR .. sep .. "cache.luac"

local loaded = false

--- Create a combined checksum string based on the config checksum
--- and several runtime parameters (msec, mnsec, size).
--- This checksum is used to validate cache files and detect changes
--- in either the user configuration or environment state.
---
--- @param config_checksum any The checksum derived from the user config.
--- @return string checksum The concatenated checksum string.
local create_checksum = function(config_checksum, msec, mnsec, size)
	return table.concat {
		tostring(config_checksum),
		tostring(msec),
		tostring(mnsec),
		tostring(size),
		"\0",
	}
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
--- @class Cache.DataAccessor
--- @field [DataKey] any The Data table

--- @type Cache.DataAccessor
local DataAccessor = {}
M.DataAccessor = DataAccessor

--- Inspect the Data table
M.inspect = function()
	require("witch-line.utils.notifier").info("WitchLine Cache Data\n" .. vim.inspect(DataAccessor))
end

--- Read modification info of the `witch-line` plugin directory.
--- Used to detect if the plugin was updated (mtime/size changed).
local read_plugin_stat = function()
	local root = vim.api.nvim_get_option_value("runtimepath", {}):match("[^,]*/witch%-line")
	local stat = uv.fs_stat(root)
	if not stat then
		return 0, 0, 0
	end

	local mtime = stat.mtime
	if mtime then
		return stat.size or 0, mtime.sec, mtime.nsec
	end
	return stat.size or 0, 0, 0
end

--- Save the current Data table to a cache file.
--- This writes the serialized bytecode (with optional function-stripping)
--- together with a checksum header, so the cache can later be validated
--- against changes in configuration or environment.
---
--- @param config_checksum integer The checksum representing the current user config state.
--- @param debug_strip? boolean Whether to strip debug info when dumping functions.
--- @param pre_work? fun(CacheDataAccessor: Cache.DataAccessor) A function to run before saving the cache.
M.save = function(config_checksum, debug_strip, pre_work)
	local success = fn.mkdir(CACHED_DIR, "p")
	if success < 0 then
		error("Failed to create cache directory: " .. CACHED_DIR)
		return
	end

	if pre_work then
		pre_work(DataAccessor)
	end

	local bytecode =
		require("witch-line.utils.persist").serialize_table_as_bytecode(DataAccessor, true, debug_strip)
	if not bytecode then
		M.clear()
		return
	end

	local fd = assert(uv.fs_open(CACHED_FILE, "w", 438))
	local msec, mnsec, size = read_plugin_stat()
	assert(uv.fs_write(fd, create_checksum(config_checksum, msec, mnsec, size) .. bytecode, 0))
	assert(uv.fs_close(fd))
end

--- Clear the cache file and reset the Data table.
--- @param notification? boolean Whether to show a user notification after clearing the cache.
M.clear = function(notification)
	uv.fs_unlink(CACHED_FILE, function(err)
		if err then
			require("witch-line.utils.notifier").error("Error while deleting cache file: " .. err)
		else
			DataAccessor = {}
			if notification ~= false then
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
		win_individual = 26,

		--- For UserConfig field
		cache = 27,
		full_scan = 28,
		notification = 29,
		func_strip = 30,

		disabled = 31,
		filetypes = 32,
		buftypes = 33,

		abstracts = 34,
		statusline = 35,
		global = 36,
		win = 37,
	})
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
--- @param notification boolean|nil Whether to show a notification when cache is invalid or refreshed.
--- @return Cache.DataAccessor|nil DataAccessor The DataAccessor if the cache is valid, or nil otherwise.
M.read = function(config_checksum, notification)
	local fd, _, err = uv.fs_open(CACHED_FILE, "r", 438)
	if err and err == "ENOENT" then
		return nil
	end
	local stat = assert(uv.fs_fstat(fd))
	local content = assert(uv.fs_read(fd, stat.size, 0))
	assert(uv.fs_close(fd))

	--- Validate the cache file content against the user configs
	local msec, mnsec, size = read_plugin_stat()
	local checksum = create_checksum(config_checksum, msec, mnsec, size)
	local checksum_end = #checksum
	if content:sub(1, checksum_end) ~= checksum then
		return nil
	end

	local bytecode = content:sub(checksum_end + 1)

	local data = require("witch-line.utils.persist").deserialize_table_from_bytecode(bytecode)
	if not data then
		M.clear(notification)
		return nil
	end

	DataAccessor = data
	loaded = true

	return DataAccessor
end

return M
