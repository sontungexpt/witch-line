--- @type DefaultComponent
local Weather = {
	id = "weather",
	_plug_provided = true,
	update = function(self, _)
		return ""
	end,
}

return Weather
