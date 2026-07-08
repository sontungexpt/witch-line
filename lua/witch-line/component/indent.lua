local colors = require("witch-line.constant.color")

---@type DefaultComponent
return {
    id = "wl.indent",
    ___builtin = true,
    events = "InsertEnter",
    style = { fg = colors.cyan },
    update = function()
        return "Tab: " .. vim.bo.shiftwidth
    end,
}
