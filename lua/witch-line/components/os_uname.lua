local Id = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")

--- @type DefaultComponent
return {
	id = Id["os_uname"],
	auto_theme = true,
	_plug_provided = true,
	events = { "BufEnter" },
	static = {
		icon = {
			mac = "",
			arch = "",
			linux = "",
			windows = "",
		},
		colors = {
			mac = colors.white,
			arch = colors.blue,
			linux = colors.yellow,
			windows = colors.blue,
		},
	},
	update = function(self, session_id)
		local os_uname = (vim.uv or vim.loop).os_uname()
		local static = self.static
		--- @cast static { icon: { mac: string, arch: string, linux: string, windows: string }, colors: { mac: string, arch: string, linux: string, windows: string } }
		local uname, static_icon, static_colors = os_uname.sysname, static.icon, static.colors

		if uname == "Darwin" then
			return static_icon.mac, { fg = static_colors.mac }
		elseif uname == "Linux" then
			if os_uname.release:find("arch") then
				return static_icon.arch, { fg = static_colors.arch }
			end
			return static_icon.linux, { fg = static_colors.linux }
		elseif uname == "Windows_NT" then
			return static_icon.windows, { fg = static_colors.windows }
		end

		return uname or "󱚟 Unknown OS", { fg = "#ffffff" }
	end,
}
