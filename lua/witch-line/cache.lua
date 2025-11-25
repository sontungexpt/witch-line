local vim, assert, substring = vim, assert, string.sub
local uv = vim.uv or vim.loop

---@class Cache
local M = {}
local sep = substring(package.config, 1, 1)
local CACHED_DIR = vim.fn.stdpath("cache") .. sep .. "witch-line"
local CACHED_FILE = CACHED_DIR .. sep .. "cache.luac"

local loaded = false

--- Create a combined checksum string based on the config checksum
--- and several runtime parameters (msec, mnsec, size).
--- This checksum is used to validate cache files and detect changes
--- in either the user configuration or environment state.
---
--- @param config_checksum any The checksum derived from the user config.
--- @param commit_hash string The git commit hash.
--- @return string checksum The concatenated checksum string.
local create_checksum = function(config_checksum, commit_hash)
	-- return tostring(config_checksum) .. commit_hash .. "\0"
	return tostring(config_checksum) .. commit_hash
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

--- Get the current git commit hash
--- @return string commit_hash The git commit hash
local get_current_commit = function()
	local repo = vim.api.nvim_get_option_value("runtimepath", {}):match("[^,]*/witch%-line")
	local head_fd = assert(uv.fs_open(repo .. "/.git/HEAD", "r", 438))
	local head_content = assert(uv.fs_read(head_fd, 40, 0))
	if substring(head_content, 1, 4) ~= "ref:" then
		assert(uv.fs_close(head_fd))
		return head_content
	end

	-- HEAD is a reference
	local ref_path = repo .. "/.git/" .. substring(head_content, 6):gsub("%s*$", "")
	local ref_fd, _, err = uv.fs_open(ref_path, "r", 438)
	if err == "ENOENT" then -- 40 byte is not enough for a branch name (rarely)
		local head_stat = assert(uv.fs_fstat(head_fd))
		head_content = assert(uv.fs_read(head_fd, head_stat.size, 0))
		assert(uv.fs_close(head_fd))
		ref_path = repo .. "/.git/" .. substring(head_content, 6):gsub("%s*$", "")
		ref_fd = assert(uv.fs_open(ref_path, "r", 438))
	end
	local hash = assert(uv.fs_read(ref_fd, 40, 0))
	assert(uv.fs_close(ref_fd))
	return hash
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
	local success = vim.fn.mkdir(CACHED_DIR, "p")
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
	assert(uv.fs_write(fd, create_checksum(config_checksum, get_current_commit()) .. bytecode, 0))
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
		inherit = 2,
		timing = 3,
		lazy = 4,
		flexible = 5,
		events = 6,
		min_screen_width = 7,
		ref = 8,
		left_style = 10,
		left = 11,
		right_style = 12,
		right = 13,
		padding = 14,
		init = 15,
		style = 16,
		temp = 17,
		static = 18,
		context = 19,
		pre_update = 20,
		update = 21,
		post_update = 22,
		hidden = 23,
		on_click = 24,
		win_individual = 25,

		--- For UserConfig field
		cache = 26,
		enabled = 27,
		notification = 28,
		func_strip = 29,

		disabled = 30,
		filetypes = 31,
		buftypes = 32,

		abstracts = 33,
		statusline = 34,
		global = 35,
		win = 36,
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
	local checksum = create_checksum(config_checksum, get_current_commit())
	local checksum_end = #checksum

	if substring(content, 1, checksum_end) ~= checksum then
		M.clear(notification)
		return nil
	end

	local bytecode = substring(content, checksum_end + 1)

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
