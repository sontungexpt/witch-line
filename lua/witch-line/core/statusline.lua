local bit = require("bit")

local vim, concat, type, ipairs = vim, table.concat, type, ipairs
local o, bo, api = vim.o, vim.bo, vim.api
local bor, band, lshift = bit.bor, bit.band, bit.lshift
local nvim_strwidth = api.nvim_strwidth
local assign_highlight_name = require("witch-line.core.highlight").assign_highlight_name

local M = {}
-- Constants controlling the relative index positions for layout calculation.
-- These are typically used to determine horizontal shifts (e.g., for padding, borders, etc.)
---@type integer  Offset index for the left side.
local LEFT_SHIFT = -1
---@type integer  Offset index for the right side
local RIGHT_SHIFT = -1
---@type integer  Distance (gap) between consecutive shift indices.
local SHIFT_GAP = 3
---@type integer  Base offset applied to value computations.
local VALUE_SHIFT = 2
---@type integer  Derived offset for string width calculations
local STRWIDTH_SHIFT = VALUE_SHIFT + SHIFT_GAP

--- Compute the left-side index based on a given shift value.
--- Used when aligning or spacing elements to the left.
--- @param shift integer The base shift amount.
--- @return integer idx The computed index for the left side.
local left_idx = function(shift)
	return shift + LEFT_SHIFT
end

--- Compute the right-side index based on a given shift value.
--- Used when aligning or spacing elements to the right.
--- @param shift integer The base shift amount.
--- @return integer idx The computed index for the right side.
local right_idx = function(shift)
	return shift + RIGHT_SHIFT
end

--- Compute the side index dynamically based on direction.
--- This function generalizes `left_idx` and `right_idx` into one,
--- where `side_shift` determines the direction of offset.
---
--- Example:
--- ```lua
--- side_idx(5, -1) --> 4   (left side)
--- side_idx(5,  1) --> 6   (right side)
--- ```
---
--- @param shift_base integer The base shift value to offset from.
--- @param side_shift 1|-1 Direction multiplier: `-1` for left, `1` for right.
--- @return integer idx The computed index corresponding to the side.
local side_idx = function(shift_base, side_shift)
	return shift_base + side_shift
end

--- @class Segment A statusline component segment.
--- @field frozen true|nil If true, the part is frozen and will not be cleared on Vim exit.
--- @field click_handler_form string|nil The click handler for the component. ( Not be cached )
--- @field total_width integer|nil The click handler for the component. ( Not be cached )

--- @type Segment[] The list of statusline components.
local Statusline = {
	-- { value = "", hl = nil, left = nil, left_hl = nil, right = nil, right_hl = nil, frozen = nil, click_handler_form = nil },
	-- { value = "", hl = nil, left = nil, left_hl = nil, right = nil, right_hl = nil, frozen = nil, click_handler_form = nil },
}

---@type integer The size of the Values list.
local ValuesSize = 0

--- @type table<integer, {idx: integer, priority: integer}> A priority queue of flexible components. It's always sorted by priority in ascending order.
--- Components with lower priority values are considered more important and will be retained longer when space is limited
local FlexiblePrioritySorted = {
	-- { idx = 1, priority = 1 },
	-- { idx = 2, priority = 2 },
}

--- @type integer The length of FlexiblePrioritySorted
local FlexiblePrioritySortedLen = 0

--- Gets the current size of the statusline values.
--- @return integer size The current size of the statusline values.
M.get_size = function()
	return ValuesSize
end

--- Tracks a component as flexible with a given priority.
--- Components with lower priority values are considered more important and will be retained longer when space is limited.
--- @param idx integer The group indexs of the component to track as flexible (including main part and its separators).
--- @param priority integer The priority of the component; lower values indicate higher importance.
M.track_flexible = function(idx, priority)
	FlexiblePrioritySortedLen = FlexiblePrioritySortedLen + 1

	-- Insert the component and sort in ascending order of priority at the same time using insertion sort
	local i = FlexiblePrioritySortedLen
	while i > 1 and priority < FlexiblePrioritySorted[i].priority do
		FlexiblePrioritySorted[i] = FlexiblePrioritySorted[i - 1]
		i = i - 1
	end
	FlexiblePrioritySorted[i] = { idx = idx, priority = priority }
end

--- Inspects the current statusline values.
--- @param t "statusline"|"flexible_priority_sorted"|nil The type of values to inspect. If nil or "values", inspects the statusline values.
M.inspect = function(t)
	local notifier = require("witch-line.utils.notifier")
	if t == "flexible_priority_sorted" then
		notifier.info(vim.inspect(FlexiblePrioritySorted))
	elseif t == nil or t == "statusline" then
		notifier.info(vim.inspect(Statusline))
	end
end

--- Resets all values
--- @param cb function callback function to be called for each value during the reset process.
M.iterate_values = function(cb)
	for i = 1, ValuesSize do
		cb(i, Statusline[i])
	end
end

--- Resets the value of a statusline component before caching.
--- @param segment Segment The statusline component to reset.
local format_state_before_cache = function(segment)
	for k, v in pairs(segment) do
		if
			k ~= "frozen"
			and k ~= "click_handler_form"
			and k ~= left_idx(VALUE_SHIFT)
			and k ~= k ~= right_idx(VALUE_SHIFT)
		then
			if k == VALUE_SHIFT then
				if not segment.frozen then
					segment[k] = "" -- Clear unfrozen main value
				end
			else
				segment[k] = nil
			end
		end
	end
end

--- Handles necessary operations before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for caching the statusline.
M.on_vim_leave_pre = function(CacheDataAccessor)
	-- Clear unfrozen values to reset statusline on next startup
	M.iterate_values(function(_, segment)
		format_state_before_cache(segment)
	end)

	CacheDataAccessor.set("Statusline", Statusline)
	CacheDataAccessor.set("StatuslineSize", ValuesSize)
	CacheDataAccessor.set("FlexiblePrioritySorted", FlexiblePrioritySorted)
	CacheDataAccessor.set("FlexiblePrioritySortedLen", FlexiblePrioritySortedLen)
end

--- Loads the statusline cache.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for loading the statusline.
--- @return function undo function to restore the previous state
M.load_cache = function(CacheDataAccessor)
	local before_values, before_values_size, before_flexible_priority_sorted, before_flexible_priority_sorted_len =
		Statusline, ValuesSize, FlexiblePrioritySorted, FlexiblePrioritySortedLen

	Statusline = CacheDataAccessor.get("Statusline") or Statusline
	ValuesSize = CacheDataAccessor.get("StatuslineSize") or ValuesSize
	FlexiblePrioritySorted = CacheDataAccessor.get("FlexiblePrioritySorted") or FlexiblePrioritySorted
	FlexiblePrioritySortedLen = CacheDataAccessor.get("FlexiblePrioritySortedLen") or FlexiblePrioritySortedLen

	return function()
		Statusline, ValuesSize, FlexiblePrioritySorted, FlexiblePrioritySortedLen =
			before_values, before_values_size, before_flexible_priority_sorted, before_flexible_priority_sorted_len
	end
end

--- Marks specific indices to be skipped during the merging process.
--- @param bitmasks integer The current bitmask representing indices to skip.
--- @param idx integer The index to mark for skipping.
--- @return integer new_mask The updated bitmask with the specified index marked for skipping.
local skip = function(bitmasks, idx)
	return bor(bitmasks, lshift(1, idx - 1))
end

--- Checks if a specific index is marked to be skipped in the bitmask.
--- @param bitmasks integer The bitmask representing indices to skip.
--- @param idx integer The index to check for skipping.
--- @return boolean is_skipped True if the index is marked to be skipped, false otherwise.
local is_skipped = function(bitmasks, idx)
	return band(bitmasks, lshift(1, idx - 1)) ~= 0
end

--- Merges the highlight group names with the corresponding statusline values.
--- @param skip_bitmasks integer|nil A bitmask representing indices to skip during the merging process (1-based index). If nil, no indices are skipped.
--- @return string[] merged The merged list of statusline values with highlight group names applied.
local function build_values(skip_bitmasks)
	skip_bitmasks = skip_bitmasks or 0

	--- Lazy load
	local values, n = {}, 0

	for i = 1, ValuesSize do
		if not is_skipped(skip_bitmasks, i) then
			local seg = Statusline[i]

			local val = seg[VALUE_SHIFT] or ""
			-- If no main value, skip the whole segment including its left and right parts
			if val ~= "" then
				local click_handler_form = seg.click_handler_form
				if click_handler_form then
					n = n + 1
					values[n] = click_handler_form
				end

				local left, right = seg[left_idx(VALUE_SHIFT)], seg[right_idx(VALUE_SHIFT)]
				if left and left ~= "" then
					n = n + 1
					values[n] = left
				end

				--- Main part
				n = n + 1
				values[n] = val

				--- Right part
				if right and right ~= "" then
					n = n + 1
					values[n] = right
				end

				if click_handler_form then
					n = n + 1
					values[n] = "%X"
				end
			end
		end
	end
	return values
end

--- Computes the total display width of a statusline component including its left and right parts.
--- This function caches the computed width to optimize performance.
--- @param seg Segment The statusline component to compute the width for.
--- @return integer width The total display width of the component including its left and right parts.
local compute_segment_width = function(seg)
	local width = seg.total_width
	if width then
		return width
	end
	width = seg[STRWIDTH_SHIFT] or 0
	if width ~= 0 then
		width = width + seg[left_idx(STRWIDTH_SHIFT)] or 0 + seg[right_idx(STRWIDTH_SHIFT)] or 0
	end

	seg.total_width = width
	return width
end
M.compute_segment_width = compute_segment_width

--- Computes the total display width of all statusline components.
--- This function caches the computed widths to optimize performance.
--- @return integer total_width The total display width of all statusline components.
local compute_statusline_width = function()
	local total_width = 0
	for i = 1, ValuesSize do
		total_width = total_width + compute_segment_width(Statusline[i])
	end
	return total_width
end
M.compute_statusline_width = compute_statusline_width

--- Hides a specific component by setting its value to an empty string.
--- @param idxs integer[] The index of the component to hide.
M.hide_segment = function(idxs)
	for i = 1, #idxs do
		local seg = Statusline[idxs[i]]
		seg[VALUE_SHIFT] = ""
		seg[STRWIDTH_SHIFT] = 0
		seg.total_width = 0
	end
end

--- Renders the statusline by concatenating all component values and setting it to `o.statusline`.
--- If the statusline is disabled, it sets `o.statusline` to a single space.
--- @param max_width integer|nil The maximum width for the statusline. Defaults to vim.o.columns if not provided.
M.render = function(max_width)
	if o.laststatus == 0 then
		return
	elseif FlexiblePrioritySortedLen == 0 then
		local str = concat(build_values())
		o.statusline = str ~= "" and str or " "
		return
	end

	local skip_mask = 0
	local removed_idx = FlexiblePrioritySortedLen
	local truncated_len = compute_statusline_width()

	max_width = max_width or o.columns
	while removed_idx > 0 and truncated_len > max_width do
		local value_idx = FlexiblePrioritySorted[removed_idx].idx
		skip_mask = skip(skip_mask, value_idx)
		truncated_len = truncated_len - compute_segment_width(Statusline[value_idx])
		removed_idx = removed_idx - 1
	end
	local str = concat(build_values(skip_mask))
	o.statusline = str ~= "" and str or " "
end

--- Appends a new value to the statusline values list.
--- @param value string The value to append.
--- @param frozen boolean|nil If true, the value is marked as frozen and will not be cleared on Vim exit.
--- @return integer new_idx The index of the newly added value.
M.push = function(value, frozen)
	ValuesSize = ValuesSize + 1

	local width = nvim_strwidth(value)
	--- @type Segment
	Statusline[ValuesSize] = {
		[VALUE_SHIFT] = value,
		[STRWIDTH_SHIFT] = width,
		total_width = width,
		frozen = frozen,
	}
	return ValuesSize
end

--- Sets the value for a specific component.
--- @param idxs integer|integer[] The index of the component to set the side value for.
--- @param value string The value to set for the specified side.
--- @param hl_name string|nil The highlight group name to set for the specified side.
M.set_value = function(idxs, value, hl_name)
	local width = nvim_strwidth(value)
	for i = 1, #idxs do
		local seg = Statusline[idxs[i]]
		seg.total_width = (seg.total_width or 0) - (seg[STRWIDTH_SHIFT] or 0) + width
		seg[STRWIDTH_SHIFT] = width
		seg[VALUE_SHIFT] = assign_highlight_name(value, hl_name)
	end
end

--- Sets the left or right side value for a specific component.
--- @param idxs integer|integer[] The index of the component to set the side value for.
--- @param shift_side -1|1 The shift side value to get the side idx. 1 Right, -1 Left
--- @param value string The value to set for the specified side.
--- @param hl_name string|nil The highlight group name to set for the specified side.
--- @param force boolean|nil If true, forces the update even if a value already exists for the specified side.
M.set_side_value = function(idxs, shift_side, value, hl_name, force)
	local width = nvim_strwidth(value)
	for i = 1, #idxs do
		local seg = Statusline[idxs[i]]
		local idx = side_idx(VALUE_SHIFT, shift_side)
		if force or not seg[idx] then
			seg[idx] = assign_highlight_name(value, hl_name)
			local strwidth_idx = side_idx(STRWIDTH_SHIFT, shift_side == "left" and -1 or 1)
			seg.total_width = (seg.total_width or 0) - (seg[strwidth_idx] or 0) + width
			seg[strwidth_idx] = width
		else
			return -- Do not overwrite existing value
		end
	end
end

--- Updates the click handler for a specific component.
--- @param idxs integer[] The index in the statusline of the component to update the click handler for.
--- @param click_handler string|nil The click handler to set for the specified component.
--- @param force boolean|nil If true, forces the update even if a click handler already exists.
M.set_click_handler = function(idxs, click_handler, force)
	for i = 1, #idxs do
		local seg = Statusline[idxs[i]]
		if force or not seg.click_handler_form then
			seg.click_handler_form = "%@v:lua." .. click_handler .. "@"
		else
			return -- Do not overwrite existing click handler
		end
	end
end

--- Determines if a buffer is disabled based on its filetype and buftype.
--- @param bufnr integer The buffer number to check.
--- @param disabled UserConfig.Disabled|nil The disabled configuration to check against. If nil, the buffer is not disabled.
--- @return boolean
M.is_buf_disabled = function(bufnr, disabled)
	if type(disabled) ~= "table" then
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
--- @param disabled_config UserConfig.Disabled|nil The disabled configuration to apply.
M.setup = function(disabled_config)
	--- For automatically rerender statusline on Vim or window resize when there are flexible components.
	local render_debounce = require("witch-line.utils").debounce(M.render, 100)
	if FlexiblePrioritySortedLen > 0 then
		api.nvim_create_autocmd({ "VimResized" }, {
			callback = function()
				render_debounce(o.columns)
			end,
		})
	end

	--- For automatically toggle `laststatus` based on buffer filetype and buftype.
	local user_laststatus = o.laststatus or 3

	api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
		callback = function(e)
			local bufnr = e.buf
			vim.schedule(function()
				if not api.nvim_buf_is_valid(bufnr) then
					return
				end

				local disabled = M.is_buf_disabled(bufnr, disabled_config)

				if not disabled and o.laststatus == 0 then
					api.nvim_set_option_value("laststatus", user_laststatus, {})
					render_debounce(o.columns) -- rerender statusline after enabling
				elseif disabled and o.laststatus ~= 0 then
					user_laststatus = o.laststatus
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
