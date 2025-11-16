local Id = require("witch-line.constant.id").Id

--- @type DefaultComponent
local SearchCount = {
	id = Id["search.count"],
	_plug_provided = true,
	events = { "CmdlineLeave /" },
	hidden = function(self, sid)
		return vim.v.hlsearch == 0
	end,
	update = function(self, session_id)
		local search = vim.fn.searchcount({ maxcount = 999 })
		if not search then
			return ""
		end
		local current = search.current
		return current and current .. "/" .. math.min(search.total or 0, search.maxcount or 999)
	end,
}

return {
	count = SearchCount,
}
