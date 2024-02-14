local colors = require("sttusline.util.color")

return {
	name = "form", -- nickname to link the componet with the group
	timing = false, -- The component will be update every time interval
	lazy = true,

	event = {},
	min_width = function()
		return 0
	end,
	user_event = {},

	shared = {},

	static = {},
	configs = {},
	styles = {},

	group = false, -- if a component is flexible, it's children will be added when the parent is updated

	-- number or table
	padding = 1, -- { left = 1, right = 1 }

	init = function() end, -- called when the component is created

	propagation = false,
	pre_update = function() end,
	update = function()
		return ""
	end,
	post_update = function() end,
	condition = function()
		return true
	end,

	{},
	{},
}
