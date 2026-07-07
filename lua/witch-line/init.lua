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

--- Ensure defaults are applied to the user config table.
--- Fills in missing `statusline.global` with the built-in default.
---@param user_configs? UserConfig
---@return UserConfig
local resolve_user_config = function(user_configs)
    user_configs = type(user_configs) == "table" and user_configs or {}

    local statusline = user_configs.statusline
    statusline = type(statusline) == "table" and statusline or {}
    user_configs.statusline = statusline

    if type(statusline.global) ~= "table" then
        statusline.global = require("witch-line.config.default_layout")
    end

    return user_configs
end

---@class WitchLine
---@field user_config? UserConfig
local M = {}

--- Setup witch-line with the given user config.
---@param user_config? UserConfig
M.setup = function(user_config)
    user_config = resolve_user_config(user_config)
    M.user_config = user_config

    require("witch-line.engine.statusline").setup(user_config.disabled)
    require("witch-line.engine").setup(user_config.statusline)

    vim.api.nvim_create_autocmd("CmdlineEnter", {
        once = true,
        callback = function()
            require("witch-line.command")
        end,
    })
end

return M
