local colors = require("witch-line.config.color")

---@type DefaultComponent
return {
    id = "wl.mode",
    ___builtin = true,
    events = "ModeChanged",
    flexible = 90,
    static = {
        colors = {
            [1] = { fg = colors.blue },    -- NORMAL
            [2] = { fg = colors.gray },    -- O-PENDING
            [3] = { fg = colors.purple },  -- VISUAL
            [4] = { fg = colors.green },   -- INSERT
            [5] = { fg = colors.red },     -- REPLACE
            [6] = { fg = colors.magenta }, -- SELECT / MORE / CONFIRM
            [7] = { fg = colors.yellow },  -- COMMAND / EX / SHELL / PROMPT
        },
        modes = {
            ["n"]     = { "NORMAL", 1 },
            ["niI"]   = { "NORMAL", 1 },
            ["niR"]   = { "NORMAL", 1 },
            ["niV"]   = { "NORMAL", 1 },
            ["nt"]    = { "NORMAL", 1 },
            ["ntT"]   = { "NORMAL", 1 },
            ["t"]     = { "TERMINAL", 1 },

            ["no"]    = { "O-PENDING", 2 },
            ["no\22"] = { "O-PENDING", 2 },
            ["nov"]   = { "O-PENDING", 2 },
            ["noV"]   = { "O-PENDING", 2 },

            ["v"]     = { "VISUAL", 3 },
            ["vs"]    = { "VISUAL", 3 },
            ["V"]     = { "V-LINE", 3 },
            ["Vs"]    = { "V-LINE", 3 },
            ["\22"]   = { "V-BLOCK", 3 },
            ["\22s"]  = { "V-BLOCK", 3 },

            ["i"]     = { "INSERT", 4 },
            ["ic"]    = { "INSERT", 4 },
            ["ix"]    = { "INSERT", 4 },

            ["R"]     = { "REPLACE", 5 },
            ["Rc"]    = { "REPLACE", 5 },
            ["Rx"]    = { "REPLACE", 5 },
            ["Rv"]    = { "V-REPLACE", 5 },
            ["Rvc"]   = { "V-REPLACE", 5 },
            ["Rvx"]   = { "V-REPLACE", 5 },

            ["s"]     = { "SELECT", 6 },
            ["S"]     = { "S-LINE", 6 },
            ["\19"]   = { "S-BLOCK", 6 },

            ["c"]     = { "COMMAND", 7 },
            ["cr"]    = { "COMMAND", 7 },
            ["cv"]    = { "EX", 7 },
            ["ce"]    = { "EX", 7 },
            ["cvr"]   = { "EX", 7 },
            ["!"]     = { "SHELL", 7 },
            ["r"]     = { "PROMPT", 7 },
            ["rm"]    = { "MORE", 7 },
            ["r?"]    = { "CONFIRM", 7 },
        },
    },
    update = function(self, _)
        local mode_code = vim.api.nvim_get_mode().mode

        local mode_config = self.static.modes[mode_code]
        if not mode_config then
            return mode_code, nil
        end

        local color = mode_config[2]
        if type(color) == "number" then
            color = self.static.colors[color]
        end

        return mode_config[1], color
    end,
}
