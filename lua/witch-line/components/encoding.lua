local colors = require("witch-line.constant.color")

---@type DefaultComponent
local Encoding = {
	id = "encoding",
	events = { "InsertEnter" },
	_plug_provided = true,
	style = { fg = colors.yellow },
	update = function(self, _)
		local enc = vim.bo.fenc ~= "" and vim.bo.fenc or vim.o.enc
		return enc and enc:upper() or ""
	end,
}
return Encoding
