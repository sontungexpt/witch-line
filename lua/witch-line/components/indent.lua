local Id = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.colors")

---@type DefaultComponent
return {
    events = { "BufEnter", "WinEnter" },
    _plug_provided = true,
    id = Id["indent"],
    style = { fg = colors.cyan },
    update = function()
        return "Tab: " .. vim.api.nvim_buf_get_option(0, "shiftwidth")
    end,
}
