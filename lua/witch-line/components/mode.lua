local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
return {
	id = Id["mode"],
	_plug_provided = true,
	user_events = { "VeryLazy" },
	events = { "VimResized", "ModeChanged" },
	static = {
		modes = {
			["n"] = { "NORMAL", "STTUSLINE_NORMAL_MODE" },
			["no"] = { "NORMAL (no)", "STTUSLINE_NORMAL_MODE" },
			["nov"] = { "NORMAL (nov)", "STTUSLINE_NORMAL_MODE" },
			["noV"] = { "NORMAL (noV)", "STTUSLINE_NORMAL_MODE" },
			["noCTRL-V"] = { "NORMAL", "STTUSLINE_NORMAL_MODE" },
			["niI"] = { "NORMAL i", "STTUSLINE_NORMAL_MODE" },
			["niR"] = { "NORMAL r", "STTUSLINE_NORMAL_MODE" },
			["niV"] = { "NORMAL v", "STTUSLINE_NORMAL_MODE" },

			["nt"] = { "TERMINAL", "STTUSLINE_NTERMINAL_MODE" },
			["ntT"] = { "TERMINAL (ntT)", "STTUSLINE_NTERMINAL_MODE" },

			["v"] = { "VISUAL", "STTUSLINE_VISUAL_MODE" },
			["vs"] = { "V-CHAR (Ctrl O)", "STTUSLINE_VISUAL_MODE" },
			["V"] = { "V-LINE", "STTUSLINE_VISUAL_MODE" },
			["Vs"] = { "V-LINE", "STTUSLINE_VISUAL_MODE" },
			[""] = { "V-BLOCK", "STTUSLINE_VISUAL_MODE" },

			["i"] = { "INSERT", "STTUSLINE_INSERT_MODE" },
			["ic"] = { "INSERT (completion)", "STTUSLINE_INSERT_MODE" },
			["ix"] = { "INSERT completion", "STTUSLINE_INSERT_MODE" },

			["t"] = { "TERMINAL", "STTUSLINE_TERMINAL_MODE" },
			["!"] = { "SHELL", "STTUSLINE_TERMINAL_MODE" },

			["R"] = { "REPLACE", "STTUSLINE_REPLACE_MODE" },
			["Rc"] = { "REPLACE (Rc)", "STTUSLINE_REPLACE_MODE" },
			["Rx"] = { "REPLACEa (Rx)", "STTUSLINE_REPLACE_MODE" },
			["Rv"] = { "V-REPLACE", "STTUSLINE_REPLACE_MODE" },
			["Rvc"] = { "V-REPLACE (Rvc)", "STTUSLINE_REPLACE_MODE" },
			["Rvx"] = { "V-REPLACE (Rvx)", "STTUSLINE_REPLACE_MODE" },

			["s"] = { "SELECT", "STTUSLINE_SELECT_MODE" },
			["S"] = { "S-LINE", "STTUSLINE_SELECT_MODE" },
			[""] = { "S-BLOCK", "STTUSLINE_SELECT_MODE" },

			["c"] = { "COMMAND", "STTUSLINE_COMMAND_MODE" },
			["cv"] = { "COMMAND", "STTUSLINE_COMMAND_MODE" },
			["ce"] = { "COMMAND", "STTUSLINE_COMMAND_MODE" },

			["r"] = { "PROMPT", "STTUSLINE_CONFIRM_MODE" },
			["rm"] = { "MORE", "STTUSLINE_CONFIRM_MODE" },
			["r?"] = { "CONFIRM", "STTUSLINE_CONFIRM_MODE" },
			["x"] = { "CONFIRM", "STTUSLINE_CONFIRM_MODE" },
		},
		mode_colors = {
			["STTUSLINE_NORMAL_MODE"] = { fg = colors.blue },
			["STTUSLINE_INSERT_MODE"] = { fg = colors.green },
			["STTUSLINE_VISUAL_MODE"] = { fg = colors.purple },
			["STTUSLINE_NTERMINAL_MODE"] = { fg = colors.gray },
			["STTUSLINE_TERMINAL_MODE"] = { fg = colors.cyan },
			["STTUSLINE_REPLACE_MODE"] = { fg = colors.red },
			["STTUSLINE_SELECT_MODE"] = { fg = colors.magenta },
			["STTUSLINE_COMMAND_MODE"] = { fg = colors.yellow },
			["STTUSLINE_CONFIRM_MODE"] = { fg = colors.yellow },
		},
		auto_hide_on_vim_resized = true,
	},
	context = function(self, static)
		return vim.api.nvim_get_mode().mode
	end,
	style = function(self, ctx, static)
		local mode_code = ctx
		---@diagnostic disable-next-line: need-check-nil
		return static.mode_colors[static.modes[mode_code][2]] or {}
	end,
	update = function(self, ctx, static)
		local mode_code = ctx
		local static = self.static
		---@diagnostic disable-next-line: need-check-nil
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
