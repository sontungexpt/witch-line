local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
return {
	id = Id["datetime"],
  _plug_provided = true,
	timing = true,
	static = {
		format = "default",
	},
  update = function (self, ctx, static, session_id)
		local fmt = static.format or "default"
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
