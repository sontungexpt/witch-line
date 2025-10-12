local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
  size_t mb_string2cells_len(const char *str, size_t size)
]]

local vim, concat, type, ipairs, mb_string2cells_len  = vim, table.concat, type, ipairs, ffi.C.mb_string2cells_len
local o, bo, api = vim.o, vim.bo, vim.api
local bor, band, lshift = bit.bor, bit.band, bit.lshift

local M = {}

--- @class Segment A statusline component segment.
--- @field value string The main value of the component.
--- @field hl string|nil The highlight group name for the main value of the component.
--- @field left string|nil The left value of the component.
--- @field left_hl string|nil The highlight group name for the left value of the component.
--- @field right string|nil The right value of the component.
--- @field right_hl string|nil The highlight group name for the main value of the component.
--- @field frozen true|nil If true, the part is frozen and will not be cleared on Vim exit.
--- @field click_handler_form string|nil The click handler for the component. ( Not be cached )
---
--- @private cached fields:
--- @field _total_display_width? integer|nil The cached total display width of the component including its left and right parts. ( Not be cached )
--- @field _merged_hl_value string|nil The cached merged main value with highlight group name. ( Not be cached )
--- @field _merged_hl_value_left string|nil The cached merged left value with highlight group name. ( Not be cached )
--- @field _merged_hl_value_right string|nil The cached merged right value with highlight group name. ( Not be cached )

local Disabled = o.laststatus == 0

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
local format_state_before_cache = function (segment)
  for k, v in pairs(segment) do
    if k ~= "frozen"
      and k ~= "click_handler_form"
      and k ~= "left"
      and k ~= "right"
    then
      if k == "value"  then
        if not segment.frozen then
          segment[k] = ""  -- Clear unfrozen main value
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
    Statusline, ValuesSize, FlexiblePrioritySorted, FlexiblePrioritySortedLen =
      before_values,
      before_values_size,
      before_flexible_priority_sorted,
      before_flexible_priority_sorted_len
	end
end

--- Marks specific indices to be skipped during the merging process.
--- @param bitmasks integer The current bitmask representing indices to skip.
--- @param idx integer The index to mark for skipping.
--- @return integer new_mask The updated bitmask with the specified index marked for skipping.
local skip = function (bitmasks, idx)
  return bor(bitmasks, lshift(1, idx - 1))
end

--- Checks if a specific index is marked to be skipped in the bitmask.
--- @param bitmasks integer The bitmask representing indices to skip.
--- @param idx integer The index to check for skipping.
--- @return boolean is_skipped True if the index is marked to be skipped, false otherwise.
local is_skipped = function (bitmasks, idx)
  return band(bitmasks, lshift(1, idx - 1)) ~= 0
end

--- Merges the highlight group names with the corresponding statusline values.
--- @param skip_bitmasks integer|nil A bitmask representing indices to skip during the merging process (1-based index). If nil, no indices are skipped.
--- @return string[] merged The merged list of statusline values with highlight group names applied.
local function build_values(skip_bitmasks)
  skip_bitmasks = skip_bitmasks or 0

	--- Lazy load
	local assign_highlight_name = require("witch-line.core.highlight").assign_highlight_name
  local values, n = {}, 0

	for i = 1, ValuesSize do
		if not is_skipped(skip_bitmasks, i) then
      local seg = Statusline[i]

      local val = seg.value
      -- If no main value, skip the whole segment including its left and right parts
      if val ~= "" then
        local click_handler_form = seg.click_handler_form
        if click_handler_form then
          n = n + 1
          values[n] = click_handler_form
        end


        local merged_hl_val
        local left, right = seg.left, seg.right
        if left and left ~= "" then
          n = n + 1
          merged_hl_val = seg._merged_hl_value_left
          if merged_hl_val then
            values[n] = merged_hl_val
          else
            merged_hl_val = assign_highlight_name(left, seg.left_hl)
            values[n], seg._merged_hl_value_left = merged_hl_val, merged_hl_val
          end
        end

        --- Main part
        n = n + 1
        merged_hl_val = seg._merged_hl_value
        if merged_hl_val then
          values[n] = merged_hl_val
        else
          merged_hl_val = assign_highlight_name(val, seg.hl)
          values[n], seg._merged_hl_value = merged_hl_val, merged_hl_val
        end

        --- Right part
        if right and right ~= "" then
          n = n + 1
          merged_hl_val = seg._merged_hl_value_right
          if merged_hl_val then
            values[n] = merged_hl_val
          else
            merged_hl_val = assign_highlight_name(right, seg.right_hl)
            values[n], seg._merged_hl_value_right = merged_hl_val, merged_hl_val
          end
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
--- @param segment Segment The statusline component to compute the width for.
--- @return integer width The total display width of the component including its left and right parts.
local compute_segment_width = function (segment)
  local width = segment._total_display_width
  if width then return width end

  local value = segment.value
  width = value ~= "" and mb_string2cells_len(value, #value) or 0
  if width ~= 0 then
    local left, right = segment.left, segment.right
    if left then
      width = width + mb_string2cells_len(left, #left)
    end
    if right then
      width = width + mb_string2cells_len(right, #right)
    end
  end
  segment._total_display_width = width
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

--- Hides a specific component by setting its value to an empty string.
--- @param idxs integer[] The index of the component to hide.
M.hide_segment = function(idxs)
  for i = 1, #idxs do
    local seg = Statusline[idxs[i]]
    seg.value, seg._total_display_width, seg._merged_hl_value = "", nil, nil
  end
end


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

  --- @type Segment
  Statusline[ValuesSize] = {
    value = value,
    frozen = frozen,
  }
	return ValuesSize
end


--- Sets the value for a specific component.
--- @param idxs integer[] The index of the component to set the value for.
--- @param hl_name string|nil The highlight group name to assign to the specified component.
--- @param force boolean|nil If true, forces the update even if a highlight group name already exists.
M.set_value_highlight = function(idxs, hl_name, force)
  for i = 1, #idxs do
    local seg = Statusline[idxs[i]]
    local hl = seg.hl
    if force or not hl then
      seg.hl, seg._merged_hl_value = hl_name, nil
    else
      return -- Do not overwrite existing highlight
    end
  end
end

--- Updates the highlight group name for the left or right side of a specific component.
--- @param idxs integer[] The index of the component to update the side highlight for.
--- @param side "left"|"right" The side to set the highlight for. Use "left" for left and "right" for right.
--- @param hl_name string|nil The highlight group name to set for the specified side.
--- @param force boolean|nil If true, forces the update even if a highlight group name already exists for the specified side.
M.set_side_value_highlight = function(idxs, side, hl_name, force)
  local hl_key, merged_hl_key
  if side == "left" then
    hl_key, merged_hl_key = "left_hl", "_merged_hl_value_left"
  elseif side == "right" then
    hl_key, merged_hl_key = "right_hl", "_merged_hl_value_right"
  else
    error("Invalid side: " .. tostring(side) .. ". Use 'left' or 'right'.")
  end

  for i = 1, #idxs do
    local seg = Statusline[idxs[i]]
    if force or not seg[hl_key] then
      seg[hl_key], seg[merged_hl_key] = hl_name, nil
    else
      return -- Do not overwrite existing highlight
    end
  end
end
--- Sets the value for a specific component.
--- @param idxs integer|integer[] The index of the component to set the side value for.
--- @param value string The value to set for the specified side.
M.set_value = function(idxs, value)
  for i = 1, #idxs do
   local seg = Statusline[idxs[i]]
    seg.value, seg._merged_hl_value, seg._total_display_width = value, nil, nil
  end
end

--- Sets the left or right side value for a specific component.
--- @param idxs integer|integer[] The index of the component to set the side value for.
--- @param side "left"|"right" The side to set the value for. Use "left" for left and "right" for right.
--- @param value string The value to set for the specified side.
--- @param force boolean|nil If true, forces the update even if a value already exists for the specified side.
M.set_side_value = function(idxs, side, value, force)
  local key, merged_key
  if side == "left" then
    key, merged_key = "left", "_merged_hl_value_left"
  elseif side == "right" then
    key, merged_key = "right", "_merged_hl_value_right"
  else
    error("Invalid side: " .. tostring(side) .. ". Use 'left' or 'right'.")
  end

  for i = 1, #idxs do
    local seg = Statusline[idxs[i]]
    if force or not seg[key] then
      seg[key], seg[merged_key], seg._total_display_width = value, nil, nil
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
      seg.click_handler_form = "%@" .. click_handler .. "@"
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
			local bufnr = e.buf
			vim.schedule(function()
        if not api.nvim_buf_is_valid(bufnr) then
          return
        end

				Disabled = M.is_buf_disabled(bufnr, disabled_config)

				if not Disabled and o.laststatus == 0 then
					api.nvim_set_option_value("laststatus", user_laststatus, {})
          render_debounce(o.columns) -- rerender statusline after enabling
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
