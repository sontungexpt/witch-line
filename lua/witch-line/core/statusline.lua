local vim, concat, type = vim, table.concat, type
local o, bo, api = vim.o, vim.bo, vim.api
local assign_highlight_name = require("witch-line.core.highlight").assign_highlight_name
local M = {}

--- @type string[] The list of render value of component .
local Values = {
	-- [1] = "%#WitchLineComponent1#",
	-- [2] = "Component1",
	-- [3] = "%#WitchLineComponent2#",
	-- [4] = "Component2",
}
---@type integer The size of the Values list.
local ValuesSize = 0

--- @type table<integer, string> A mapping from component indices to their highlight group name
local IdxHlMap = {
	-- [1] = "WitchLineComponent1",
	-- [2] = "WitchLineComponent2",

	-- [5] = "WitchLineComponent3",
}


--- @type table<integer, true> The set of indices of components that are frozen (not cleared on Vim exit).
local Frozens = {
	-- [1] = true,
	-- [2] = true,
}


--- @type table<integer, {idx: integer, priority: integer}> A priority queue of flexible components. It's always sorted by priority in ascending order.
--- Components with lower priority values are considered more important and will be retained longer when space is limited
local FlexiblePriorityQueue = {
	-- { idx = 1, priority = 1 },
	-- { idx = 2, priority = 2 },
}


--- Marks a component's highlight group.
--- @param idxs integer[] The index or indices of the component(s) to mark.
--- @param hl_name string The highlight group name to assign.
M.mark_highlight = function(idxs, hl_name)
	for i = 1, #idxs do
		IdxHlMap[idxs[i]] = hl_name
	end
end

--- Marks a component's separator highlight group.
--- @param idxs integer[] The index or indices of the component(s) to mark.
--- @param hl_name string The highlight group name to assign.
--- @param adjust number If true, marks the separator to the left of the component; otherwise, marks it to the right.
M.mark_sep_highlight = function(idxs, hl_name, adjust)
	for i = 1, #idxs do
		IdxHlMap[idxs[i] + adjust] = hl_name
	end
end


--- Tracks a component as flexible with a given priority.
--- Components with lower priority values are considered more important and will be retained longer when space is limited.
--- @param idx integer The index of the component to track.
--- @param priority integer The priority of the component; lower values indicate higher importance.
M.track_flexible = function(idx, priority)
	local new_len = #FlexiblePriorityQueue + 1
	FlexiblePriorityQueue[new_len] = { idx = idx, priority = priority }

	-- sort by insertion sort algorithm
	for i = new_len, 2, -1 do
		if FlexiblePriorityQueue[i].priority < FlexiblePriorityQueue[i - 1].priority then
			FlexiblePriorityQueue[i], FlexiblePriorityQueue[i - 1] = FlexiblePriorityQueue[i - 1],
				FlexiblePriorityQueue[i]
		else
			break
		end
	end
end


--- Inspects the current statusline values.
M.inspect = function()
	require("witch-line.utils.notifier").info(vim.inspect(Values))
end


--- Resets all values
--- @param condition function|nil If provided, only clears values for which the condition function returns true when passed the index.
M.empty_values = function(condition)
	if type(condition) == "function" then
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
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for caching the statusline.
M.on_vim_leave_pre = function(CacheDataAccessor)
	-- Clear unfrozen values to reset statusline on next startup
	M.empty_values(function(idx)
		return not Frozens[idx]
	end)
	CacheDataAccessor.set("Statusline", Values)
	CacheDataAccessor.set("StatuslineSize", ValuesSize)
	CacheDataAccessor.set("FlexiblePriorityQueue", FlexiblePriorityQueue)
end

--- Loads the statusline cache.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for loading the statusline.
--- @return function undo function to restore the previous state
M.load_cache = function(CacheDataAccessor)
	local before_values = Values
	local before_values_size = ValuesSize
	local before_flexible_queue = FlexiblePriorityQueue

	Values = CacheDataAccessor.get("Statusline") or Values
	ValuesSize = CacheDataAccessor.get("StatuslineSize") or ValuesSize
	FlexiblePriorityQueue = CacheDataAccessor.get("FlexiblePriorityQueue") or FlexiblePriorityQueue

	return function()
		Values = before_values
		ValuesSize = before_values_size
		FlexiblePriorityQueue = before_flexible_queue
	end
end

--- Clears all statusline values and resets the statusline to a single space.
M.clear = function()
	Values = {}
	ValuesSize = 0
	o.statusline = " "
end


--- Gets the current size of the statusline values.
--- @return integer size The current size of the statusline values.
M.get_size = function()
	return ValuesSize
end


--- Merges the highlight group names with the corresponding statusline values.
--- @param values string[] The list of statusline values to merge with highlight group names.
--- @return string[] merged The merged list of statusline values with highlight group names applied.
local function merge_highlight_with_values(values)
	local merged = {}
	local len    = values == Values and ValuesSize or #values
	for i = 1, len do
		local hl_name = IdxHlMap[i]
		merged[i] = hl_name and assign_highlight_name(values[i], hl_name) or values[i]
	end
	return merged
end

--- Renders the statusline by concatenating all component values and setting it to `o.statusline`.
--- If the statusline is disabled, it sets `o.statusline` to a single space.
--- @param full_width number|nil The max width of the statusline. If true, uses the full width of the window.
M.render = function(full_width)
	local removed_idx = #FlexiblePriorityQueue
	if removed_idx == 0 then
		local str = concat(merge_highlight_with_values(Values))
		o.statusline = str ~= "" and str or " "
		return
	end

	local strdisplaywidth = vim.fn.strdisplaywidth

	full_width = (full_width and o.columns) or api.nvim_win_get_width(0)
	local ValuesCopied = require("witch-line.utils.tbl").shallow_copy(Values)
	local values_len = strdisplaywidth(concat(ValuesCopied))
	while removed_idx > 0 and values_len > full_width do
		local value_idx = FlexiblePriorityQueue[removed_idx].idx
		local removed_value = ValuesCopied[value_idx] or ""
		if removed_value ~= "" then
			ValuesCopied[value_idx] = ""
			values_len = values_len - strdisplaywidth(removed_value)
		end
		removed_idx = removed_idx - 1
	end
	local str = concat(merge_highlight_with_values(ValuesCopied))
	o.statusline = str ~= "" and str or " "
end


--- Appends a new value to the statusline values list.
--- @param value string The value to append.
--- @return integer new_idx The index of the newly added value.
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

--- Determines if a buffer is disabled based on its filetype and buftype.
--- @param bufnr integer The buffer number to check.
--- @param disabled BufDisabled|nil The disabled configuration to check against. If nil, the buffer is not disabled.
--- @return boolean
M.is_buf_disabled = function(bufnr, disabled)
	if not api.nvim_buf_is_valid(bufnr)
		or type(disabled) ~= "table"
	then
		return false
	end

	local buf_o = bo[bufnr]
	if type(disabled.filetypes) == "table" then
		local filetype = buf_o.filetype
		for _, ft in ipairs(disabled.filetypes) do
			if filetype == ft then
				return true
			end
		end
	end

	if type(disabled.buftypes) == "table" then
		local buftype = buf_o.buftype
		for _, bt in ipairs(disabled.buftypes) do
			if buftype == bt then
				return true
			end
		end
	end


	return false
end

--- Setup the necessary things for statusline rendering.
--- @param disabled BufDisabled|nil The disabled configuration to apply.
M.setup = function(disabled)
	--- For automatically rerender statusline on Vim or window resize when there are flexible components.
	if next(FlexiblePriorityQueue) then
		api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
			callback = function()
				M.render() -- full width
			end,
		})
	end

	--- For automatically toggle `laststatus` based on buffer filetype and buftype.
	local user_laststatus = o.laststatus or 3

	api.nvim_create_autocmd("OptionSet", {
		pattern = "laststatus",
		callback = function()
			local new_status = o.laststatus
			if new_status ~= 0 then
				user_laststatus = new_status
			end
		end,
	})

	api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
		callback = function(e)
			local buf = e.buf
			vim.schedule(function()
				local disabled = M.is_buf_disabled(buf, disabled)

				if not disabled and o.laststatus == 0 then
					api.nvim_set_option_value("laststatus", user_laststatus, {})
					M.render() -- rerender statusline immediately
				elseif disabled and o.laststatus ~= 0 then
					api.nvim_set_option_value("laststatus", 0, {})
				else
					return -- no change no need to redrawstatus
				end

				if api.nvim_get_mode().mode == "c" then
					vim.cmd("redrawstatus")
				end
			end)
		end,
	})
end


return M
