local Id = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")

---@type DefaultComponent
return {
    events = { "BufEnter", "WinEnter" },
    _plug_provided = true,
    id = Id["indent"],
    style = { fg = colors.cyan },
    update = function()
        return "Tab: " .. vim.bo.shiftwidth
    end,
}
