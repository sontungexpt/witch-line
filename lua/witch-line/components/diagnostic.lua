-- local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

--- @type Component
local Error = {
	id = Id["diagnostic.error"],
	_plug_provided = true,
	-- style = {
	-- 	fg = "DiagnosticError",
	-- },
	events = { "DiagnosticChanged" },
	static = {
		ERROR = "",
		WARN = "",
		INFO = "",
		HINT = "",
	},
	hidden = function()
		return vim.api.nvim_buf_get_option(0, "filetype") ~= "lazy" and not api.nvim_buf_get_name(0):match("%.env$")
	end,
	update = function(self, ctx, static)
		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
		---@diagnostic disable-next-line: need-check-nil
		return count > 0 and static.ERROR .. " " .. count or ""
	end,
}

local Warn = {
	style = {
		fg = "DiagnosticWarn",
	},
	static = "WitchLineDiagnosticsError",
	update = function(self, ctx, static)
		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
		---@diagnostic disable-next-line: need-check-nil
		return count > 0 and static.WARN .. " " .. count or ""
	end,
}

local Info = {
	styles = {
		fg = "DiagnosticInfo",
	},
	update = function(self, ctx, static)
		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.INFO })
		---@diagnostic disable-next-line: need-check-nil
		return count > 0 and static.INFO .. " " .. count or ""
	end,
}

return {
	error = Error,
	warn = Warn,
	info = Info,
}
