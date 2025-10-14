local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local Encoding = {
	id = Id["encoding"],
	events = { "InsertEnter" },
	_plug_provided = true,
	static = {
		["utf-8"] = "󰉿",
		["utf-16"] = "󰊀",
		["utf-32"] = "󰊁",
		["utf-8mb4"] = "󰊂",
		["utf-16le"] = "󰊃",
		["utf-16be"] = "󰊄",
	},
	style = { fg = colors.yellow },
	update = function(self, session_id)
		local enc = vim.bo.fenc ~= "" and vim.bo.fenc or vim.o.enc
    return enc and self.static[enc] or enc or ""
	end,
}
return Encoding
