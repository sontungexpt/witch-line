local colors = require("witch-line.config.color")
local uv = vim.uv or vim.loop

local DEBUG_LOG = ("/tmp/witch-line-debug-%s.log"):format(vim.fn.getpid())
local function debug_log(...)
    if vim.g.witch_line_debug then
        local f = io.open(DEBUG_LOG, "a")
        if f then f:write(os.date("%H:%M:%S") .. " " .. table.concat({...}, " ") .. "\n") f:close() end
    end
end

local function get_root_by_git(dir_path)
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

--- @alias DiffResult { added: uinteger, modified: uinteger, removed: uinteger }
local function process_diff(stdout)
    local added, removed, modified = 0, 0, 0
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

---@class BranchCtx
---@field root_dir string|nil
---@type BranchCtx
local BRANCH_CTX = { root_dir = nil }

local DISABLED_FILETYPES = {
    "NvimTree",
    "neo-tree",
    "alpha",
    "dashboard",
    "TelescopePrompt",
}

---@type DefaultComponent
local Branch = {
    id = "wl.git.branch",
    ___builtin = true,
    config = {
        branch_icon = "",
        disabled_filetypes = DISABLED_FILETYPES,
    },
    init = function(self, _)
        local api = vim.api
        local ctx = BRANCH_CTX
        local last_root_dir = nil

        local file_changed, sec_arg = nil, nil
        local function update_repo(new_dir_path)
            if not file_changed then
                local uv = vim.uv or vim.loop
                if uv.os_uname().sysname == "Windows_NT" then
                    file_changed = assert(uv.new_fs_poll())
                    sec_arg = 1000
                else
                    file_changed = assert(uv.new_fs_event())
                    sec_arg = {}
                end
            end
            file_changed:stop()

            if new_dir_path then
                file_changed:start(
                    new_dir_path,
                    ---@cast sec_arg integer|table
                    sec_arg,
                    vim.schedule_wrap(function()
                        require("witch-line.engine").request_update_comp_graph(self)
                    end)
                )
            end

            last_root_dir = new_dir_path
            ctx.root_dir = new_dir_path
            require("witch-line.engine").request_update_comp_graph(self)
        end

        api.nvim_create_autocmd("BufEnter", {
            callback = function(e)
                if vim.list_contains(self.config.disabled_filetypes, vim.bo[e.buf].filetype) then
                    return
                end
                local file = e.file:gsub("\\", "/")
                if last_root_dir and file:sub(1, #last_root_dir) == last_root_dir then
                    return
                end

                local new_root_dir =
                    get_root_by_git(file:match("^(.*)/[^/]*$"))

                if new_root_dir ~= nil and last_root_dir == nil then
                    update_repo(new_root_dir)
                elseif new_root_dir == last_root_dir then
                    return
                elseif new_root_dir ~= nil and new_root_dir ~= last_root_dir then
                    update_repo(new_root_dir)
                elseif new_root_dir == nil then
                    if last_root_dir ~= nil then
                        update_repo(nil)
                    end
                end
            end,
        })
    end,
    style = { fg = colors.green },
    update = function(self, _)
        if not BRANCH_CTX.root_dir then
            return ""
        end

        local branch = ""
        local head_file_path = BRANCH_CTX.root_dir .. "/.git/HEAD"
        local head_file = io.open(head_file_path, "r")
        if head_file then
            local content = head_file:read("*all")
            head_file:close()
            branch = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
        end
        return branch ~= "" and self.config.branch_icon .. " " .. branch or ""
    end,
}

local Diff = {}

--- @type DefaultComponent
Diff.Interface = {
    id = "wl.git.diff.interface",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
    },
    init = function(self)
        local vim = vim
        local api = vim.api

        self.___processes = self.___processes or {}
        self.___diff_cache = self.___diff_cache or {}

        api.nvim_create_autocmd({ "BufDelete", "BufWritePost", "BufEnter", "FileChangedShellPost" }, {
            callback = function(e)
                local event, bufnr = e.event, e.buf

                if event ~= "BufEnter" then
                    self.___diff_cache[bufnr] = nil

                    local process = self.___processes[bufnr]
                    if process and not process:is_closing() then
                        process:kill(15)
                        vim.defer_fn(function()
                            if process and not process:is_closing() then
                                process:kill(9)
                            end
                        end, 1500)
                        self.___processes[bufnr] = nil
                    end
                end

                if event ~= "BufDelete" then
                    if self.___diff_cache[bufnr] or vim.list_contains(self.config.disabled_filetypes, vim.bo[bufnr].filetype) then
                        require("witch-line.engine").request_update_comp_graph(self)
                        return
                    end
                    local file = e.file
                    local parent_dir = file:match("^(.*)[/\\][^/\\]*$")
                    if not parent_dir then
                        return
                    end
                    local filename = file:match("[^/\\]*$")
                    if not filename then
                        return
                    end

                    if self.___processes[bufnr] then
                        return
                    end

                    self.___processes[bufnr] = vim.system({
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
                        self.___processes[bufnr] = nil
                        local code, stdout = out.code, out.stdout
                        if code == 15 or code == 9 then
                            require("witch-line.util.notifier").info("Killed git diff process" .. code)
                            return
                        elseif stdout and #stdout > 0 then
                            vim.schedule(function()
                                if api.nvim_buf_is_valid(bufnr) then
                                    self.___diff_cache[bufnr] = process_diff(
                                        stdout)
                                    require("witch-line.engine").request_update_comp_graph(self)
                                end
                            end)
                            return
                        end
                        vim.schedule(function()
                            if api.nvim_buf_is_valid(bufnr) then
                                require("witch-line.engine").request_update_comp_graph(self)
                            end
                        end)
                    end)
                end
            end,
        })
    end,
    hidden = function(self, _)
        return vim.list_contains(self.config.disabled_filetypes, vim.bo.filetype)
    end,
    context = function(self, session)
        return { diff = self.___diff_cache[vim.api.nvim_get_current_buf()] }
    end,
}

--- Determine if diff should be hidden based on filetype.
---@param self ManagedComponent
---@return boolean
local function diff_hidden(self, _)
    return vim.list_contains(self.config.disabled_filetypes, vim.bo.filetype)
end

--- @type DefaultComponent
Diff.Added = {
    id = "wl.git.diff.added",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "",
    },
    ref = {
        events = "wl.git.diff.interface",
        context = "wl.git.diff.interface",
    },
    style = { fg = colors.green },
    hidden = diff_hidden,
    update = function(self, session)
        debug_log("GIT_ADDED update", "self.id=" .. tostring(self.id))
        debug_log("GIT_ADDED context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("GIT_ADDED ctx", type(ctx))
        if ctx.diff then
            local added = ctx.diff.added
            if added then
                return self.config.icon .. " " .. added
            end
        end
        return ""
    end,
}

---@type DefaultComponent
Diff.Modified = {
    id = "wl.git.diff.modified",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "",
    },
    ref = {
        events = "wl.git.diff.interface",
        context = "wl.git.diff.interface",
    },
    style = { fg = colors.cyan },
    hidden = diff_hidden,
    update = function(self, session)
        debug_log("GIT_MODIFIED update", "self.id=" .. tostring(self.id))
        debug_log("GIT_MODIFIED context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("GIT_MODIFIED ctx", type(ctx))
        if ctx.diff then
            local modified = ctx.diff.modified
            if modified then
                return self.config.icon .. " " .. modified
            end
        end
        return ""
    end,
}

---@type DefaultComponent
Diff.Removed = {
    id = "wl.git.diff.removed",
    ___builtin = true,
    config = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "-",
    },
    ref = {
        events = "wl.git.diff.interface",
        context = "wl.git.diff.interface",
    },
    style = { fg = colors.red },
    hidden = diff_hidden,
    update = function(self, session)
        debug_log("GIT_REMOVED update", "self.id=" .. tostring(self.id))
        debug_log("GIT_REMOVED context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("GIT_REMOVED ctx", type(ctx))
        if ctx.diff then
            local removed = ctx.diff.removed
            if removed then
                return self.config.icon .. " " .. removed
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
