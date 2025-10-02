local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
local Interface = {
	id = Id["file.interface"],
	_plug_provided = true,
	user_events = { "VeryLazy" },
	events = {
		"BufEnter",
		"BufLeave",
		"BufWinEnter",
		"WinEnter",
	},
}

---@type DefaultComponent
local Name = {
	id = Id["file.name"],
	_plug_provided = true,
	ref = {
		events = Id["file.interface"],
		user_events = Id["file.interface"],
	},
	style = {
		bg = colors.orange,
	},
	static = {
		formatter = {
			filetype = {
				["NvimTree"] = "NvimTree",
				["TelescopePrompt"] = "Telescope",
				["mason"] = "Mason",
				["lazy"] = "Lazy",
				["checkhealth"] = "CheckHealth",
			},

			buftype = {
				["terminal"] = "Terminal",
			},
		},
	},
	padding = { left = 1, right = 0 },
	update = function(self, context, static)
		local api = vim.api
		local formatter = static.formatter

		local filename = formatter.filetype[api.nvim_get_option_value("filetype", { buf = 0 })]
		if filename then
			return filename
		end
		filename = formatter.buftype[api.nvim_get_option_value("buftype", { buf = 0 })]
		if filename then
			return filename
		end

		filename = vim.fs.basename(vim.api.nvim_buf_get_name(0))
		return filename ~= "" and filename or "No File"
	end,
}

---@type DefaultComponent
local Icon = {
	id = Id["file.icon"],
	_plug_provided = true,
	ref = {
		events = Id["file.interface"],
		user_events = Id["file.interface"],
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

			buftypes = {
				["terminal"] = { "", colors.red },
			},
		},
	},
	context = function(self, static)
		local fn, api = vim.fn, vim.api
		local filename = fn.expand("%:t")
		-- local filename = vim.fs.basename(vim.api.nvim_buf_get_name(0))

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
			color = color_icon or "#ffffff",
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

--- @type DefaultComponent
local Modifier = {
	id = Id["file.modifier"],
	_plug_provided = true,
	ref = {
		events = Id["file.interface"],
		user_events = Id["file.interface"],
	},
	style = {
		bg = colors.orange,
		fg = colors.black,
	},
	update = function(self, ctx, static)
		local api = vim.api
		local buftype = api.nvim_get_option_value("buftype", { buf = 0 })
		if buftype == "prompt" then
			return ""
		end
		if not api.nvim_buf_get_option(0, "modifiable") or api.nvim_buf_get_option(0, "readonly") then
			return ""
		elseif api.nvim_buf_get_option(0, "modified") then
			return ""
		end
		return ""
	end,
}

return {
	interface = Interface,
	name = Name,
	icon = Icon,
	modifier = Modifier,
}
