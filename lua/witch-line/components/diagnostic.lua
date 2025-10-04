-- local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
local Interface = {
	id = Id["diagnostic.interface"],
	_plug_provided = true,
	events = { "DiagnosticChanged" },
	static = {
		ERROR = "",
		WARN = "",
		INFO = "",
		HINT = "",
	},
	hidden = function()
		local filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })
		return filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
	end,
}

--- @type DefaultComponent
local Error = {
	id = Id["diagnostic.error"],
	_plug_provided = true,
	style = {
		fg = "DiagnosticError",
	},
	inherit = Id["diagnostic.interface"],
	-- ref = {
	-- 	events = Id["diagnostic.interface"],
	-- 	static = Id["diagnostic.interface"],
	-- 	hide = Id["diagnostic.interface"],
	-- },
	update = function(self, ctx, static)
		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
		return count > 0 and static.ERROR .. " " .. count or ""
	end,
}

--- @type DefaultComponent
local Warn = {
	id = Id["diagnostic.warn"],
	_plug_provided = true,
	inherit = Id["diagnostic.interface"],
	style = {
		fg = "DiagnosticWarn",
	},
	-- ref = {
	-- 	events = Id["diagnostic.interface"],
	-- 	static = Id["diagnostic.interface"],
	-- 	hide = Id["diagnostic.interface"],
	-- },
	update = function(self, ctx, static)
		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
		return count > 0 and static.WARN .. " " .. count or ""
	end,
}

---@type DefaultComponent
local Info = {
	id = Id["diagnostic.info"],
	_plug_provided = true,
	inherit = Id["diagnostic.interface"],
	style = {
		fg = "DiagnosticInfo",
	},
	-- ref = {
	-- 	events = Id["diagnostic.interface"],
	-- 	static = Id["diagnostic.interface"],
	-- 	hide = Id["diagnostic.interface"],
	-- },
	update = function(self, ctx, static)
		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.INFO })
		return count > 0 and static.INFO .. " " .. count or ""
	end,
}

--- @type DefaultComponent
local Hint = {
	id = Id["diagnostic.hint"],
	_plug_provided = true,
	inherit = Id["diagnostic.interface"],
	style = {
		fg = "DiagnosticHint",
	},
	-- ref = {
	-- 	events = Id["diagnostic.interface"],
	-- 	static = Id["diagnostic.interface"],
	-- 	hide = Id["diagnostic.interface"],
	-- },
	update = function(self, ctx, static)
		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.HINT })
		return count > 0 and static.HINT .. " " .. count or ""
	end,
}

return {
	interface = Interface,
	error = Error,
	warn = Warn,
	info = Info,
	hint = Hint,
}
