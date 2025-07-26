local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id")

---@type Component
local FileName = {
	id = Id.FileName,
	-- id = require("witch-line.components.id.enum").FileName,
	user_events = { "VeryLazy" },
	events = {
		"BufEnter",
		"BufLeave",
		"BufWinEnter",
		"WinEnter",
	},
	style = {
		fg = colors.orange,
	},
	static = {
		extensions = {
			-- filetypes = { icon, color, filename(optional) },
			filetypes = {
				["NvimTree"] = { "", colors.red, "NvimTree" },
				["TelescopePrompt"] = { "", colors.red, "Telescope" },
				["mason"] = { "󰏔", colors.red, "Mason" },
				["lazy"] = { "󰏔", colors.red, "Lazy" },
				["checkhealth"] = { "", colors.red, "CheckHealth" },
				["plantuml"] = { "", colors.green },
				["dashboard"] = { "", colors.red },
			},

			-- buftypes = { icon, color, filename(optional) },
			buftypes = {
				["terminal"] = { "", colors.red, "Terminal" },
			},
		},
	},
	context = function(self, static)
		local fn, api = vim.fn, vim.api
		local filename = fn.expand("%:t")

		local has_devicons, devicons = pcall(require, "nvim-web-devicons")
		local icon, color_icon = nil, nil
		if has_devicons then
			icon, color_icon = devicons.get_icon_color(filename, fn.expand("%:e"))
		end

		if not icon then
			local extensions = static.extensions
			local buftype = api.nvim_get_option_value("buftype", {
				buf = 0,
			})

			local extension = extensions.buftypes[buftype]
			if extension then
				icon, color_icon, filename =
					extension[1], extension[2], extension[3] or filename ~= "" and filename or buftype
			else
				local filetype = api.nvim_get_option_value("filetype", { buf = 0 })
				extension = extensions.filetypes[filetype]
				if extension then
					icon, color_icon, filename =
						extension[1], extension[2], extension[3] or filename ~= "" and filename or filetype
				end
			end
		end

		if filename == "" then
			filename = "No File"
		end
		return { icon, color_icon, filename }
	end,
	padding = { left = 1, right = 0 },
	update = function(self, context, static)
		return context[3]
	end,
}

---@type Component
local Icon = {
	id = Id.FileIcon,
	inherit = Id.FileName,
	style = function(self, ctx, static)
		return {
			fg = ctx[2],
		}
	end,

	update = function(self, ctx, static)
		return ctx[1]
	end,
}

return {
	filename = FileName,
	icon = Icon,
}
