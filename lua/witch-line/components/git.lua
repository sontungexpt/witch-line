local Id       = require("witch-line.constant.id").Id
local colors   = require("witch-line.constant.color")

---@type DefaultComponent
local Branch   = {
    id = Id["git.branch"],
    _plug_provided = true,
    user_events = { "GitBranchChanged" },
    static = {
      icon = "",
      skip_check = {
        filetypes = {
          "NvimTree",
          "neo-tree",
          "alpha" ,
          "dashboard" ,
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
                      vim.api.nvim_exec_autocmds("User", { pattern = "GitBranchChanged" })
                  end)
                )
            end

            -- Update state
            last_head_file_path = new_path
            -- Trigger immediately so the branch text updates
            api.nvim_exec_autocmds("User", { pattern = "GitBranchChanged" })
        end      --

        api.nvim_create_autocmd("BufEnter", {
          callback = function(e)
            if vim.list_contains(static.skip_check.filetypes,vim.bo[e.buf].filetype)
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
            local content = head_file:read("*all")
            head_file:close()
            -- branch name  or commit hash
            branch = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
        end
        return branch ~= "" and static.icon .. " " .. branch or ""
    end,
}
local Diff  = {}

--- @type DefaultComponent
Diff.Interface = {
    id = Id["git.diff.interface"],
    events = { "BufWritePost", "BufEnter" },
    _plug_provided = true,
    hide = function(self, ctx, static, session_id)
        if #vim.fn.expand('%') == 0 then
            return true
        end
    end,
    init = function(self, ctx, static)
    end,
    update = function(self, ctx, static)
        -- Don't show git diff when current buffer doesn't have a filename
        local api, fn = vim.api, vim.fn
        local active_buf = tostring(vim.api.nvim_get_current_buf())
        local diff_output_cache = {}
        local diff_cache = {}
        local git_diff

        ---@param bufnr number|nil
        function M.get_sign_count(bufnr)
          if bufnr then
            return diff_cache[bufnr]
          end
          if M.src then
            git_diff = M.src()
            diff_cache[vim.api.nvim_get_current_buf()] = git_diff
          elseif vim.g.actual_curbuf ~= nil and active_bufnr ~= vim.g.actual_curbuf then
            -- Workaround for https://github.com/nvim-lualine/lualine.nvim/issues/286
            -- See upstream issue https://github.com/neovim/neovim/issues/15300
            -- Diff is out of sync re sync it.
            M.update_diff_args()
          end
          return git_diff
        end
        ---process diff data and update git_diff{ added, removed, modified }
        ---@param data string output on stdout od git diff job
        local function process_diff(data)
          -- Adapted from https://github.com/wbthomason/nvim-vcs.lua
          local added, removed, modified = 0, 0, 0
          for _, line in ipairs(data) do
            if string.find(line, [[^@@ ]]) then
              local tokens = vim.fn.matchlist(line, [[^@@ -\v(\d+),?(\d*) \+(\d+),?(\d*)]])
              local line_stats = {
                mod_count = tokens[3] == nil and 0 or tokens[3] == '' and 1 or tonumber(tokens[3]),
                new_count = tokens[5] == nil and 0 or tokens[5] == '' and 1 or tonumber(tokens[5]),
              }

              if line_stats.mod_count == 0 and line_stats.new_count > 0 then
                added = added + line_stats.new_count
              elseif line_stats.mod_count > 0 and line_stats.new_count == 0 then
                removed = removed + line_stats.mod_count
              else
                local min = math.min(line_stats.mod_count, line_stats.new_count)
                modified = modified + min
                added = added + line_stats.new_count - min
                removed = removed + line_stats.mod_count - min
              end
            end
          end
          git_diff = { added = added, modified = modified, removed = removed }
        end
        vim.system({
          "git" , "-C", fn.expand('%:h'),
          "--no-pager diff", "--no-color", "--no-ext-diff", "-U0",
          "--", fn.expand('%:t')
        }, { text  = true }, function (out)
            if out.code ~= 0 then
              git_diff = nil
              diff_output_cache = {}
              return
            end

            if out.stdout and #out.stdout > 0 then
              local lines = vim.split(out.stdout, "\n", { trimempty = true })
              diff_output_cache = vim.list_extend(diff_output_cache, lines)
              process_diff(diff_output_cache)
            else
              git_diff = { added = 0, modified = 0, removed = 0 }
            end

            diff_cache[vim.api.nvim_get_current_buf()] = git_diff
        end)
    end,

}
Diff.Add       = {
    update = function(configs)
        local git_status = vim.b.gitsigns_status_dict
        return git_status.added and git_status.added > 0 and configs.added .. " " .. git_status.added
            or ""
    end,
}


Diff.Change  = {
    styles = { fg = "DiffChange" },
    update = function(configs)
        local git_status = vim.b.gitsigns_status_dict
        return git_status.changed
            and git_status.changed > 0
            and configs.changed .. " " .. git_status.changed
            or ""
    end,
}
local Delete = {
    styles = { fg = "DiffDelete" },
    update = function(configs)
        local git_status = vim.b.gitsigns_status_dict
        return git_status.removed
            and git_status.removed > 0
            and configs.removed .. " " .. git_status.removed
            or ""
    end,
}

return {
    branch = Branch,
    diff = Diff
}
