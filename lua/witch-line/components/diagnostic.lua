local Id = require("witch-line.constant.id").Id
local DiagnosticSevrity = vim.diagnostic.severity

--- @type DefaultComponent
local Interface = {
	id = Id["diagnostic.interface"],
	_plug_provided = true,
	auto_theme = true,
	events = "DiagnosticChanged",
	static = {
		[DiagnosticSevrity.ERROR] = "",
		[DiagnosticSevrity.WARN] = "",
		[DiagnosticSevrity.INFO] = "",
		[DiagnosticSevrity.HINT] = "",
	},
	hidden = function(self, sid)
		return vim.bo.filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
	end,
	context = function(self)
		local icon = require("witch-line.core.manager.hook").use_static(self)
		local diagnostic = vim.diagnostic
		--- @cast icon table<integer, string>
		local signs = diagnostic.config().signs
		if type(signs) == "table" then
			local text = signs.text
			if type(text) == "table" then
				local severity = diagnostic.severity
				for id, value in pairs(icon) do
					icon[id] = text[id] or text[severity[id]] or value
				end
			end
		end
		return {
			count = vim.diagnostic.count(0),
			icon = icon,
		}
	end,
}

--- @type DefaultComponent
local Error = {
	id = Id["diagnostic.error"],
	_plug_provided = true,
	style = {
		fg = "DiagnosticError",
	},
	ref = {
		events = Id["diagnostic.interface"],
		context = Id["diagnostic.interface"],
		hidden = Id["diagnostic.interface"],
	},
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx = hook.use_context(self, session_id)
		--- @cast ctx {count: table, icon: table}
		local id = vim.diagnostic.severity.ERROR
		local count = ctx.count[id] or 0
		return count > 0 and ctx.icon[id] .. " " .. count or ""
	end,
}

--- @type DefaultComponent
local Warn = {
	id = Id["diagnostic.warn"],
	_plug_provided = true,
	ref = {
		events = Id["diagnostic.interface"],
		context = Id["diagnostic.interface"],
		hidden = Id["diagnostic.interface"],
	},
	style = {
		fg = "DiagnosticWarn",
	},
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx = hook.use_context(self, session_id)
		--- @cast ctx {count: table, icon: table}
		local id = vim.diagnostic.severity.WARN
		local count = ctx.count[id] or 0
		return count > 0 and ctx.icon[id] .. " " .. count or ""
	end,
}

---@type DefaultComponent
local Info = {
	id = Id["diagnostic.info"],
	_plug_provided = true,
	ref = {
		events = Id["diagnostic.interface"],
		context = Id["diagnostic.interface"],
		hidden = Id["diagnostic.interface"],
	},
	style = {
		fg = "DiagnosticInfo",
	},
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx = hook.use_context(self, session_id)
		--- @cast ctx {count: table, icon: table}
		local id = vim.diagnostic.severity.INFO
		local count = ctx.count[id] or 0
		return count > 0 and ctx.icon[id] .. " " .. count or ""
	end,
}

--- @type DefaultComponent
local Hint = {
	id = Id["diagnostic.hint"],
	_plug_provided = true,
	ref = {
		events = Id["diagnostic.interface"],
		context = Id["diagnostic.interface"],
		hidden = Id["diagnostic.interface"],
	},
	style = {
		fg = "DiagnosticHint",
	},
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx = hook.use_context(self, session_id)
		--- @cast ctx {count: table, icon: table}
		local id = vim.diagnostic.severity.HINT
		local count = ctx.count[id] or 0
		return count > 0 and ctx.icon[id] .. " " .. count or ""
	end,
}

return {
	interface = Interface,
	error = Error,
	warn = Warn,
	info = Info,
	hint = Hint,
}
