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
	hidden = function(self, session_id)
		return vim.bo.filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
	end,
	context = function(self)
		return vim.diagnostic.count(0)
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
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx, static = hook.use_context(self, session_id), hook.use_static(self)
		local count = ctx[vim.diagnostic.severity.ERROR] or 0
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
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx, static = hook.use_context(self, session_id), hook.use_static(self)
		local count = ctx[vim.diagnostic.severity.WARN] or 0
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
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx, static = hook.use_context(self, session_id), hook.use_static(self)
		local count = ctx[vim.diagnostic.severity.INFO] or 0
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
	update = function(self, session_id)
		local hook = require("witch-line.core.manager.hook")
		local ctx, static = hook.use_context(self, session_id), hook.use_static(self)
		local count = ctx[vim.diagnostic.severity.HINT] or 0
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
