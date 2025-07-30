local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local CursorPos = {
	id = Id["cursor.pos"],
	_plug_provided = true,
	style = { fg = colors.fg },
	events = { "CursorMoved", "CursorMovedI" },
	update = function(self, ctx, static)
		local pos = vim.api.nvim_win_get_cursor(0)
		return pos[1] .. ":" .. pos[2]
	end,
}

---@type DefaultComponent
local CursorProgress = {
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
	update = function(self, ctx, static)
		local line = vim.fn.line
		return static.chars[math.ceil(line(".") / line("$") * #static.chars)] or ""
	end,
}

return {
	pos = CursorPos,
	progress = CursorProgress,
}
