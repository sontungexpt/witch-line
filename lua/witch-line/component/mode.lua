local colors = require("witch-line.config.color")

---@type DefaultComponent
return {
    id = "wl.mode",
    ___plug_provided = true,
    events = "ModeChanged",
    flexible = 90,
    static = {
        colors = {
            [1] = { fg = colors.blue },
            [2] = { fg = colors.gray },
            [3] = { fg = colors.purple },
            [4] = { fg = colors.green },
            [5] = { fg = colors.cyan },
            [6] = { fg = colors.red },
            [7] = { fg = colors.magenta },
            [8] = { fg = colors.yellow },
            [9] = { fg = colors.yellow },
        },
        modes = {
            ["n"] = { "NORMAL", 1 },
            ["no"] = { "NORMAL (no)", 1 },
            ["nov"] = { "NORMAL (nov)", 1 },
            ["noV"] = { "NORMAL (noV)", 1 },
            ["noCTRL-V"] = { "NORMAL", 1 },
            ["niI"] = { "NORMAL i", 1 },
            ["niR"] = { "NORMAL r", 1 },
            ["niV"] = { "NORMAL v", 1 },
            ["nt"] = { "TERMINAL", 2 },
            ["ntT"] = { "TERMINAL (ntT)", 2 },
            ["v"] = { "VISUAL", 3 },
            ["vs"] = { "V-CHAR (Ctrl O)", 3 },
            ["V"] = { "V-LINE", 3 },
            ["Vs"] = { "V-LINE", 3 },
            [""] = { "V-BLOCK", 3 },
            ["i"] = { "INSERT", 4 },
            ["ic"] = { "INSERT (completion)", 4 },
            ["ix"] = { "INSERT completion", 4 },
            ["t"] = { "TERMINAL", 5 },
            ["!"] = { "SHELL", 5 },
            ["R"] = { "REPLACE", 6 },
            ["Rc"] = { "REPLACE (Rc)", 6 },
            ["Rx"] = { "REPLACE (Rx)", 6 },
            ["Rv"] = { "V-REPLACE", 6 },
            ["Rvc"] = { "V-REPLACE (Rvc)", 6 },
            ["Rvx"] = { "V-REPLACE (Rvx)", 6 },
            ["s"] = { "SELECT", 7 },
            ["S"] = { "S-LINE", 7 },
            [""] = { "S-BLOCK", 7 },
            ["c"] = { "COMMAND", 8 },
            ["cv"] = { "COMMAND", 8 },
            ["ce"] = { "COMMAND", 8 },
            ["r"] = { "PROMPT", 9 },
            ["rm"] = { "MORE", 9 },
            ["r?"] = { "CONFIRM", 9 },
            ["x"] = { "CONFIRM", 9 },
        },
    },
    update = function(self, _)
        local mode_code = vim.api.nvim_get_mode().mode
        local mode_config = self.static.modes[mode_code]
        if not mode_config then
            return mode_code
        end
        return mode_config[1], self.static.colors[mode_config[2]]
    end,
}
