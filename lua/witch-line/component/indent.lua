local colors = require("witch-line.config.color")

---@type DefaultComponent
return {
    id = "wl.indent",
    ___builtin = true,
    events = { "BufEnter", "WinEnter" },
    style = { fg = colors.cyan },
    update = function()
        return "Tab: " .. vim.bo.shiftwidth
    end,
}
