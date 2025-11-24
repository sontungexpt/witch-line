local colors = require("witch-line.constant.color")
local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local Encoding = {
	id = Id["encoding"],
	events = { "InsertEnter" },
	_plug_provided = true,
	style = { fg = colors.yellow },
	update = function(self, session_id)
		local enc = vim.bo.fenc ~= "" and vim.bo.fenc or vim.o.enc
		return enc and enc:upper() or ""
	end,
}
return Encoding
