local colors = require("witch-line.config.color")

---@type DefaultComponent
local Encoding = {
    id = "wl.encoding",
    events = "InsertEnter",
    ___builtin = true,
    style = { fg = colors.yellow },
    update = function(self, _)
        local enc = vim.bo.fenc ~= "" and vim.bo.fenc or vim.o.enc
        return enc and enc:upper() or ""
    end,
}
return Encoding
