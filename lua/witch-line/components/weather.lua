local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
local Weather = {
	id = Id["weather"],
	_plug_provided = true,
	update = function(self, sid)
		return ""
	end,
}

return Weather
