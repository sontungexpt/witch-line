local Id     = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")

---@type DefaultComponent
local Branch = {
  id = Id["git.branch"],
  _plug_provided = true,
  -- user_events = { "GitBranchChanged" },
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
      buftypes = {
      },
    }
  },
  context = {
    get_head_file_path = function()
      local fn = vim.fn
      local git_dir = fn.finddir(".git", ".;")
      if git_dir ~= "" then
        return fn.fnamemodify(git_dir, ":p") .. "HEAD"
      end
      return nil
    end,
  },
  init = function(self, ctx, static)
    local uv = vim.uv or vim.loop
    local api = vim.api
    local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph


    local is_win = uv.os_uname().sysname == "Windows_NT"
    local file_changed = is_win and uv.new_fs_poll() or uv.new_fs_event()

    local last_head_file_path = nil
    -- helper: restart watcher + trigger event
    local function update_repo(new_path)
      file_changed:stop()

      if new_path then
        file_changed:start(new_path,
          is_win and 1000 or {},
          vim.schedule_wrap(function()
            refresh_component_graph(self)
          end)
        )
      end

      -- Update state
      last_head_file_path = new_path
      -- Trigger immediately so the branch text updates
      refresh_component_graph(self)
    end --

    api.nvim_create_autocmd("BufEnter", {
      callback = function(e)
        if vim.list_contains(static.skip_check.filetypes, vim.bo[e.buf].filetype)
            or vim.list_contains(static.skip_check.buftypes, vim.bo[e.buf].buftype)
        then
          return
        end
        local head_file_path = ctx.get_head_file_path()

        -- Case 1: Entering first buffer (Neovim just opened)
        -- last_head_file_path = nil
        -- If buffer belongs to a git repo -> update
        if last_head_file_path == nil and head_file_path ~= nil then
          update_repo(head_file_path)

          -- Case 2: Entering another buffer in the same repository
          -- Both HEAD paths are the same -> no update
        elseif head_file_path == last_head_file_path then
          return

          -- Case 3: Entering a buffer from a different repository
          -- HEAD path changed -> update
        elseif head_file_path ~= nil and head_file_path ~= last_head_file_path then
          update_repo(head_file_path)

          -- Case 4: Entering a buffer outside of any git repository
          -- head_file_path = nil
          -- If we previously were in a git repo -> clear and update
        elseif head_file_path == nil then
          if last_head_file_path ~= nil then
            update_repo(nil)
          end
        end
      end,
    })
  end,
  style = { fg = colors.green },
  update = function(self, ctx, static)
    local branch = ""
    local head_file_path = ctx.get_head_file_path()
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
  events = { "BufWritePost", "BufEnter" },
  _plug_provided = true,
  context = {
    diff_cache = {}, -- Stores last known value of diff of a buffer
    process_diff = function(lines)
      -- Adapted from https://github.com/wbthomason/nvim-vcs.lua
      local added, removed, modified = 0, 0, 0
      for _, line in ipairs(lines) do
        -- match hunk header like: @@ -12,3 +14,4 @@
        -- captures: old_start, old_count, new_start, new_count
        local old_start, old_count, new_start, new_count = line:match("^@@ %-([0-9]+),?([0-9]*) %+([0-9]+),?([0-9]*)")

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
    is_skipped = function (static)
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
    vim.api.nvim_create_autocmd({"BufLeave", "BufWritePost"}, {
      callback = function(e)
        ctx.diff_cache[e.buf] = nil
      end
    })
  end,
  pre_update = function(self, ctx, static)
    local api, fn = vim.api, vim.fn
    local bufnr = api.nvim_get_current_buf()
    local diff_cache = ctx.diff_cache

    if diff_cache[bufnr] then
      api.nvim_exec_autocmds("User", { pattern = "GitDiffUpdate" })
    elseif ctx.is_skipped(static) then
      api.nvim_exec_autocmds("User", { pattern = "GitDiffUpdate" })
    else
      self.temp.process = vim.system({
        "git", "-C", fn.expand('%:h'),
        "--no-pager", "diff", "--no-color", "--no-ext-diff", "-U0",
        "--", fn.expand('%:t')
      }, { text = true }, function(out)
        self.temp.process = nil
        if out.code == 15 or out.code == 9 then
          require("witch-line.utils.notifier").info("Killed git diff process")
          return -- killed
        elseif out.stdout and #out.stdout > 0 then
          local lines = vim.split(out.stdout, "\n", { trimempty = true })
          diff_cache[bufnr] =  api.nvim_buf_is_valid(bufnr) and ctx.process_diff(lines) or nil
        else
          -- do nothing
          -- diff_cache[bufnr] = {
          --   added = 0,
          --   modified = 0,
          --   removed = 0,
          -- }
        end
        vim.schedule(function()
          api.nvim_exec_autocmds("User", { pattern = "GitDiffUpdate" })
        end)
      end)
    end
  end,
  hidden = function(self, ctx, static, session_id)
    local filepath = vim.fn.expand('%:p')
    if filepath == "" or  ctx.is_skipped(static) then
      local process = self.temp.process
      if process and not process:is_closing() then
        process:kill(15) --SIGTERM
        vim.defer_fn(function ()
          if process and not process:is_closing() then
            process:kill(9)
          end
        end, 2000)
        self.temp.process = nil
      end
      return true
    end
    return false
  end,
}

--- @type DefaultComponent
Diff.Added = {
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
