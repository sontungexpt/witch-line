local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
local Interface = {
	id = Id["file.interface"],
	_plug_provided = true,
  user_events = { "VeryLazy" },
	events = { "BufEnter", "WinEnter" },
}

---@type DefaultComponent
local Name = {
	id = Id["file.name"],
	_plug_provided = true,
	ref = {
    user_events = Id["file.interface"],
		events = Id["file.interface"],
	},
	style = {
		fg = colors.orange,
	},
	static = {
		formatter = {
			filetype = {
				["NvimTree"] = "NvimTree",
				["TelescopePrompt"] = "Telescope",
				["mason"] = "Mason",
				["lazy"] = "Lazy",
				["checkhealth"] = "CheckHealth",
        ["toggleterm"] = function ()
          return "ToggleTerm " .. vim.b.toggle_number
        end
			},
			buftype = {
				["terminal"] = "Terminal",
			},
		},
	},
	padding = { left = 1, right = 0 },
	update = function(self, sid)
    local bo = vim.bo
		local formatter = self.static.formatter

    --- @cast formatter {filetype: table<string, string>, buftype: table<string, string>}
		local filename = formatter.filetype[bo.filetype]
      or formatter.buftype[bo.buftype]
      or vim.fs.basename(vim.api.nvim_buf_get_name(0))

    if type(filename) == "function" then
      filename = filename()
    end

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
	context = function(self)
		local fn = vim.fn
		local filename = fn.expand("%:t")

		local has_devicons, devicons = pcall(require, "nvim-web-devicons")
		local icon, color_icon = nil, nil
		if has_devicons then
			icon, color_icon = devicons.get_icon_color(filename, fn.expand("%:e"))
		end

		if not icon then
			local extensions = self.static.extensions
      --- @cast extensions {filetypes: table<string, {[1]:string, [2]:string}>, buftypes: table<string, {[1]:string, [2]:string}>}
			local extension = extensions.filetypes[vim.bo.filetype]
        or extensions.buftypes[vim.bo.buftype]

			if extension then
				icon, color_icon = extension[1], extension[2]
			end
		end

		return {
			icon = icon or "",
			color = color_icon or "#ffffff",
		}
	end,
	style = function(self, sid)
    local ctx = require("witch-line.core.manager.hook").use_context(self, sid)
		return { fg = ctx.color }
	end,
	update = function(self, sid)
    local ctx = require("witch-line.core.manager.hook").use_context(self, sid)
		return ctx.icon
	end,
}

--- @type DefaultComponent
local Modifier = {
	id = Id["file.modifier"],
	_plug_provided = true,
	events = { "BufEnter","BufWritePost", "TextChangedI", "TextChanged" },
	style = {
		fg = colors.fg,
	},
	update = function(self, sid)
    local bo = vim.bo
		if bo.buftype == "prompt" then
			return ""
    elseif not bo.modifiable or bo.readonly then
			return ""
		elseif bo.modified then
			return ""
		end
		return ""
	end,
}

--- @type DefaultComponent
local Size =  {
	id = Id["file.size"],
  _plug_provided = true,
	ref = {
		events = Id["file.interface"],
		user_events = Id["file.interface"],
	},
	style = {
		fg = colors.green,
	},
	static = {
		icon = "",
	},
  update = function (self, sid)
		local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" then return "" end

    local file_size = (vim.uv or vim.loop).fs_stat(current_file).size
    if file_size == 0 then return "" end

		local suffixes = { "B", "KB", "MB", "GB" }
		local i = 1
		while file_size > 1024 and i < #suffixes do
			file_size = file_size / 1024
			i = i + 1
		end

		local format = i == 1 and "%d%s" or "%.1f%s"
    local static = self.static
    --- @cast static {icon: string}
		return static.icon .. " " .. string.format(format, file_size, suffixes[i])
	end,
}

return {
	interface = Interface,
	name = Name,
	icon = Icon,
	modifier = Modifier,
  size = Size,
}
