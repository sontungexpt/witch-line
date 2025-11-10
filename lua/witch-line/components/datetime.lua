local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
return {
	id = Id["datetime"],
	_plug_provided = true,
	timing = true,
	static = {
		format = "default",
	},
	update = function(self, session_id)
		--- @type {format: string}
		---@diagnostic disable-next-line: assign-type-mismatch
		local static = self.static
		local fmt = static.format or "default"
		--- @cast fmt string
		if fmt == "default" then
			fmt = "%A, %B %d | %H.%M"
		elseif fmt == "us" then
			fmt = "%m/%d/%Y"
		elseif fmt == "uk" then
			fmt = "%d/%m/%Y"
		elseif fmt == "iso" then
			fmt = "%Y-%m-%d"
		end
		return tostring(os.date(fmt))
	end,
}
