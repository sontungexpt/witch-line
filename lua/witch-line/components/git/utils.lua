local uv = vim.uv or vim.loop

local M = {}

--- Get the git root directory path
--- @param dir_path? string The directory path to start from.
--- @return string|nil path The git root directory path, or nil if not found
M.get_root_by_git = function(dir_path)
	local prev = ""
	local dir = dir_path or uv.cwd()
	while dir ~= prev do
		local git_path = dir .. "/.git"
		local stat = uv.fs_stat(git_path)
		if stat then
			if stat.type == "directory" then
				return dir
			elseif stat.type == "file" then
				local fd = io.open(git_path, "r")
				if fd then
					local line = fd:read("*l")
					fd:close()
					local gitdir = line:match("^gitdir:%s*(.-)%s*$")
					if gitdir then
						-- Handle relative gitdir path
						if not gitdir:match("^/") and not gitdir:match("^%a:[/\\]") then
							gitdir = dir .. "/" .. gitdir
						end
						-- Normalize and verify
						return uv.fs_realpath(gitdir)
					end
				end
			end
		end

		prev = dir
		dir = dir:match("^(.*)[/\\][^/\\]+$") or dir -- fallback to prevent infinite loop when reaching root
	end
	return nil
end

--- @alias DiffResult { added: uinteger, modified: uinteger, removed: uinteger }
--- Process diff output return from vim.system
--- Adapted from https://github.com/wbthomason/nvim-vcs
--- @param stdout string The output of vim.system
--- @return DiffResult diff_result The number of added, modified and removed lines
M.process_diff = function(stdout)
	local added, removed, modified = 0, 0, 0
	local tonumber = tonumber
	for old_start, old_count, new_start, new_count in
		string.gmatch(stdout, "@@%s*%-(%d+),?(%d*)%s*%+(%d+),?(%d*)%s*@@")
	do
		old_count = (old_count == nil and 0) or (old_count == "" and 1) or tonumber(old_count) or 0
		new_count = (new_count == nil and 0) or (new_count == "" and 1) or tonumber(new_count) or 0

		if old_count == 0 and new_count > 0 then
			added = added + new_count
		elseif old_count > 0 and new_count == 0 then
			removed = removed + old_count
		else
			local minv = old_count < new_count and old_count or new_count
			modified = modified + minv
			added = added + (new_count - minv)
			removed = removed + (old_count - minv)
		end
	end
	return { added = added, modified = modified, removed = removed }
end

return M
