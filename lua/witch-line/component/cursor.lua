local api = vim.api
local colors = require("witch-line.config.color")

---@type DefaultComponent
local Position = {
    id = "wl.cursor.pos",
    ___builtin = true,
    style = { fg = colors.fg },
    events = { "CursorMoved", "CursorMovedI" },
    update = function(self)
        local pos = vim.api.nvim_win_get_cursor(0)
        return pos[1] .. ":" .. pos[2]
    end,
}


---@type DefaultComponent
local Progress = {
    id = "wl.cursor.progress",
    ___builtin = true,
    events = { "CursorMoved", "CursorMovedI" },
    config = {
        chars = { "_", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" },
    },
    padding = 0,
    style = { fg = colors.orange },
    update = function(self)
        local cfg = self.config
        local cursor_line = api.nvim_win_get_cursor(0)[1]
        local total_lines = api.nvim_buf_line_count(0)

        return cfg.chars[math.ceil(cursor_line / total_lines * #cfg.chars)] or ""
    end,
}

return {
    pos = Position,
    progress = Progress,
}
