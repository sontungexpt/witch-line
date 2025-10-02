local Id       = require("witch-line.constant.id").Id
local colors   = require("witch-line.constant.color")

---@type DefaultComponent
local Branch   = {
    id = Id["git.branch"],
    _plug_provided = true,
    user_events = { "GitBranchChanged" },
    static = {
        icon = "",
    },
    context = function()
        local git_dir = vim.fn.finddir(".git", ".;")
        if git_dir ~= "" then
            return {
                head_file_path = git_dir .. "/HEAD",
            }
        end
        return nil
    end,

    -- init = function(self, ctx, static)
    --     local uv = vim.uv or vim.loop
    --     local api = vim.api

    --     --- @type table<string, table<integer,true>|{uv.fs_event_t|uv.fs_poll_t}>
    --     local cache = {

    --     }
    --     if ctx and ctx.head_file_path then
    --         local head_file_path = ctx.head_file_path
    --         local cur_buf = api.nvim_get_current_buf()

    --         api.nvim_create_autocmd({ "BufEnter", "BufLeave" }, {
    --             callback = function(e)
    --                 local buf = e.buf
    --                 if e.event == "BufEnter" then
    --                     if not cache[head_file_path] then
    --                         cache[head_file_path] = {
    --                             [buf] = true,
    --                             file_changed = uv.os_uname().sysname == "Windows_NT" and uv.new_fs_event() or
    --                                 uv.new_fs_poll()
    --                         }
    --                         cache[head_file_path].file_changed:start(head_file_path, 1000, vim.schedule_wrap(function()
    --                             if api.nvim_get_current_buf() == cur_buf then
    --                                 vim.api.nvim_exec_autocmds("User", { pattern = "GitBranchChanged" })
    --                             end
    --                         end))
    --                     end
    --                     cache[head_file_path][buf] = true
    --                 else
    --                     cache[head_file_path][buf] = nil
    --                     local key = next(cache[head_file_path])
    --                     if key == "file_changed" then
    --                         key = next(cache[head_file_path], key)
    --                     end
    --                     if key == nil then
    --                         file_changed:stop()
    --                         file_changed:close()
    --                         cache[head_file_path] = nil
    --                     end
    --                 end
    --             end,
    --         })
    --     end
    -- end,
    style = { fg = colors.green },
    update = function(self, ctx, static)
        local branch = ""
        if ctx and ctx.head_file_path then
            local head_file = io.open(ctx.head_file_path, "r")
            local content = head_file:read("*all")
            head_file:close()
            -- branch name  or commit hash
            branch = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
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
    hide = function(self, ctx, static, session_id)
        if #vim.fn.expand('%') == 0 then
            return true
        end
    end,
    init = function(self, ctx, static)
        -- Don't show git diff when current buffer doesn't have a filename
        local api, fn = vim.api, vim.fn
        local active_buf = tostring(vim.api.nvim_get_current_buf())
        local diff_output_cache = {}
        local diff_args = {
            cmd = string.format(
                [[git -C %s --no-pager diff --no-color --no-ext-diff -U0 -- %s]],
                fn.expand('%:h'),
                fn.expand('%:t')
            ),
            on_stdout = function(_, data)
                if next(data) then
                    diff_output_cache = vim.list_extend(diff_output_cache, data)
                end
            end,
            on_stderr = function(_, data)
                data = table.concat(data, '\n')
                if #data > 0 then
                    git_diff = nil
                    diff_output_cache = {}
                end
            end,
            on_exit = function()
                if #diff_output_cache > 0 then
                    process_diff(diff_output_cache)
                else
                    git_diff = { added = 0, modified = 0, removed = 0 }
                end
                diff_cache[vim.api.nvim_get_current_buf()] = git_diff
            end,
        }
        M.update_git_diff()
    end,
    update = function(self, ctx, static)
        if ctx then
            return ""
        end
        return nil
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
