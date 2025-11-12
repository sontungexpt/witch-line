local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
local Interface = {
	id = Id["diagnostic.interface"],
	_plug_provided = true,
	events = "DiagnosticChanged",
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

		local id = vim.diagnostic.severity.ERROR
		local signs = vim.diagnostic.config().signs
		local icon
		if type(signs) == "table" then
			local text = signs.text
			if type(text) == "table" then
				icon = text[id]
			end
		end
		if not icon or icon == "" then
			icon = hook.use_static(self).ERROR
		end
		local count = hook.use_context(self, session_id)[id] or 0
		return count > 0 and icon .. " " .. count or ""
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
		local id = vim.diagnostic.severity.WARN
		local signs = vim.diagnostic.config().signs
		local icon
		if type(signs) == "table" then
			local text = signs.text
			if type(text) == "table" then
				icon = text[id]
			end
		end
		if not icon or icon == "" then
			icon = hook.use_static(self).ERROR
		end
		local count = hook.use_context(self, session_id)[id] or 0
		return count > 0 and icon .. " " .. count or ""
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
		local id = vim.diagnostic.severity.INFO
		local signs = vim.diagnostic.config().signs
		local icon
		if type(signs) == "table" then
			local text = signs.text
			if type(text) == "table" then
				icon = text[id]
			end
		end
		if not icon or icon == "" then
			icon = hook.use_static(self).INFO
		end
		local count = hook.use_context(self, session_id)[id] or 0
		return count > 0 and icon .. " " .. count or ""
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
		local id = vim.diagnostic.severity.HINT
		local signs = vim.diagnostic.config().signs
		local icon
		if type(signs) == "table" then
			local text = signs.text
			if type(text) == "table" then
				icon = text[id]
			end
		end
		if not icon or icon == "" then
			icon = hook.use_static(self).HINT
		end
		local count = hook.use_context(self, session_id)[id] or 0
		return count > 0 and icon .. " " .. count or ""
	end,
}

return {
	interface = Interface,
	error = Error,
	warn = Warn,
	info = Info,
	hint = Hint,
}
