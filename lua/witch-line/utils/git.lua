local uv = vim.uv or vim.loop

local M = {}

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

return M
