
local colors = require("witch-line.constant.color")

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
    id = "git.branch",
    _plug_provided = true,
    static = {
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
                        require("witch-line.core.handler").request_update_comp_graph(self)
                    end)
                )
            end

            last_root_dir = new_dir_path
            ctx.root_dir = new_dir_path
            require("witch-line.core.handler").request_update_comp_graph(self)
        end

        api.nvim_create_autocmd("BufEnter", {
            callback = function(e)
                if vim.list_contains(self.static.disabled_filetypes, vim.bo[e.buf].filetype) then
                    return
                end
                local file = e.file:gsub("\\", "/")
                if last_root_dir and file:sub(1, #last_root_dir) == last_root_dir then
                    return
                end

                local new_root_dir =
                    require("witch-line.components.git.utils").get_root_by_git(file:match("^(.*)/[^/]*$"))

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
        return branch ~= "" and self.static.branch_icon .. " " .. branch or ""
    end,
}

local Diff = {}

--- @type DefaultComponent
Diff.Interface = {
    id = "git.diff.interface",
    _plug_provided = true,
    static = {
        disabled_filetypes = DISABLED_FILETYPES,
    },
    init = function(self, _)
        local vim = vim
        local api = vim.api

        self._processes = self._processes or {}
        self._diff_cache = self._diff_cache or {}

        api.nvim_create_autocmd({ "BufDelete", "BufWritePost", "BufEnter", "FileChangedShellPost" }, {
            callback = function(e)
                local event, bufnr = e.event, e.buf

                if event ~= "BufEnter" then
                    self._diff_cache[bufnr] = nil

                    local process = self._processes[bufnr]
                    if process and not process:is_closing() then
                        process:kill(15)
                        vim.defer_fn(function()
                            if process and not process:is_closing() then
                                process:kill(9)
                            end
                        end, 1500)
                        self._processes[bufnr] = nil
                    end
                end

                if event ~= "BufDelete" then
                    if self._diff_cache[bufnr] or vim.list_contains(self.static.disabled_filetypes, vim.bo[bufnr].filetype) then
                        require("witch-line.core.handler").request_update_comp_graph(self)
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

                    if self._processes[bufnr] then
                        return
                    end

                    self._processes[bufnr] = vim.system({
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
                        self._processes[bufnr] = nil
                        local code, stdout = out.code, out.stdout
                        if code == 15 or code == 9 then
                            require("witch-line.utils.notifier").info("Killed git diff process" .. code)
                            return
                        elseif stdout and #stdout > 0 then
                            vim.schedule(function()
                                if api.nvim_buf_is_valid(bufnr) then
                                    self._diff_cache[bufnr] = require("witch-line.components.git.utils").process_diff(
                                        stdout)
                                    require("witch-line.core.handler").request_update_comp_graph(self)
                                end
                            end)
                            return
                        end
                        vim.schedule(function()
                            if api.nvim_buf_is_valid(bufnr) then
                                require("witch-line.core.handler").request_update_comp_graph(self)
                            end
                        end)
                    end)
                end
            end,
        })
    end,
    hidden = function(self, _)
        return vim.list_contains(self.static.disabled_filetypes, vim.bo.filetype)
    end,
    context = function(self)
        return { diff = self._diff_cache[vim.api.nvim_get_current_buf()] }
    end,
}

--- Determine if diff should be hidden based on filetype.
---@param self ManagedComponent
---@return boolean
local function diff_hidden(self, _)
    return vim.list_contains(self.static.disabled_filetypes, vim.bo.filetype)
end

--- @type DefaultComponent
Diff.Added = {
    id = "git.diff.added",
    _plug_provided = true,
    static = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "",
    },
    ref = {
        events = "git.diff.interface",
        context = "git.diff.interface",
    },
    style = { fg = colors.green },
    hidden = diff_hidden,
    update = function(self, session)
        local ctx = self:with_session(session).context(self, session)
        if ctx.diff then
            local added = ctx.diff.added
            if added then
                return self.static.icon .. " " .. added
            end
        end
        return ""
    end,
}

---@type DefaultComponent
Diff.Modified = {
    id = "git.diff.modified",
    _plug_provided = true,
    static = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "",
    },
    ref = {
        events = "git.diff.interface",
        context = "git.diff.interface",
    },
    style = { fg = colors.cyan },
    hidden = diff_hidden,
    update = function(self, session)
        local ctx = self:with_session(session).context(self, session)
        if ctx.diff then
            local modified = ctx.diff.modified
            if modified then
                return self.static.icon .. " " .. modified
            end
        end
        return ""
    end,
}

---@type DefaultComponent
Diff.Removed = {
    id = "git.diff.removed",
    _plug_provided = true,
    static = {
        disabled_filetypes = DISABLED_FILETYPES,
        icon = "-",
    },
    ref = {
        events = "git.diff.interface",
        context = "git.diff.interface",
    },
    style = { fg = colors.red },
    hidden = diff_hidden,
    update = function(self, session)
        local ctx = self:with_session(session).context(self, session)
        if ctx.diff then
            local removed = ctx.diff.removed
            if removed then
                return self.static.icon .. " " .. removed
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
