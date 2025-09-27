local vim, concat = vim, table.concat
local o = vim.o

local M = {}
local enabled = true

--- @type string[] The list of render value of component .
local Values = {}
---@type integer
local ValuesSize = 0

--- @type table<integer, true>
local Frozens = {}

--- Inspects the current statusline values.
M.inspect = function()
	vim.notify(vim.inspect(Values), vim.log.levels.INFO, { title = "Witchline Statusline Values" })
end


--- Resets all values
M.empty_values = function(condition)
	if type(condition) ~= "function" then
		for i = 1, ValuesSize do
			if condition(i) then
				Values[i] = ""
			end
		end
	else
		for i = 1, ValuesSize do
			Values[i] = ""
		end
	end
end

--- Handles necessary operations before Vim exits.
---
--- @param CacheDataAccessor Cache.CacheDataAccessor The data accessor module to use for caching the statusline.
M.on_vim_leave_pre = function(CacheDataAccessor)
	-- Clear unfrozen values to reset statusline on next startup
	M.empty_values(function(idx)
		return not Frozens[idx]
	end)
	CacheDataAccessor.set("Statusline", Values)
	CacheDataAccessor.set("StatuslineSize", ValuesSize)
end

--- Loads the statusline cache.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for loading the statusline.
--- @return function undo function to restore the previous state
M.load_cache = function(CacheDataAccessor)
	local before_values = Values
	local before_values_size = ValuesSize

	Values = CacheDataAccessor.get("Statusline") or Values
	ValuesSize = CacheDataAccessor.get("StatuslineSize") or ValuesSize

	return function()
		Values = before_values
		ValuesSize = before_values_size
	end
end

--- Clears all statusline values and resets the statusline to a single space.
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

--- Marks a component's value as frozen, preventing it from being cleared on Vim exit.
--- @param idx integer The index of the component to freeze.		
M.freeze = function(idx)
	Frozens[idx] = true
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

--- Sets the value for a specific component.
--- @param idx integer The index of the component to set the value for.
--- @param value string The value to set for the specified component.
M.set = function(idx, value)
	Values[idx] = value
end

--- Gets the value for a specific component.
--- @param idx integer The index of the component to get the value for.
--- @return string|nil The value of the specified component, or nil if it does not
M.get = function(idx)
	return Values[idx]
end


M.enable_hide_automatically = function()
	---@diagnostic disable-next-line: undefined-field
	vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
		callback = function(e)
			local buf = e.buf
			vim.schedule(function()
				local ConfMod = require("witch-line.config")
				enabled = not ConfMod.is_buf_disabled(buf)
				M.render()
			end)
		end,
	})
end


return M
