local colors = require("witch-line.constant.color")

---@type DefaultComponent
return {
    id = "wl.spell",
    ___builtin = true,
    events = "OptionSet spell",
    style = { fg = colors.orange, bold = true },
    hidden = function()
        return not vim.wo.spell
    end,
    update = function()
        return "SPELL"
    end,
}
