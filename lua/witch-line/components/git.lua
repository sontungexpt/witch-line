local Id = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")

---@type DefaultComponent
local Branch = {
	id = Id["git.branch"],
	_plug_provided = true,
	static = {
		icon = "",
		disabled = {
			filetypes = {
				"NvimTree",
				"neo-tree",
				"alpha",
				"dashboard",
				"TelescopePrompt",
			},
		},
	},
	context = {
		root_dir = nil, -- the root directory of the current git repository

		-- The slower but simpler version
		-- get_head_file_path = function()
		--   local fn = vim.fn
		--   local git_dir = fn.finddir(".git", ".;")
		--   if git_dir ~= "" then
		--     return fn.fnamemodify(git_dir, ":p") .. "HEAD"
		--   end
		--   return nil
		-- end,
	},
	init = function(self, session_id)
		local uv, api = vim.uv or vim.loop, vim.api
		local static = self.static
		--- @cast static { disabled: { filetypes: string[] }, icon: string }
		local ctx = self.context
		--- @cast ctx {root_dir: string|nil }

		local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph

		local get_root_by_git = function(dir_path)
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

		local file_changed, sec_arg = nil, nil
		if uv.os_uname().sysname == "Windows_NT" then
			file_changed = uv.new_fs_poll()
			sec_arg = 1000
		else
			file_changed = uv.new_fs_event()
			sec_arg = {}
		end

		-- local last_head_file_path = nil
		local last_root_dir = nil

		-- helper: restart watcher + trigger event
		local function update_repo(new_dir_path)
			if not file_changed then
				return
			end
			file_changed:stop()

			if new_dir_path then
				file_changed:start(
					new_dir_path,
					sec_arg,
					vim.schedule_wrap(function()
						refresh_component_graph(self)
					end)
				)
			end

			-- Update state
			-- last_head_file_path = new_dir_path
			last_root_dir = new_dir_path
			ctx.root_dir = new_dir_path
			-- Trigger immediately so the branch text updates
			refresh_component_graph(self)
		end

		api.nvim_create_autocmd("BufEnter", {
			callback = function(e)
				if vim.list_contains(static.disabled.filetypes, vim.bo[e.buf].filetype) then
					return
				end
				local file = e.file:gsub("\\", "/")
				if last_root_dir and file:sub(1, #last_root_dir) == last_root_dir then
					return -- still in the same repo
				end

				local new_root_dir = get_root_by_git(file:match("^(.*)/[^/]*$"))

				--local head_file_path = ctx.get_head_file_path(e.file:gsub("\\", "/"):match("^(.*)/[^/]*$"))

				-- Case 1: Entering first buffer (Neovim just opened)
				-- last_root_dir = nil
				-- If buffer belongs to a git repo -> update
				if new_root_dir ~= nil and last_root_dir == nil then
					update_repo(new_root_dir)

				-- Case 2: Entering another buffer in the same repository
				-- Both HEAD paths are the same -> no update
				elseif new_root_dir == last_root_dir then
					return

				-- Case 3: Entering a buffer from a different repository
				-- HEAD path changed -> update
				elseif new_root_dir ~= nil and new_root_dir ~= last_root_dir then
					update_repo(new_root_dir)

				-- Case 4: Entering a buffer outside of any git repository
				-- new_root_dir = nil
				-- If we previously were in a git repo -> clear and update
				elseif new_root_dir == nil then
					if last_root_dir ~= nil then
						update_repo(nil)
					end
				end
			end,
		})
	end,
	style = { fg = colors.green },
	update = function(self, session_id)
		local ctx = self.context

		--- @cast ctx {root_dir: string|nil }
		if not ctx.root_dir then
			return ""
		end

		local branch = ""
		local head_file_path = ctx.root_dir .. "/.git/HEAD"
		if head_file_path then
			local head_file = io.open(head_file_path, "r")
			if head_file then
				local content = head_file:read("*all")
				head_file:close()
				-- branch name or commit hash
				branch = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
			end
		end
		local static = self.static
		--- @cast static { icon: string }
		return branch ~= "" and static.icon .. " " .. branch or ""
	end,
}

local Diff = {}

--- @alias DiffResult { added: integer, modified: integer, removed: integer }
--- @type DefaultComponent
Diff.Interface = {
	id = Id["git.diff.interface"],
	_plug_provided = true,
	static = {
		disabled = {
			filetypes = {
				"NvimTree",
				"neo-tree",
				"alpha",
				"dashboard",
				"TelescopePrompt",
			},
		},
	},
	context = {
		-- get_diff = function (bufnr)
		--   -- return self.temp.diff[bufnr]
		-- end,
	},
	init = function(self, session_id)
		local vim = vim
		local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph
		local api, bo, tonumber, list_contains, gmatch =
			vim.api, vim.bo, tonumber, vim.list_contains, string.gmatch

		--- @type table<integer, vim.SystemObj>
		local processes = {}

		--- @type table<integer, DiffResult?>
		local diff = {}

		local static = self.static
		--- @cast static { disabled: { filetypes: string[] } }

		local ctx = self.context
		--- @cast ctx { get_diff: fun(bufnr?: integer): DiffResult? }

		--- Export function to get the diff of a buffer
		--- @param bufnr? integer Buffer number, defaults to current buffer
		--- @return DiffResult
		ctx.get_diff = function(bufnr)
			return diff[bufnr or api.nvim_get_current_buf()]
		end

		local function process_diff(stdout)
			-- Adapted from https://github.com/wbthomason/nvim-vcs.lua
			local added, removed, modified = 0, 0, 0
			for old_start, old_count, new_start, new_count in
				gmatch(stdout, "@@%s*%-(%d+),?(%d*)%s*%+(%d+),?(%d*)%s*@@")
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

		api.nvim_create_autocmd({ "BufDelete", "BufWritePost", "BufEnter", "FileChangedShellPost" }, {
			callback = function(e)
				local event, bufnr = e.event, e.buf

				--- Clear the old diff when buffer is deleted or written
				if event ~= "BufEnter" then
					diff[bufnr] = nil

					--- Stop any running process
					local process = processes[bufnr]
					if process and not process:is_closing() then
						process:kill(15) --SIGTERM
						vim.defer_fn(function()
							if process and not process:is_closing() then
								process:kill(9)
							end
						end, 1500)
						processes[bufnr] = nil
					end
				end

				if event ~= "BufDelete" then
					--- If diff is caculated and filetype is not disabled, just refresh
					if diff[bufnr] or list_contains(static.disabled.filetypes, bo[bufnr].filetype) then
						refresh_component_graph(self) -- trigger update

						return
					end
					local file = e.file
					-- support windows path
					local parent_dir = file:match("^(.*)[/\\][^/\\]*$")
					if not parent_dir then
						return
					end
					local filename = file:match("[^/\\]*$")
					if not filename then
						return
					end

					if processes[bufnr] then
						return -- already running
					end

					processes[bufnr] = vim.system({
						"git",
						"-C",
						parent_dir,
						"--no-pager",
						"diff",
						"--no-color",
						"--no-ext-diff",
						"-U0",
						"--",
						filename,
					}, { text = true }, function(out)
						processes[bufnr] = nil
						local code, stdout = out.code, out.stdout
						if code == 15 or code == 9 then
							require("witch-line.utils.notifier").info("Killed git diff process" .. code)
							return -- killed
						elseif stdout and #stdout > 0 then
							vim.schedule(function()
								if api.nvim_buf_is_valid(bufnr) then
									diff[bufnr] = process_diff(stdout)
									refresh_component_graph(self) -- trigger update
								end
							end)
							return
						end
						-- no output or error occurred
						-- it means that there are no git in this forlder
						-- so we need to hide the components
						vim.schedule(function()
							if api.nvim_buf_is_valid(bufnr) then
								refresh_component_graph(self) -- trigger update
							end
						end)
					end)
				end
			end,
		})
	end,
	hidden = function(self, session_id)
		local static = self.static
		--- @cast static { disabled: { filetypes: string[] } }
		if vim.list_contains(static.disabled.filetypes, vim.bo.filetype) then
			return true
		end
		return false
	end,
}

--- @type DefaultComponent
Diff.Added = {
	id = Id["git.diff.added"],
	_plug_provided = true,
	static = {
		icon = "",
	},
	style = {
		fg = colors.green,
	},
	ref = {
		events = Id["git.diff.interface"],
		context = Id["git.diff.interface"],
		hidden = Id["git.diff.interface"],
	},
	update = function(self, session_id)
		local static = self.static
		--- @cast static { icon: string }

		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)
		--- @cast ctx { get_diff: fun(bufnr?: integer): DiffResult? }
		local diff = ctx.get_diff()
		if diff then
			local added = diff.added
			if added then
				return static.icon .. " " .. added
			end
		end
		return ""
	end,
}

---@type DefaultComponent
Diff.Modified = {
	id = Id["git.diff.modified"],
	_plug_provided = true,
	static = {
		icon = "",
	},
	style = {
		fg = colors.cyan,
	},
	ref = {
		context = Id["git.diff.interface"],
		hidden = Id["git.diff.interface"],
		events = Id["git.diff.interface"],
	},
	update = function(self, session_id)
		local static = self.static
		--- @cast static { icon: string }
		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)
		--- @cast ctx { get_diff: fun(bufnr?: integer): DiffResult? }
		local diff = ctx.get_diff()
		if diff then
			local modified = diff.modified
			if modified then
				return static.icon .. " " .. modified
			end
		end
		return ""
	end,
}

---@type DefaultComponent
Diff.Removed = {
	id = Id["git.diff.removed"],
	_plug_provided = true,
	static = {
		icon = "-",
	},
	style = {
		fg = colors.red,
	},
	ref = {
		events = Id["git.diff.interface"],
		context = Id["git.diff.interface"],
		hidden = Id["git.diff.interface"],
	},
	update = function(self, session_id)
		local static = self.static
		--- @cast static { icon: string }
		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)
		--- @cast ctx { get_diff: fun(bufnr?: integer): DiffResult? }
		local diff = ctx.get_diff(vim.api.nvim_get_current_buf())
		if diff then
			local removed = diff.removed
			if removed then
				return static.icon .. " " .. removed
			end
		end
		return ""
	end,
}

return {
	branch = Branch,
	diff = {
		interface = Diff.Interface,
		added = Diff.Added,
		removed = Diff.Removed,
		modified = Diff.Modified,
	},
}
