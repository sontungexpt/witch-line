local vim, concat = vim, table.concat
local o = vim.o

local M = {}
local enabled = true

--- @type string[] The list of render value of component .
local Values = {}

---@type integer
local ValuesSize = 0

--- Inspects the current statusline values.
M.inspect = function()
	vim.notify(vim.inspect(Values), vim.log.levels.INFO, { title = "Witchline Statusline Values" })
end

--- Hidden all components by setting their values to empty strings.
M.empty_values = function()
	for i = 1, ValuesSize do
		Values[i] = ""
	end
end

M.on_vim_leave_pre = function()
	local CacheMod = require("witch-line.cache")
	--reset the values to empty strings
	--before caching
	--because when the plugin is loaded
	--the statusline must be empty stage
	M.empty_values()
	CacheMod.cache(Values, "Statusline")
	CacheMod.cache(ValuesSize, "StatuslineSize")
end

--- Loads the statusline cache.
--- @return function undo function to restore the previous state
M.load_cache = function()
	local CacheMod = require("witch-line.cache")
	local before_values = Values
	local before_values_size = ValuesSize

	Values = CacheMod.get("Statusline") or Values
	ValuesSize = CacheMod.get("StatuslineSize") or ValuesSize

	return function()
		Values = before_values
		ValuesSize = before_values_size
	end
end

M.clear = function()
	Values = {}
	ValuesSize = 0
	o.statusline = " "
end

M.get_size = function()
	return ValuesSize
end

M.render = function()
	if not enabled then
		o.statusline = " "
		return
	end
	local str = concat(Values)
	o.statusline = str ~= "" and str or " "
end

M.push = function(value)
	ValuesSize = ValuesSize + 1
	Values[ValuesSize] = value
	return ValuesSize
end

--- Sets the value for multiple components at once.
--- @param indices integer[] The indices of the components to set the value for.
--- @param value string The value to set for the specified components.
M.bulk_set = function(indices, value)
	for i = 1, #indices do
		Values[indices[i]] = value
	end
end

--- Sets the separator for left or right side of the component.
--- @param indices integer[]|string[] The indices of the components to set the separator for.
--- @param value string The separator value to set.
--- @param adjust number If true, sets the separator to the left of the component; otherwise, sets it to the right.
M.bulk_set_sep = function(indices, value, adjust)
	for i = 1, #indices do
		Values[indices[i] + adjust] = value
	end
end

M.set = function(idx, value)
	Values[idx] = value
end

M.get = function(idx)
	return Values[idx]
end

---@diagnostic disable-next-line: undefined-field
vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
	callback = function(e)
		vim.schedule(function()
			local ConfMod = require("witch-line.config")

			if ConfMod.is_buf_disabled(e.buf) then
				enabled = false
			else
				enabled = true
			end
			M.render()
		end)
	end,
})

return M
