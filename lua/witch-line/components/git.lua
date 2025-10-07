local Id     = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")


---@type DefaultComponent
local Branch = {
  id = Id["git.branch"],
  _plug_provided = true,
  static = {
    icon = "",
    skip_check = {
      filetypes = {
        "NvimTree",
        "neo-tree",
        "alpha",
        "dashboard",
        "TelescopePrompt"
      },
    }
  },
  context = {
    -- get_head_file_path = function(dir_path)
    --   local uv = vim.uv or vim.loop
    --   local prev = ''
    --   local dir = dir_path or uv.cwd()

    --   while dir ~= prev do
    --     local git_path = dir .. '/.git'
    --     local stat = uv.fs_stat(git_path)
    --     if stat then
    --       if stat.type == 'directory' then
    --         return git_path .. '/HEAD'
    --       elseif stat.type == 'file' then
    --         local fd = io.open(git_path, 'r')
    --         if fd then
    --           local line = fd:read('*l')
    --           fd:close()
    --           local gitdir = line:match("^gitdir:%s*(.-)%s*$")
    --           if gitdir then
    --             -- Handle relative gitdir path
    --             if not gitdir:match("^/") and not gitdir:match("^%a:[/\\]") then
    --               gitdir = dir .. "/" .. gitdir
    --             end
    --             -- Normalize and verify
    --             return uv.fs_realpath(gitdir .. '/HEAD')
    --           end
    --         end
    --       end
    --     end

    --     prev = dir
    --     dir = dir:match('^(.*)[/\\][^/\\]+$') or dir
    --   end
    --   return nil
    -- end,
    get_root_by_git = function(dir_path)
      local uv = vim.uv or vim.loop
      local prev = ''
      local dir = dir_path or uv.cwd()
      while dir ~= prev do
        local git_path = dir .. '/.git'
        local stat = uv.fs_stat(git_path)
        if stat then
          if stat.type == 'directory' then
            return dir
          elseif stat.type == 'file' then
            local fd = io.open(git_path, 'r')
            if fd then
              local line = fd:read('*l')
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
        dir = dir:match('^(.*)[/\\][^/\\]+$') or dir -- fallback to prevent infinite loop when reaching root
      end
      return nil
    end,

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
  init = function(self, ctx, static)
    local uv, api = vim.uv or vim.loop, vim.api
    local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph

    local is_win = uv.os_uname().sysname == "Windows_NT"
    local file_changed = is_win and uv.new_fs_poll() or uv.new_fs_event()

    -- local last_head_file_path = nil
    local last_root_dir = nil

    -- helper: restart watcher + trigger event
    local function update_repo(new_dir_path)
      file_changed:stop()

      if new_dir_path then
        file_changed:start(new_dir_path,
          is_win and 1000 or {},
          vim.schedule_wrap(function()
            refresh_component_graph(self)
          end)
        )
      end

      -- Update state
      -- last_head_file_path = new_dir_path
      last_root_dir = new_dir_path
      self.temp = new_dir_path -- store current dir path that contains .git to use in update()
      -- Trigger immediately so the branch text updates
      refresh_component_graph(self)
    end

    api.nvim_create_autocmd({ "BufEnter" }, {
      callback = function(e)
        if vim.list_contains(static.skip_check.filetypes, vim.bo[e.buf].filetype) then
          return
        end

        local parent_dir = e.file:gsub("\\", "/"):match("^(.*)/[^/]*$")
        if not parent_dir then
          update_repo(nil)
          return
        elseif last_root_dir and parent_dir:sub(1, #last_root_dir) == last_root_dir then
          return -- still in the same repo
        end

        local new_root_dir = ctx.get_root_by_git(parent_dir)

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
  update = function(self, ctx, static)
    if not self.temp then
      return ""
    end

    local branch = ""
    local head_file_path = self.temp .. "/.git/HEAD"
    if head_file_path then
      local head_file = io.open(head_file_path, "r")
      if head_file then
        local content = head_file:read("*all")
        head_file:close()
        -- branch name or commit hash
        branch = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
      end
    end
    return branch ~= "" and static.icon .. " " .. branch or ""
  end,
}


local Diff     = {}

--- @type DefaultComponent
Diff.Interface = {
  id = Id["git.diff.interface"],
  events = { "BufWritePost", "BufEnter", "FileChangedShellPost" },
  _plug_provided = true,
  context = {
    diff_cache = {}, -- Stores last known value of diff of a buffer
    process_diff = function(lines)
      -- Adapted from https://github.com/wbthomason/nvim-vcs.lua
      local added, removed, modified = 0, 0, 0
      for i = 1, #lines do
        -- match hunk header like: @@ -12,3 +14,4 @@
        -- captures: old_start, old_count, new_start, new_count
        local old_start, old_count, new_start, new_count = lines[i]:match(
          "^@@ %-([0-9]+),?([0-9]*) %+([0-9]+),?([0-9]*)")

        if old_start then
          -- convert captures to numbers using same rules as original:
          -- nil → 0, "" → 1, else → tonumber
          local mod_count = (old_count == nil and 0)
              or (old_count == "" and 1)
              or tonumber(old_count) or 0

          new_count = (new_count == nil and 0)
              or (new_count == "" and 1)
              or tonumber(new_count) or 0

          if mod_count == 0 and new_count > 0 then
            added = added + new_count
          elseif mod_count > 0 and new_count == 0 then
            removed = removed + mod_count
          else
            local minv = math.min(mod_count, new_count)
            modified = modified + minv
            added = added + (new_count - minv)
            removed = removed + (mod_count - minv)
          end
        end
      end
      return { added = added, modified = modified, removed = removed }
    end,
    is_skipped = function(static)
      return vim.list_contains(static.skip_check.filetypes, vim.bo.filetype)
    end
  },
  static = {
    skip_check = {
      filetypes = {
        "NvimTree",
        "neo-tree",
        "alpha",
        "dashboard",
        "TelescopePrompt"
      },
    }
  },
  temp = {}, -- temp storage
  init = function(self, ctx, static)
    -- Initialize temp storage
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWritePost" }, {
      callback = function(e)
        ctx.diff_cache[e.buf] = nil
      end
    })
  end,
  pre_update = function(self, ctx, static)
    local api, fn = vim.api, vim.fn
    local bufnr = api.nvim_get_current_buf()
    local diff_cache = ctx.diff_cache
    --- Skip check then hide components immediately
    if ctx.is_skipped(static) or diff_cache[bufnr] then
      api.nvim_exec_autocmds("User", { pattern = "GitDiffUpdate" })
    else
      self.temp.process = vim.system({
        "git", "-C", fn.expand('%:h'),
        "--no-pager", "diff", "--no-color", "--no-ext-diff", "-U0",
        "--", fn.expand('%:t')
      }, { text = true }, function(out)
        self.temp.process = nil
        local code, stdout = out.code, out.stdout
        if code == 15 or code == 9 then
          require("witch-line.utils.notifier").info("Killed git diff process")
          return -- killed
        elseif stdout and #stdout > 0 then
          local lines = vim.split(stdout, "\n", { trimempty = true })
          vim.schedule(function()
            if api.nvim_buf_is_valid(bufnr) then
              diff_cache[bufnr] = ctx.process_diff(lines)
              api.nvim_exec_autocmds("User", { pattern = "GitDiffUpdate" })
            end
          end)
          return
        end
        -- No output or error occurred
        -- It means that there are no git in this forlder
        -- So we need to hide the components
        vim.schedule(function()
          api.nvim_exec_autocmds("User", { pattern = "GitDiffUpdate" })
        end)
      end)
    end
  end,
  hidden = function(self, ctx, static, session_id)
    local filepath = vim.fn.expand('%:p')
    if filepath == "" or ctx.is_skipped(static) then
      local process = self.temp.process
      if process and not process:is_closing() then
        process:kill(15) --SIGTERM
        vim.defer_fn(function()
          if process and not process:is_closing() then
            process:kill(9)
          end
        end, 1500)
        self.temp.process = nil
      end
      return true
    end
    return false
  end,
}

--- @type DefaultComponent
Diff.Added     = {
  id = Id["git.diff.added"],
  user_events = { "GitDiffUpdate" },
  _plug_provided = true,
  -- inherit = Id["git.diff.interface"],
  static = {
    icon = ""
  },
  style = {
    fg = colors.green
  },
  ref = {
    context = Id["git.diff.interface"],
    hidden = Id["git.diff.interface"]
  },
  update = function(self, ctx, static, session_id)
    local bufnr = vim.api.nvim_get_current_buf()
    local diff_cache = ctx.diff_cache[bufnr]
    if diff_cache then
      local added = diff_cache.added
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
  user_events = { "GitDiffUpdate" },
  _plug_provided = true,
  -- inherit = Id["git.diff.interface"],
  static = {
    icon = ""
  },
  style = {
    fg = colors.cyan
  },
  ref = {
    context = Id["git.diff.interface"],
    hidden = Id["git.diff.interface"]
  },
  update = function(self, ctx, static, session_id)
    local bufnr = vim.api.nvim_get_current_buf()
    local diff_cache = ctx.diff_cache[bufnr]
    if diff_cache then
      local modified = diff_cache.modified
      if modified then
        return static.icon .. " " .. modified
      end
    end
    return ""
  end,
}

---@type DefaultComponent
Diff.Removed  = {
  id = Id["git.diff.removed"],
  user_events = { "GitDiffUpdate" },
  _plug_provided = true,
  -- inherit = Id["git.diff.interface"],
  static = {
    icon = "-"
  },
  style = {
    fg = colors.red,
  },
  ref = {
    context = Id["git.diff.interface"],
    hidden = Id["git.diff.interface"]
  },
  update = function(self, ctx, static, session_id)
    local bufnr = vim.api.nvim_get_current_buf()
    local diff_cache = ctx.diff_cache[bufnr]
    if diff_cache then
      local removed = diff_cache.removed
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
  }
}
