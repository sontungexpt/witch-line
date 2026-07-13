local colors = require("witch-line.constant.color")

---@type DefaultComponent
return {
    id = "wl.macro.recording",
    ___builtin = true,
    events = { "RecordingEnter", "RecordingLeave" },
    style = { fg = colors.orange, bold = true },
    hidden = function()
        return vim.fn.reg_recording() == ""
    end,
    update = function()
        return vim.fn.reg_recording()
    end,
}
