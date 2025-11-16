local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local Position = {
	id = Id["cursor.pos"],
	_plug_provided = true,
	style = { fg = colors.fg },
	events = { "CursorMoved", "CursorMovedI" },
	update = function(self)
		local pos = vim.api.nvim_win_get_cursor(0)
		return pos[1] .. ":" .. pos[2]
	end,
}

---@type DefaultComponent
local Progress = {
	id = Id["cursor.progress"],
	_plug_provided = true,
	ref = {
		events = Id["cursor.pos"],
	},
	static = {
		chars = { "_", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" },
	},
	padding = 0,
	style = { fg = colors.orange },
	update = function(self)
		local api = vim.api
		local static = self.static

		---@cast static {chars: string[]}
		local cursor_line = api.nvim_win_get_cursor(0)[1]
		local total_lines = api.nvim_buf_line_count(0)

		return static.chars[math.ceil(cursor_line / total_lines * #static.chars)] or ""
	end,
}

return {
	pos = Position,
	progress = Progress,
}
