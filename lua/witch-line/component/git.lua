local vim = vim
local uv, api, bo, schedule, system, list_contains = vim.uv or vim.loop, vim.api, vim.bo, vim.schedule, vim.system,
    vim.list_contains
local engine = require("witch-line.engine")

local colors = require("witch-line.constant.color")

local function get_root_by_git(dir_path)
    local dir = dir_path or uv.cwd()
    local prev = ""
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
                        if not gitdir:match("^/") and not gitdir:match("^%a:[/\\]") then
                            gitdir = dir .. "/" .. gitdir
                        end
                        return uv.fs_realpath(gitdir)
                    end
                end
            end
        end
        prev = dir
        dir = dir:match("^(.*)[/\\][^/\\]+$") or dir
    end
    return nil
end



local DISABLED_FILETYPES = {
    "NvimTree",
    "neo-tree",
    "alpha",
    "dashboard",
    "TelescopePrompt",
}

local branch_name = ""

---@type DefaultComponent
local Branch = {
    id = "wl.git.branch",
    ___builtin = true,
    config = {
        branch_icon = "",
        disabled_filetypes = DISABLED_FILETYPES,
    },
    init = function(self, _)
        local git_root = nil

        local function refresh_branch()
            if not git_root then
                branch_name = ""
                return
            end
            local f = io.open(git_root .. "/.git/HEAD", "r")
            if f then
                local content = f:read("*all")
                f:close()
                branch_name = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
            else
                branch_name = ""
            end
        end

        local watcher, watcher_opts = nil, nil
        local on_head_change = vim.schedule_wrap(function()
            refresh_branch()
            engine.request_update_comp_graph(self)
        end)

        local function update_repo(new_dir_path)
            if not watcher then
                if uv.os_uname().sysname == "Windows_NT" then
                    watcher = assert(uv.new_fs_poll())
                    watcher_opts = 1000
                else
                    watcher = assert(uv.new_fs_event())
                    watcher_opts = {}
                end
            end
            watcher:stop()

            if new_dir_path then
                watcher:start(new_dir_path .. "/.git", watcher_opts, on_head_change)
            end

            git_root = new_dir_path
            on_head_change()
        end

        api.nvim_create_autocmd("BufEnter", {
            callback = function(e)
                if list_contains(self.config.disabled_filetypes, bo[e.buf].filetype) then
                    return
                end
                local file = e.file:gsub("\\", "/")
                if git_root and file:sub(1, #git_root) == git_root then
                    return
                end

                local new_root_dir = get_root_by_git(file:match("^(.*)/[^/]*$"))

                if new_root_dir ~= git_root then
                    update_repo(new_root_dir)
                end
            end,
        })
    end,
    style = { fg = colors.green },
    update = function(self, _)
        return branch_name ~= "" and self.config.branch_icon .. " " .. branch_name or ""
    end,
}

local Diff = {}

--- @alias DiffResult { added: integer, modified: integer, removed: integer }
--- Parse `git diff -U0` output into per-hunk counts using hunk headers.
---
--- Matches `@@ -old_start,old_count +new_start,new_count @@` where
--- old_count = removed lines, new_count = added lines per hunk.
local function process_diff(stdout)
    local added, modified, removed = 0, 0, 0
    for _, old_count, _, new_count in stdout:gmatch("@@%s-%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s@@") do
        local remove_count = tonumber(old_count) or 1
        local add_count = tonumber(new_count) or 1
        local m = add_count < remove_count and add_count or remove_count
        modified = modified + m
        added = added + add_count - m
        removed = removed + remove_count - m
    end
    return { added = added, modified = modified, removed = removed }
end

--- @type DefaultComponent
Diff.Interface = {
    id = "wl.git.diff.interface",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
    },
    init = function(self)
        self.___processes = self.___processes or {}
        self.___diff_cache = self.___diff_cache or {}

        local function kill_process(bufnr)
            local proc = self.___processes[bufnr]
            if proc and not proc:is_closing() then
                proc:kill(15)
            end
            self.___processes[bufnr] = nil
            self.___diff_cache[bufnr] = nil
        end

        local function spawn_diff(bufnr, parent_dir, filename)
            if self.___processes[bufnr] then return end
            self.___processes[bufnr] = system({
                "git", "-C", parent_dir, "diff",
                "--no-color", "--no-ext-diff", "-U0", "--", filename,
            }, { text = true }, function(out)
                self.___processes[bufnr] = nil
                if out.code == 15 then return end
                schedule(function()
                    if not api.nvim_buf_is_valid(bufnr) then return end
                    if out.stdout and #out.stdout > 0 then
                        self.___diff_cache[bufnr] = process_diff(out.stdout)
                    end
                    engine.request_update_comp_graph(self)
                end)
            end)
        end

        api.nvim_create_autocmd({ "BufDelete", "BufWritePost", "BufReadPost", "BufEnter", "FileChangedShellPost" }, {
            callback = function(e)
                local event, bufnr = e.event, e.buf

                if event ~= "BufEnter" then
                    kill_process(bufnr)
                    if event == "BufDelete" then return end
                end

                local file = e.file
                if not file then return end

                if not list_contains(self.config.disabled_filetypes, bo[bufnr].filetype)
                    and not self.___diff_cache[bufnr] then
                    local parent_dir, filename = file:match("^(.*)[/\\]([^/\\]+)$")
                    if parent_dir then
                        spawn_diff(bufnr, parent_dir, filename)
                    end
                else
                    engine.request_update_comp_graph(self)
                end
            end,
        })
    end,
    hidden = function(self, _)
        return list_contains(self.config.disabled_filetypes, bo.filetype)
    end,
    context = function(self, _)
        return { diff = self.___diff_cache[api.nvim_get_current_buf()] }
    end,
}


local function diff_update(self, session, field)
    local ctx = self.context(self, session)
    if ctx.diff then
        local v = ctx.diff[field]
        if v then
            return self.config.icon .. " " .. v
        end
    end
    return ""
end

--- @type DefaultComponent
Diff.Added = {
    id = "wl.git.diff.added",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "",
    },
    ref = {
        events = "wl.git.diff.interface",
        context = "wl.git.diff.interface",
        hidden = "wl.git.diff.interface",
    },
    style = { fg = colors.green },
    update = function(self, session) return diff_update(self, session, "added") end,
}

---@type DefaultComponent
Diff.Modified = {
    id = "wl.git.diff.modified",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "",
    },
    ref = {
        events = "wl.git.diff.interface",
        context = "wl.git.diff.interface",
        hidden = "wl.git.diff.interface",
    },
    style = { fg = colors.cyan },
    update = function(self, session) return diff_update(self, session, "modified") end,
}

---@type DefaultComponent
Diff.Removed = {
    id = "wl.git.diff.removed",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "",
    },
    ref = {
        events = "wl.git.diff.interface",
        context = "wl.git.diff.interface",
        hidden = "wl.git.diff.interface",
    },
    style = { fg = colors.red },
    update = function(self, session) return diff_update(self, session, "removed") end,
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
