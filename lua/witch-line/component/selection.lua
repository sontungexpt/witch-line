local colors = require("witch-line.constant.color")
local nvim_get_mode = vim.api.nvim_get_mode
local fn_line = vim.fn.line
local fn_col = vim.fn.col

--- @type DefaultComponent
local SelectionCount = {
    id = "wl.selection.count",
    ___builtin = true,
    style = { fg = colors.cyan },
    events = { "ModeChanged", "CursorMoved" },
    update = function(self, _)
        local mode = nvim_get_mode().mode

        if mode == "V" then
            local num = math.abs(fn_line(".") - fn_line("v")) + 1
            return "Sel: " .. num .. (num > 1 and " lines" or " line")
        end

        if mode == "v" then
            local ls, le = fn_line("v"), fn_line(".")
            if ls ~= le then
                local num = math.abs(le - ls) + 1
                return "Sel: " .. num .. (num > 1 and " lines" or " line")
            end
            local num = math.abs(fn_col(".") - fn_col("v")) + 1
            return "Sel: " .. num .. (num > 1 and " cols" or " col")
        end

        if mode == "" then
            local rows = math.abs(fn_line(".") - fn_line("v")) + 1
            local cols = math.abs(fn_col(".") - fn_col("v")) + 1
            return "Sel: " .. rows .. "x" .. cols
        end

        return ""
    end,
}

return {
    count = SelectionCount,
}
