local Id = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")

---@type DefaultComponent
local Branch = {
    id = Id["git.branch"],
    _plug_provided = true,
    events = { "BufEnter", "WinEnter",  },
    user_events = {"GitSignsUpdate"},
    static = {
        icon = "",
    },
    style = { fg = colors.green },
    update = function(self, ctx, static)
        local branch = ""
        local git_dir = vim.fn.finddir(".git", ".;")
        if git_dir ~= "" then
            local head_file = io.open(git_dir .. "/HEAD", "r")
            if head_file then
                local content = head_file:read("*all")
                head_file:close()
                -- branch name  or commit hash
                branch = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
            end
        end
        return branch ~= "" and static.icon .. " " .. branch or ""
    end,
}

return {
    branch = Branch,
}
