local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@enum Mode
local Mode = {
	NORMAL = 1,
	NTERMINAL = 2,
	VISUAL = 3,
	INSERT = 4,
	TERMINAL = 5,
	REPLACE = 6,
	SELECT = 7,
	COMMAND = 8,
	CONFIRM = 9,
}

---@type DefaultComponent
return {
	id = Id["mode"],
	auto_theme = true,
	_plug_provided = true,
	events = { "VimResized", "ModeChanged" },
	static = {
		modes = {
			["n"] = { "NORMAL", Mode.NORMAL },
			["no"] = { "NORMAL (no)", Mode.NORMAL },
			["nov"] = { "NORMAL (nov)", Mode.NORMAL },
			["noV"] = { "NORMAL (noV)", Mode.NORMAL },
			["noCTRL-V"] = { "NORMAL", Mode.NORMAL },
			["niI"] = { "NORMAL i", Mode.NORMAL },
			["niR"] = { "NORMAL r", Mode.NORMAL },
			["niV"] = { "NORMAL v", Mode.NORMAL },

			["nt"] = { "TERMINAL", Mode.NTERMINAL },
			["ntT"] = { "TERMINAL (ntT)", Mode.NTERMINAL },

			["v"] = { "VISUAL", Mode.VISUAL },
			["vs"] = { "V-CHAR (Ctrl O)", Mode.VISUAL },
			["V"] = { "V-LINE", Mode.VISUAL },
			["Vs"] = { "V-LINE", Mode.VISUAL },
			[""] = { "V-BLOCK", Mode.VISUAL },

			["i"] = { "INSERT", Mode.INSERT },
			["ic"] = { "INSERT (completion)", Mode.INSERT },
			["ix"] = { "INSERT completion", Mode.INSERT },

			["t"] = { "TERMINAL", Mode.TERMINAL },
			["!"] = { "SHELL", Mode.TERMINAL },

			["R"] = { "REPLACE", Mode.REPLACE },
			["Rc"] = { "REPLACE (Rc)", Mode.REPLACE },
			["Rx"] = { "REPLACE (Rx)", Mode.REPLACE },
			["Rv"] = { "V-REPLACE", Mode.REPLACE },
			["Rvc"] = { "V-REPLACE (Rvc)", Mode.REPLACE },
			["Rvx"] = { "V-REPLACE (Rvx)", Mode.REPLACE },

			["s"] = { "SELECT", Mode.SELECT },
			["S"] = { "S-LINE", Mode.SELECT },
			[""] = { "S-BLOCK", Mode.SELECT },

			["c"] = { "COMMAND", Mode.COMMAND },
			["cv"] = { "COMMAND", Mode.COMMAND },
			["ce"] = { "COMMAND", Mode.COMMAND },

			["r"] = { "PROMPT", Mode.CONFIRM },
			["rm"] = { "MORE", Mode.CONFIRM },
			["r?"] = { "CONFIRM", Mode.CONFIRM },
			["x"] = { "CONFIRM", Mode.CONFIRM },
		},

		mode_colors = {
			[Mode.NORMAL] = { fg = colors.blue },
			[Mode.INSERT] = { fg = colors.green },
			[Mode.VISUAL] = { fg = colors.purple },
			[Mode.NTERMINAL] = { fg = colors.gray },
			[Mode.TERMINAL] = { fg = colors.cyan },
			[Mode.REPLACE] = { fg = colors.red },
			[Mode.SELECT] = { fg = colors.magenta },
			[Mode.COMMAND] = { fg = colors.yellow },
			[Mode.CONFIRM] = { fg = colors.yellow },
		},
		auto_hide_on_vim_resized = true,
	},
	context = function(self)
		return {
			mode = vim.api.nvim_get_mode().mode,
		}
	end,
	style = function(self, session_id)
		local static = self.static
		--- @cast static {mode_colors: table<string, {fg: string}>, modes: table<string, { [1]: string, [2]: string}>}
		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)
		--- @cast ctx {mode: string}
		local mode_code = ctx.mode
		return static.mode_colors[static.modes[mode_code][2]] or {}
	end,
	update = function(self, session_id)
		local static = self.static
		--- @cast static {modes: table<string, { [1]: string, [2]: string}>}
		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)
		--- @cast ctx {mode: string}
		local mode_code = ctx.mode
		local mode = static.modes[mode_code]
		return mode and mode[1] or mode_code
	end,
	hidden = function(self)
		if self.static.auto_hide_on_vim_resized then
			vim.opt.showmode = not (vim.o.columns > 70)
			return vim.opt.showmode
		end
		return false
	end,
}
