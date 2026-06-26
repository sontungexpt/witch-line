local require, type = require, type


--- @class UserConfig.Disabled
--- @field filetypes? string[]
--- @field buftypes? string[]
---
--- @class UserConfig.Statusline
--- @field global CombinedComponent
--- @field win? fun(winid: integer): CombinedComponent|nil

--- @class UserConfig : table
--- @field statusline? UserConfig.Statusline
--- @field disabled? UserConfig.Disabled
--- @field auto_theme? boolean

local use_default_config = function(user_configs)
    user_configs = type(user_configs) == "table" and user_configs or {}
    local statusline = user_configs.statusline
    statusline = type(statusline) == "table" and statusline or {}
    statusline.global =
        type(statusline.global) ~= "table"
        and require("witch-line.constant.default")
        or statusline.global
    user_configs.statusline = statusline
    return user_configs
end

local M = {
    user_config = nil
}

--- @param user_config? UserConfig
M.setup = function(user_config)
    user_config = use_default_config(user_config)
    M.user_config = user_config

    require("witch-line.core.statusline").setup(user_config.disabled)
    require("witch-line.core.handler").setup(user_config.statusline)

    vim.api.nvim_create_autocmd("CmdlineEnter", {
        once = true,
        callback = function()
            require("witch-line.command")
        end,
    })
end

return M
