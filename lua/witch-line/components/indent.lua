local colors = require("witch-line.constant.color")

---@type DefaultComponent
return {
    id = "indent",
    _plug_provided = true,
    events = { "BufEnter", "WinEnter" },
    style = { fg = colors.cyan },
    update = function()
        return "Tab: " .. vim.bo.shiftwidth
    end,
}
