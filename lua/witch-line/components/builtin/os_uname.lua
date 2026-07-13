local colors = require("witch-line.constant.color")
local uv = vim.uv or vim.loop

--- @type DefaultComponent
return {
    id = "wl.os_uname",
    ___builtin = true,
    events = "UIEnter",
    config = {
        icon = {
            mac = "",
            arch = "",
            linux = "",
            windows = "",
        },
        colors = {
            mac = colors.white,
            arch = colors.blue,
            linux = colors.yellow,
            windows = colors.blue,
        },
    },
    update = function(self, _)
        local u = uv.os_uname()
        local sysname = u.sysname
        local ico = self.config.icon
        local col = self.config.colors

        if sysname == "Darwin" then
            return ico.mac, { fg = col.mac }
        end

        if sysname == "Linux" then
            if u.release:match("[Aa][Rr][Cc][Hh]") then
                return ico.arch, { fg = col.arch }
            end
            return ico.linux, { fg = col.linux }
        end

        if sysname == "Windows_NT" then
            return ico.windows, { fg = col.windows }
        end

        return "󱚟 " .. (sysname or "Unknown OS"), { fg = "#ffffff" }
    end,
}
