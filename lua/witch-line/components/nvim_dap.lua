local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
return {
	id = Id["nvim_dap"],
	auto_theme = true,
	_plug_provided = true,
	events = { "CursorHold", "CursorMoved", "BufEnter" }, -- The component will be update when the event is triggered
	update = function()
		return require("dap").status()
	end,
	hidden = function()
		local session = require("dap").session()
		return session == nil
	end,
}
