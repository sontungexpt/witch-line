local vim, concat, type = vim, table.concat, type
local o, bo, api, strdisplaywidth = vim.o, vim.bo, vim.api, vim.fn.strdisplaywidth
local assign_highlight_name = require("witch-line.core.highlight").assign_highlight_name
local M = {}

--- @type table<integer, true> The set of indices of components that are frozen (not cleared on Vim exit). It's contains the idx of string component in Values list.
local Frozens = {
	-- [1] = true,
	-- [2] = true,
}


--- @type string[] The list of render value of component .
local Values = {
	-- [1] = "#WitchLineComponent1",
	-- [2] = "Component1",
	-- [3] = "WitchLineComponent2",
	-- [4] = "Component2",
}

---@type integer The size of the Values list.
local ValuesSize = 0


--- @type table<integer, string> The map of idx of value to highlight group name.
local IdxHlMap = {
	-- [1] = "WitchLineComponent1",
	-- [2] = "WitchLineComponent2",
	-- [5] = "WitchLineComponent3",
}


--- @type table<integer, string> The map of idx of value to forced hidden value when truncated.
local FlexibleHiddenIdxValueMap = {
	-- [1] = "WitchLineComponent",
}


--- @type table<integer, {idx: integer, priority: integer}> A priority queue of flexible components. It's always sorted by priority in ascending order.
--- Components with lower priority values are considered more important and will be retained longer when space is limited
local FlexiblePrioritySorted = {
	-- { idx = 1, priority = 1 },
	-- { idx = 2, priority = 2 },
}

local TruncatedLength = 0
local FlexibleHiddenStopped = -1


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

--- Restores all hidden flexible values to their original state.
--- This function is used to reset the statusline to its full state, making all components visible
local function restore_all_hidden_flexible_values()
	for idx, value in pairs(FlexibleHiddenIdxValueMap) do
		Values[idx] = value
	end
end

--- Hides flexible values based on the available width.
--- It iteratively hides the least important flexible components until the total length fits within the specified width.
--- @param width integer The available width to fit the statusline within.
local function hide_flexible_values(width)
	while FlexibleHiddenStopped > 0 and TruncatedLength > width do
		FlexibleHiddenStopped                = FlexibleHiddenStopped - 1
		local value_idx                      = FlexiblePrioritySorted[FlexibleHiddenStopped].idx
		local value                          = Values[value_idx]
		FlexibleHiddenIdxValueMap[value_idx] = value
		Values[value_idx]                    = ""
		TruncatedLength                      = TruncatedLength - strdisplaywidth(value)
	end
end

--- Restores previously hidden flexible values based on the available width.
--- It iteratively restores the most recently hidden flexible components until the total length exceeds the specified width.
--- @param width integer The available width to fit the statusline within.	
local function restore_flexible_hidden_values(width)
	local len = #FlexiblePrioritySorted
	repeat
		FlexibleHiddenStopped = FlexibleHiddenStopped + 1
		local prev_value_idx  = FlexiblePrioritySorted[FlexibleHiddenStopped].idx
		local value           = FlexibleHiddenIdxValueMap[prev_value_idx]
		local new_length      = TruncatedLength + strdisplaywidth(value)

		if new_length > width then
			FlexibleHiddenStopped = FlexibleHiddenStopped - 1
			break
		end

		-- Restore the value
		Values[prev_value_idx]                    = value
		FlexibleHiddenIdxValueMap[prev_value_idx] = nil
		TruncatedLength                           = new_length
	until FlexibleHiddenStopped == len
end

local function handle_flexible_values(width)
	if TruncatedLength < width then
		restore_flexible_hidden_values(width)
	elseif TruncatedLength > width then
		hide_flexible_values(width)
	end
end

--- Tracks a component as flexible with a given priority.
--- Components with lower priority values are considered more important and will be retained longer when space is limited.
--- @param idx integer The index of the component to track.
--- @param priority integer The priority of the component; lower values indicate higher importance.
M.track_flexible = function(idx, priority)
	local new_len = #FlexiblePrioritySorted + 1

	-- Insert the component and sort in ascending order of priority at the same time using insertion sort
	FlexiblePrioritySorted[new_len] = { idx = idx, priority = priority }
	while new_len > 1 and FlexiblePrioritySorted[new_len].priority < FlexiblePrioritySorted[new_len - 1].priority do
		FlexiblePrioritySorted[new_len], FlexiblePrioritySorted[new_len - 1] = FlexiblePrioritySorted[new_len - 1],
			FlexiblePrioritySorted[new_len]
		new_len = new_len - 1
	end

	if FlexibleHiddenStopped ~= -1 then
		local width = o.columns or api.nvim_win_get_width(0)
		restore_all_hidden_flexible_values()
		handle_flexible_values(width)
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
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for caching the statusline.
M.on_vim_leave_pre = function(CacheDataAccessor)
	--- restore real values of components
	for idx, value in pairs(FlexibleHiddenIdxValueMap) do
		Values[idx] = value
	end

	-- Clear unfrozen values to reset statusline on next startup
	M.empty_values(function(idx)
		return not Frozens[idx]
	end)
	CacheDataAccessor.set("Statusline", Values)
	CacheDataAccessor.set("StatuslineSize", ValuesSize)
	CacheDataAccessor.set("FlexiblePrioritySorted", FlexiblePrioritySorted)
end

--- Loads the statusline cache.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for loading the statusline.
--- @return function undo function to restore the previous state
M.load_cache = function(CacheDataAccessor)
	local before_values = Values
	local before_values_size = ValuesSize
	local before_flexible_priority_sorted = FlexiblePrioritySorted

	Values = CacheDataAccessor.get("Statusline") or Values
	ValuesSize = CacheDataAccessor.get("StatuslineSize") or ValuesSize
	FlexiblePrioritySorted = CacheDataAccessor.get("FlexiblePrioritySorted") or FlexiblePrioritySorted

	return function()
		Values = before_values
		ValuesSize = before_values_size
		FlexiblePrioritySorted = before_flexible_priority_sorted
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
--- @return string[] merged The merged list of statusline values with highlight group names applied.
local function assign_hlname_to_value()
	local merged = {}
	for i = 1, ValuesSize do
		local hl_name = IdxHlMap[i]
		merged[i] = hl_name and assign_highlight_name(Values[i], hl_name) or Values[i]
	end
	return merged
end

--- Renders the statusline by concatenating all component values and setting it to `o.statusline`.
--- If the statusline is disabled, it sets `o.statusline` to a single space.
M.render = function()
	local str = concat(assign_hlname_to_value())
	o.statusline = str ~= "" and str or " "


	-- full_width = (full_width and o.columns) or api.nvim_win_get_width(0)
	-- local ValuesCopied = require("witch-line.utils.tbl").shallow_copy(Values)
	-- TruncatedLength = strdisplaywidth(concat(ValuesCopied))

	-- while removed_idx > 0 and TruncatedLength > full_width do
	-- 	local value_idx = FlexiblePrioritySorted[removed_idx].idx
	-- 	local removed_value = ValuesCopied[value_idx] or ""
	-- 	if removed_value ~= "" then
	-- 		ValuesCopied[value_idx] = ""
	-- 		TruncatedLength = TruncatedLength - strdisplaywidth(removed_value)
	-- 	end
	-- 	removed_idx = removed_idx - 1
	-- end
	-- local str = concat(assign_hlname_to_value(ValuesCopied))
	-- o.statusline = str ~= "" and str or " "
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
--- @param disabled BufDisabledConfig|nil The disabled configuration to check against. If nil, the buffer is not disabled.
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
--- @param disabled_config BufDisabledConfig|nil The disabled configuration to apply.
M.setup = function(disabled_config)
	--- For automatically rerender statusline on Vim or window resize when there are flexible components.
	if next(FlexiblePrioritySorted) then
		local render_flexible_debounce = require("witch-line.utils").debounce(function()
			local width = o.columns or api.nvim_win_get_width(0)
			handle_flexible_values(width)
			M.render()
		end, 100)

		api.nvim_create_autocmd({ "VimResized" }, {
			callback = render_flexible_debounce,
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
				local disabled = M.is_buf_disabled(buf, disabled_config)

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
