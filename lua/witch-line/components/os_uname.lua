local Id       = require("witch-line.constant.id").Id
local colors   = require("witch-line.constant.color")

--- @type DefaultComponent
return {
	id = Id["os_uname"],
  _plug_provided = true,
	events = { "VimEnter" },
	style = {
		fg = colors.orange,
	},
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
  update =function (self, ctx, static, session_id)
		local os_uname = (vim.uv or vim.loop).os_uname()

		local uname = os_uname.sysname
		if uname == "Darwin" then
			return static.icon.mac, { fg = static.colors.mac }
		elseif uname == "Linux" then
			if os_uname.release:find("arch") then
				return static.icon.arch, { fg = static.colors.arch}
			end
				return static.icon.linux, { fg = static.colors.linux }
		elseif uname == "Windows_NT" then
				return static.icon.windows, { fg = static.colors.windows }
		else
			return uname or "󱚟 Unknown OS", {fg = "#ffffff"}
		end
	end,
}
