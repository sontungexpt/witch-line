---@type Component
return {
	id = 100,
	name = "form",
	lazy = true,

	inherit = "",
	ref = {},

	timing = false, -- The component will be update every time interval
	events = {},
	user_events = {},
	min_screen_width = 70,

	padding = 1,

	left = "",
	left_style = {},

	right = "",
	right_style = {},

	static = {},
	context = function() end, -- context is a table that will be passed to the component's update function

	style = {},

	init = function() end, -- called when the component is created
	pre_update = function(comp, ctx, static) end,
	update = function(comp, ctx, static)
		return ""
	end,
	post_update = function(comp, ctx, static) end,
	hidden = function(comp, ctx, static)
		return true
	end,
}
