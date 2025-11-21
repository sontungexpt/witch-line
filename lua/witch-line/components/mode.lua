local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@enum Mode
---| NORMAL: 1
---| NTERMINAL: 2
---| VISUAL: 3
---| INSERT:  4
---| TERMINAL:  5
---| REPLACE:  6
---| SELECT:  7
---| COMMAND:  8
---| CONFIRM:  9

local NORMAL = 1
local NTERMINAL = 2
local VISUAL = 3
local INSERT = 4
local TERMINAL = 5
local REPLACE = 6
local SELECT = 7
local COMMAND = 8
local CONFIRM = 9

---@type DefaultComponent
return {
	id = Id["mode"],
	_plug_provided = true,
	events = "ModeChanged",
	flexible = 90,
	static = {
		modes = {
			["n"] = { "NORMAL", NORMAL },
			["no"] = { "NORMAL (no)", NORMAL },
			["nov"] = { "NORMAL (nov)", NORMAL },
			["noV"] = { "NORMAL (noV)", NORMAL },
			["noCTRL-V"] = { "NORMAL", NORMAL },
			["niI"] = { "NORMAL i", NORMAL },
			["niR"] = { "NORMAL r", NORMAL },
			["niV"] = { "NORMAL v", NORMAL },

			["nt"] = { "TERMINAL", NTERMINAL },
			["ntT"] = { "TERMINAL (ntT)", NTERMINAL },

			["v"] = { "VISUAL", VISUAL },
			["vs"] = { "V-CHAR (Ctrl O)", VISUAL },
			["V"] = { "V-LINE", VISUAL },
			["Vs"] = { "V-LINE", VISUAL },
			[""] = { "V-BLOCK", VISUAL },

			["i"] = { "INSERT", INSERT },
			["ic"] = { "INSERT (completion)", INSERT },
			["ix"] = { "INSERT completion", INSERT },

			["t"] = { "TERMINAL", TERMINAL },
			["!"] = { "SHELL", TERMINAL },

			["R"] = { "REPLACE", REPLACE },
			["Rc"] = { "REPLACE (Rc)", REPLACE },
			["Rx"] = { "REPLACE (Rx)", REPLACE },
			["Rv"] = { "V-REPLACE", REPLACE },
			["Rvc"] = { "V-REPLACE (Rvc)", REPLACE },
			["Rvx"] = { "V-REPLACE (Rvx)", REPLACE },

			["s"] = { "SELECT", SELECT },
			["S"] = { "S-LINE", SELECT },
			[""] = { "S-BLOCK", SELECT },

			["c"] = { "COMMAND", COMMAND },
			["cv"] = { "COMMAND", COMMAND },
			["ce"] = { "COMMAND", COMMAND },

			["r"] = { "PROMPT", CONFIRM },
			["rm"] = { "MORE", CONFIRM },
			["r?"] = { "CONFIRM", CONFIRM },
			["x"] = { "CONFIRM", CONFIRM },
		},

		--- @type table<Mode, CompStyle>
		mode_colors = {
			[NORMAL] = { fg = colors.blue },
			[INSERT] = { fg = colors.green },
			[VISUAL] = { fg = colors.purple },
			[NTERMINAL] = { fg = colors.gray },
			[TERMINAL] = { fg = colors.cyan },
			[REPLACE] = { fg = colors.red },
			[SELECT] = { fg = colors.magenta },
			[COMMAND] = { fg = colors.yellow },
			[CONFIRM] = { fg = colors.yellow },
		},
	},
	update = function(self, sid)
		local static = self.static
		--- @cast static {mode_colors: table<string, CompStyle>, modes: table<string, { [1]: string, [2]: Mode}>}
		local mode_code = vim.api.nvim_get_mode().mode
		local mode_config = static.modes[mode_code]
		if not mode_config then
			return mode_code
		end
		return mode_config[1], static.mode_colors[mode_config[2]]
	end,
}
