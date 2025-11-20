local Id = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")

--- @type DefaultComponent
local SelectionCount = {
	id = Id["selection.count"],
	auto_theme = true,
	_plug_provided = true,
	style = {
		fg = colors.cyan,
	},
	events = { "ModeChanged", "CursorMoved" },
	update = function(self, session_id)
		local mode = vim.api.nvim_get_mode().mode
		local line_start, col_start = vim.fn.line("v"), vim.fn.col("v")
		local line_end, col_end = vim.fn.line("."), vim.fn.col(".")
		if mode == "" then
			return string.format("Sel: %dx%d", math.abs(line_start - line_end) + 1, math.abs(col_start - col_end) + 1)
		elseif mode == "V" or line_start ~= line_end then
			local num = math.abs(line_start - line_end) + 1
			return "Sel: " .. num .. (num > 1 and " lines" or " line")
		elseif mode == "v" then
			local num = math.abs(col_start - col_end) + 1
			return "Sel: " .. num .. (num > 1 and " cols" or " col")
		else
			return ""
		end
	end,
}

return {
	count = SelectionCount,
}
