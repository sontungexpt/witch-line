local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
local Interface = {
	id = Id["file.interface"],
	_plug_provided = true,
	events = "BufEnter",
	static = {
		formatter = {
			filetype = {
				["NvimTree"] = { "NvimTree", "", colors.red },
				["TelescopePrompt"] = { "Telescope", "", colors.red },
				["mason"] = { "Mason", "󰏔", colors.red },
				["lazy"] = { "Lazy", "󰏔", colors.red },
				["checkhealth"] = { "Health", "", colors.red },
				["plantuml"] = { nil, "", colors.green },
				["dashboard"] = { nil, "", colors.red },
				["toggleterm"] = {
					function()
						return "ToggleTerm " .. vim.b.toggle_number
					end,
					"",
					colors.red,
				},
			},
			buftype = {
				["terminal"] = { "Terminal", "", colors.red },
			},
		},
	},
	context = function(self)
		local api, fs, bo = vim.api, vim.fs, vim.bo
		local static = self.static
		--- @cast static {formatter: {filetype: table<string, string>, buftype: table<string, string>}, extensions:{filetypes: table<string, {[1]:string, [2]:string, [3]:string}>}}
		local fmt = static.formatter
		local formatter = fmt.filetype[bo.filetype] or fmt.buftype[bo.buftype]
		if formatter then
			local resolve = require("witch-line.utils").resolve
			local basename = resolve(formatter[1]) or fs.basename(api.nvim_buf_get_name(0))
			return {
				basename = basename ~= "" and basename or "No File",
				icon = resolve(formatter[2]) or "",
				color = resolve(formatter[3]) or "#ffffff",
			}
		end
		local basename, icon, color_icon
		basename = vim.fs.basename(vim.api.nvim_buf_get_name(0))

		local ok, devicons = pcall(require, "nvim-web-devicons")
		if ok then
			local extension = basename:match("%.([^%.]+)$")
			icon, color_icon = devicons.get_icon_color(basename, extension)
		end

		return {
			basename = basename ~= "" and basename or "No File",
			icon = icon or "",
			color = color_icon or "#ffffff",
		}
	end,
}

---@type DefaultComponent
local Name = {
	id = Id["file.name"],
	_plug_provided = true,
	ref = {
		events = Id["file.interface"],
		context = Id["file.interface"],
	},
	style = {
		fg = colors.orange,
	},
	update = function(self, sid)
		local ctx = require("witch-line.core.manager.hook").use_context(self, sid)
    ---@cast ctx {basename:string, icon:string, color:string}
		return ctx.basename
	end,
}

---@type DefaultComponent
local Icon = {
	id = Id["file.icon"],
	_plug_provided = true,
	ref = {
		events = Id["file.interface"],
		context = Id["file.interface"],
	},
	style = function(self, sid)
		local ctx = require("witch-line.core.manager.hook").use_context(self, sid)
    ---@cast ctx {basename:string, icon:string, color:string}
		return { fg = ctx.color }
	end,
	update = function(self, sid)
		local ctx = require("witch-line.core.manager.hook").use_context(self, sid)
    ---@cast ctx {basename:string, icon:string, color:string}
		return ctx.icon
	end,
}

--- @type DefaultComponent
local Modifier = {
	id = Id["file.modifier"],
	_plug_provided = true,
	events = { "BufEnter", "BufWritePost", "TextChangedI", "TextChanged" },
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
			-- ●
			return ""
		end
		return ""
	end,
}

--- @type DefaultComponent
local Size = {
	id = Id["file.size"],
	_plug_provided = true,
	ref = {
		events = Id["file.interface"],
	},
	style = {
		fg = colors.green,
	},
	static = {
		icon = "",
	},
	update = function(self, sid)
		local current_file = vim.api.nvim_buf_get_name(0)
		if current_file == "" then
			return ""
		end

		local stat = (vim.uv or vim.loop).fs_stat(current_file)
    if type(stat) ~= "table"  then
      return ""
    end
    local file_size = stat.size
		if not file_size or file_size == 0 then
			return ""
		end

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
