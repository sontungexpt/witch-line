local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@type Component
local FileName = {
	id = Id.FileName,
	_plug_provided = true,
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
				["NvimTree"] = "NvimTree",
				["TelescopePrompt"] = "Telescope",
				["mason"] = "Mason",
				["lazy"] = "Lazy",
				["checkhealth"] = "CheckHealth",
			},

			-- buftypes = { icon, color, filename(optional) },
			buftypes = {
				["terminal"] = "Terminal",
			},
		},
	},
	padding = { left = 1, right = 0 },
	update = function(self, context, static)
		local vim = vim
		local filename = vim.fn.expand("%:t")
		local extension = static.extensions
		local filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })
		local buftype = vim.api.nvim_get_option_value("buftype", { buf = 0 })
		filename = extension.filetypes[filetype] or filename
		filename = extension.buftypes[buftype] or filename

		if filename == "" then
			filename = "No File"
		end
		return filename
	end,
}

---@type Component
local Icon = {
	id = Id.FileIcon,
	_plug_provided = true,
	ref = {
		events = Id.FileName,
		user_events = Id.FileName,
	},
	static = {
		extensions = {
			-- filetypes = { icon, color, filename(optional) },
			filetypes = {
				["NvimTree"] = { "", colors.red },
				["TelescopePrompt"] = { "", colors.red },
				["mason"] = { "󰏔", colors.red },
				["lazy"] = { "󰏔", colors.red },
				["checkhealth"] = { "", colors.red },
				["plantuml"] = { "", colors.green },
				["dashboard"] = { "", colors.red },
			},

			-- buftypes = { icon, color, filename(optional) },
			buftypes = {
				["terminal"] = { "", colors.red },
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
				icon, color_icon = extension[1], extension[2]
			else
				local filetype = api.nvim_get_option_value("filetype", { buf = 0 })
				extension = extensions.filetypes[filetype]
				if extension then
					icon, color_icon = extension[1], extension[2]
				end
			end
		end

		return {
			icon = icon or "",
			color = color_icon or colors.white,
		}
	end,
	style = function(self, ctx, static)
		return {
			fg = ctx.color,
		}
	end,

	update = function(self, ctx, static)
		return ctx.icon
	end,
}

return {
	filename = FileName,
	icon = Icon,
}
