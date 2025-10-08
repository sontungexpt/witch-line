local vim, concat, type, ipairs = vim, table.concat, type, ipairs
local o, bo, api= vim.o, vim.bo, vim.api
local ffi = require("ffi")

ffi.cdef[[
  size_t mb_string2cells_len(const char *str, size_t size)
]]
local mb_string2cells_len = ffi.C.mb_string2cells_len


local M = {}

--- @class Segment A statusline component segment.
--- @field value string The render value of the part. ( Empty when cached if not frozen )
--- @field hl_name string|nil The highlight group name of the part. ( Not be cached )
--- @field left string|nil The main part of the component.
--- @field left_hl_name string|nil The highlight group name of the left part. ( Not be cached )
--- @field right string|nil The right part of the component.
--- @field right_hl_name string|nil The highlight group name of the right part. ( Not be cached )
--- @field frozen true|nil If true, the part is frozen and will not be cleared on Vim exit.
--- @field click_handler string|nil The click handler for the component. ( Not be cached )
---
--- @private cached fields:
--- @field _cached_total_display_width? integer|nil The cached total display width of the component including its left and right parts. ( Not be cached )
--- @field _cached_highlighted_value? string|nil The cached merged value with highlight group name. ( Not be cached )
--- @field _cached_left_highlighted_value? string|nil The cached merged left value with highlight group name. ( Not be cached )
--- @field _cached_right_highlighted_value? string|nil The cached merged right value with highlight group name. ( Not be cached )
---

local Disabled = false

--- @type Segment[] The list of statusline components.
local Statusline = {
  -- { value = "", hl_name = nil, left = nil, left_hl_name = nil, right = nil, right_hl_name = nil, frozen = false, click_handler = nil },
  -- { value = "", hl_name = nil, left = nil, left_hl_name = nil, right = nil, right_hl_name = nil, frozen = false, click_handler = nil },
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
local format_state_before_cache = function (segment)
  if not segment.frozen then
    segment.value = ""
    segment._cached_total_display_width = nil
  end
  segment.hl_name = nil

  segment.left = nil
  segment.left_hl_name = nil

  segment.right = nil
  segment.right_hl_name = nil

  segment.click_handler = nil

  segment._cached_highlighted_value = nil
  segment._cached_left_highlighted_value = nil
  segment._cached_right_highlighted_value = nil
end

--- Handles necessary operations before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for caching the statusline.
M.on_vim_leave_pre = function(CacheDataAccessor)
	-- Clear unfrozen values to reset statusline on next startup
  M.iterate_values(function(idx, segment)
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
    Statusline,
    ValuesSize,
    FlexiblePrioritySorted,
    FlexiblePrioritySortedLen

	Statusline = CacheDataAccessor.get("Statusline") or Statusline
	ValuesSize = CacheDataAccessor.get("StatuslineSize") or ValuesSize
	FlexiblePrioritySorted = CacheDataAccessor.get("FlexiblePrioritySorted") or FlexiblePrioritySorted
	FlexiblePrioritySortedLen = CacheDataAccessor.get("FlexiblePrioritySortedLen") or FlexiblePrioritySortedLen

	return function()
		Statusline = before_values
		ValuesSize = before_values_size
		FlexiblePrioritySorted = before_flexible_priority_sorted
		FlexiblePrioritySortedLen = before_flexible_priority_sorted_len
	end
end

--- Merges the highlight group names with the corresponding statusline values.
--- @param skip table<integer, true>| nil An optinal set of indices to skip during merging
--- @return string[] merged The merged list of statusline values with highlight group names applied.
local function build_values(skip)
	--- Lazy load
	local assign_highlight_name = require("witch-line.core.highlight").assign_highlight_name
  local values, n = {}, 0

	for i = 1, ValuesSize do
		if not skip or not skip[i] then
      local seg = Statusline[i]
      local click_handler = seg.click_handler
      if click_handler then
        n = n + 1
        values[n] = "%@" .. click_handler .. "@"
      end

      if seg._cached_left_highlighted_value then
        n = n + 1
        values[n] = seg._cached_left_highlighted_value
      elseif seg.left then
        local left, left_hl = seg.left, seg.left_hl_name
        if left ~= "" then
          n = n + 1
          values[n] = left_hl and assign_highlight_name(left, left_hl) or left
          seg._cached_left_highlighted_value = values[n]
        end
      end

      if seg._cached_highlighted_value then
        n = n + 1
        values[n] = seg._cached_highlighted_value
      else
        local val, hl = seg.value, seg.hl_name
        if val ~= "" then
          n = n + 1
          values[n] = hl and assign_highlight_name(val, hl) or val
          seg._cached_highlighted_value = values[n]
        end
      end

      if seg._cached_right_highlighted_value then
        n = n + 1
        values[n] = seg._cached_right_highlighted_value
      elseif seg.right then
        local right, right_hl = seg.right, seg.right_hl_name
        if right ~= "" then
          n = n + 1
          values[n] = right_hl and assign_highlight_name(right, right_hl) or right
          seg._cached_right_highlighted_value = values[n]
        end
      end

      if click_handler then
        n = n + 1
        values[n] = "%X"
      end
		end
	end
	return values
end


--- Computes the total display width of a statusline component including its left and right parts.
--- This function caches the computed width to optimize performance.
--- @param segment Segment The statusline component to compute the width for.
--- @return integer width The total display width of the component including its left and right parts.
local compute_segment_width = function (segment)
  local width = segment._cached_total_display_width
  if width then return width end

  local left, value, right = segment.left, segment.value, segment.right
  width = (left and mb_string2cells_len(left, #left) or 0)
    + mb_string2cells_len(value, #value) + (right and mb_string2cells_len(right, #right) or 0)
  segment._cached_total_display_width = width
  return width
end
M.compute_segment_width = compute_segment_width

--- Computes the total display width of all statusline components.
--- This function caches the computed widths to optimize performance.
--- @return integer total_width The total display width of all statusline components.
local compute_statusline_width = function ()
  local total_width = 0
  for i = 1, ValuesSize do
    total_width = total_width + compute_segment_width(Statusline[i])
  end
  return total_width
end
M.compute_statusline_width = compute_statusline_width

--- Renders the statusline by concatenating all component values and setting it to `o.statusline`.
--- If the statusline is disabled, it sets `o.statusline` to a single space.
--- @param max_width integer|nil The maximum width for the statusline. Defaults to vim.o.columns if not provided.
M.render = function(max_width)
  if Disabled then
    return
  elseif FlexiblePrioritySortedLen == 0 then
		local str = concat(build_values())
		o.statusline = str ~= "" and str or " "
		return
	end

	--- @type table<integer, true>
	local hidden_idxs = {}
	local removed_idx = FlexiblePrioritySortedLen
	local truncated_len = compute_statusline_width()

	max_width = max_width or o.columns
	while removed_idx > 0 and truncated_len > max_width do
		local value_idx = FlexiblePrioritySorted[removed_idx].idx
    hidden_idxs[value_idx] = true
    truncated_len = truncated_len - compute_segment_width(Statusline[value_idx])
		removed_idx = removed_idx - 1
	end
	local str = concat(build_values(hidden_idxs))
	o.statusline = str ~= "" and str or " "
end


--- Appends a new value to the statusline values list.
--- @param value string The value to append.
--- @param left_value string|nil The left side value of the component.
--- @param right_value string|nil The right side value of the component.
--- @param frozen boolean|nil If true, the value is marked as frozen and will not be cleared on Vim exit.
--- @return integer new_idx The index of the newly added value.
M.push = function(value, left_value, right_value, frozen)
	ValuesSize = ValuesSize + 1
  --- @type Segment
  Statusline[ValuesSize] = {
    value = value,
    left = left_value,
    right = right_value,
    frozen = frozen,
  }
	return ValuesSize
end

--- Sets the value for a specific component.
--- @param idxs integer[] The index of the component to set the value for.
--- @param value string The value to set for the specified component.
--- @param hl_name string|nil The highlight group name to assign to the specified component.
M.bulk_set = function(idxs, value, hl_name)
  for i = 1, #idxs do
    local segment = Statusline[idxs[i]]
    segment.value, segment.hl_name, segment._cached_highlighted_value, segment._cached_total_display_width = value, hl_name, nil, nil
  end
end

--- Sets the left or right side value for a specific component.
--- @param idxs integer[] The index of the component to set the side value for.
--- @param side "left"|"right" The side to set the value for.
--- @param value string The value to set for the specified side.
--- @param hl_name string|nil The highlight group name to assign to the specified side.
M.bulk_set_side = function(idxs, side, value, hl_name)
  if type(idxs) == "table" then
    for i = 1, #idxs do
      local segment = Statusline[idxs[i]]
      if side == "left" then
        segment.left, segment.left_hl_name, segment._cached_left_highlighted_value = value, hl_name, nil
      elseif side == "right" then
        segment.right, segment.right_hl_name, segment._cached_right_highlighted_value = value, hl_name, nil
      else
        error("Invalid side: " .. tostring(side) .. ". Expected 'left' or 'right'.")
        return
      end
      segment._cached_total_display_width = nil
    end
    return
  end
end


--- Updates the click handler for a specific component.
--- @param idxs integer[] The index of the component to update the click handler for.
--- @param click_handler string|nil The click handler to set for the specified component.
M.bulk_set_click_handler = function(idxs, click_handler)
  for i = 1, #idxs do
    local segment = Statusline[idxs[i]]
    segment.click_handler = click_handler
  end
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
	if FlexiblePrioritySortedLen > 0 then
		local render_debounce = require("witch-line.utils").debounce(M.render, 100)
		api.nvim_create_autocmd({ "VimResized" }, {
			callback = function()
				render_debounce(o.columns)
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
				Disabled = M.is_buf_disabled(buf, disabled_config)

				if not Disabled and o.laststatus == 0 then
					api.nvim_set_option_value("laststatus", user_laststatus, {})
					M.render() -- rerender statusline immediately
				elseif Disabled and o.laststatus ~= 0 then
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
