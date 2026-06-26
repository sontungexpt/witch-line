local DiagnosticSevrity = vim.diagnostic.severity

--- @type DefaultComponent
local Interface = {
	id = "diagnostic.interface",
	_plug_provided = true,
	events = "DiagnosticChanged",
	static = {
		icons = {
			[DiagnosticSevrity.ERROR] = "",
			[DiagnosticSevrity.WARN] = "",
			[DiagnosticSevrity.INFO] = "",
			[DiagnosticSevrity.HINT] = "",
		},
	},
	hidden = function(self, _)
		return vim.bo.filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
	end,
	update = function(self, ctx)
		local icon = {}
		local diagnostic = vim.diagnostic
		for id, value in pairs(self.static.icons) do
			icon[id] = value
		end
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
		ctx.state.count = diagnostic.count(0)
		ctx.state.icon = icon
		return ""
	end,
}

--- @type DefaultComponent
local Error = {
	id = "diagnostic.error",
	_plug_provided = true,
	style = { fg = "DiagnosticError" },
	ref = {
		events = "diagnostic.interface",
		hidden = "diagnostic.interface",
	},
	update = function(self, ctx)
		local id = vim.diagnostic.severity.ERROR
		local count = ctx.state.count[id] or 0
		return count > 0 and ctx.state.icon[id] .. " " .. count or ""
	end,
}

--- @type DefaultComponent
local Warn = {
	id = "diagnostic.warn",
	_plug_provided = true,
	ref = {
		events = "diagnostic.interface",
		hidden = "diagnostic.interface",
	},
	style = { fg = "DiagnosticWarn" },
	update = function(self, ctx)
		local id = vim.diagnostic.severity.WARN
		local count = ctx.state.count[id] or 0
		return count > 0 and ctx.state.icon[id] .. " " .. count or ""
	end,
}

---@type DefaultComponent
local Info = {
	id = "diagnostic.info",
	_plug_provided = true,
	ref = {
		events = "diagnostic.interface",
		hidden = "diagnostic.interface",
	},
	style = { fg = "DiagnosticInfo" },
	update = function(self, ctx)
		local id = vim.diagnostic.severity.INFO
		local count = ctx.state.count[id] or 0
		return count > 0 and ctx.state.icon[id] .. " " .. count or ""
	end,
}

--- @type DefaultComponent
local Hint = {
	id = "diagnostic.hint",
	_plug_provided = true,
	ref = {
		events = "diagnostic.interface",
		hidden = "diagnostic.interface",
	},
	style = { fg = "DiagnosticHint" },
	update = function(self, ctx)
		local id = vim.diagnostic.severity.HINT
		local count = ctx.state.count[id] or 0
		return count > 0 and ctx.state.icon[id] .. " " .. count or ""
	end,
}

return {
	interface = Interface,
	error = Error,
	warn = Warn,
	info = Info,
	hint = Hint,
}
