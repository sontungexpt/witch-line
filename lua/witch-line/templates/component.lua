-- local colors = require("sttusline.util.color")
return {
	name = "form",
	timing = false, -- The component will be update every time interval
	lazy = true,
	dispersed = false, -- if true, the component will be rendered as a string, otherwise it will be rendered as a table

	events = {},
	user_events = {},

	left = 1,
	right = 1,

	static = {},
	context = function() end, -- context is a table that will be passed to the component's update function

	style = {},

	-- group = false, -- if a component is flexible, it's children will be added when the parent is updated

	init = function() end, -- called when the component is created

	pre_update = function(ctx) end,
	update = function(ctx)
		return ""
	end,
	post_update = function(ctx) end,
	display_when = function(ctx)
		return true
	end,
}
