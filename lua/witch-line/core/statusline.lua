local ffi = require("ffi")
ffi.cdef[[
  size_t mb_string2cells_len(const char *str, size_t size)
]]
local vim, concat, type, ipairs = vim, table.concat, type, ipairs
local o, bo, api, mb_string2cells_len = vim.o, vim.bo, vim.api, ffi.C.mb_string2cells_len


local M = {}


--- @alias IdxValue 1
local IDX_VALUE = 1
--- @alias IdxValue.Left 0
local IDX_VALUE_LEFT,
--- @alias IdxValue.Right 2
      IDX_VALUE_RIGHT
        = IDX_VALUE - 1,
          IDX_VALUE + 1

--- @alias IdxHL 4
--- @alias IdxHL.Left 3
--- @alias IdxHL.Right 5
local IDX_HL = IDX_VALUE + 3

--- @alias IdxMergedHLValue 7
--- @alias IdxMergedHLValue.Left 6
--- @alias IdxMergedHLValue.Right 8
local IDX_MERGED_HL_VAL = IDX_HL + 3


--- @class Segment A statusline component segment.
--- @field [IdxValue.Left] string|nil The left value of the component.
--- @field [IdxValue] string The main value of the component.
--- @field [IdxValue.Right] string|nil The right value of the component.
--- @field [IdxHL.Left] string|nil The highlight group name for the left value of the component.
--- @field [IdxHL] string|nil The highlight group name for the main value of the component.
--- @field [IdxHL.Right] string|nil The highlight group name for the right value of the component.
--- @field [IdxMergedHLValue.Left] string|nil The cached merged left value with highlight group name. ( Not be cached )
--- @field [IdxMergedHLValue] string|nil The cached merged main value with highlight group name. ( Not be cached )
--- @field [IdxMergedHLValue.Right] string|nil The cached merged right value with highlight group name. ( Not be cached )
--- @field frozen true|nil If true, the part is frozen and will not be cleared on Vim exit.
--- @field click_handler_form string|nil The click handler for the component. ( Not be cached )
---
--- @private cached fields:
--- @field _total_display_width? integer|nil The cached total display width of the component including its left and right parts. ( Not be cached )

local Disabled = false

--- @type Segment[] The list of statusline components.
local Statusline = {
  -- { [VALUE_KEY] = "value", -- main value
  --   [VALUE_KEY - 1] = "left", -- left valuel
  --   [VALUE_KEY + 1] = "right", -- right value
  --   [HL_NAME_KEY] = "HighlightGroup", -- main highlight group name
  --   [HL_NAME_KEY - 1] = "LeftHighlightGroup", -- left highlight group name
  --   [HL_NAME_KEY + 1] = "RightHighlightGroup", -- right highlight group name
  --   frozen = true, -- if true, the value will not be cleared on Vim exit
  --   click_handler = "ClickHandler", -- click handler
  --   _cached_total_display_width = 10, -- cached total display width of the component including its left and right parts
  --   [MERGED_HL_VALUE] = "%#HighlightGroup#value", -- cached merged main value with highlight group name
  --   [MERGED_HL_VALUE - 1] = "%#LeftHighlightGroup#left", -- cached merged left value with highlight group name
  --   [MERGED_HL_VALUE + 1] = "%#RightHighlightGroup#right", -- cached merged right value with highlight group name
  --  }
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
  elseif t == "statusline_readable" then
    local new = {}
    for i = 1, ValuesSize do
      local seg = Statusline[i]
      new[i] = {
        value = seg[IDX_VALUE],
        left = seg[IDX_VALUE - 1],
        right = seg[IDX_VALUE + 1],
        hl = seg[IDX_HL],
        hl_left = seg[IDX_HL - 1],
        hl_right = seg[IDX_HL + 1],
        merged_hl_value = seg[IDX_MERGED_HL_VAL],
        merged_hl_value_left = seg[IDX_MERGED_HL_VAL - 1],
        merged_hl_value_right = seg[IDX_MERGED_HL_VAL + 1],
        frozen = seg.frozen,
        click_handler = seg.click_handler_form,
        _total_display_width = seg._total_display_width,
      }
    end
    notifier.info(vim.inspect(new))
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
      and k ~= IDX_VALUE_LEFT
      and k ~= IDX_VALUE_RIGHT
    then
      if k == IDX_VALUE  then
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

      local val = seg[IDX_VALUE]
      -- If no main value, skip the whole segment including its left and right parts
      if val ~= "" then
        local click_handler_form = seg.click_handler_form
        if click_handler_form then
          n = n + 1
          values[n] = click_handler_form
        end


        local hl_value, hl
        local left, right = seg[IDX_VALUE - 1], seg[IDX_VALUE + 1]
        if left and left ~= "" then
          hl_value = seg[IDX_MERGED_HL_VAL - 1]
          if hl_value then
            n = n + 1
            values[n] = hl_value
          else
            hl = seg[IDX_HL - 1]
            hl_value = hl and assign_highlight_name(left, hl) or left
            n = n + 1
            values[n], seg[IDX_MERGED_HL_VAL - 1] = hl_value, hl_value
          end
        end

        -- Main part
        hl_value = seg[IDX_MERGED_HL_VAL]
        if hl_value then
          n = n + 1
          values[n] = hl_value
        else
          hl = seg[IDX_HL]
          hl_value = hl and assign_highlight_name(val, hl) or val
          n = n + 1
          values[n], seg[IDX_MERGED_HL_VAL] = hl_value, hl_value
        end

        if right and right ~= "" then
          hl_value = seg[IDX_MERGED_HL_VAL + 1]
          if hl_value then
            n = n + 1
            values[n] = hl_value
          else
            hl = seg[IDX_HL + 1]
            hl_value = hl and assign_highlight_name(right, hl) or right
            n = n + 1
            values[n], seg[IDX_MERGED_HL_VAL + 1] = hl_value, hl_value
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

  local value = segment[IDX_VALUE]
  width = value ~= "" and mb_string2cells_len(value, #value) or 0
  if width ~= 0 then
    local left, right = segment[IDX_VALUE_LEFT], segment[IDX_VALUE_RIGHT]
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
    local segment = Statusline[idxs[i]]
    segment[IDX_VALUE] ,segment._total_display_width = "", 0
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
--- @param frozen boolean|nil If true, the value is marked as frozen and will not be cleared on Vim exit.
--- @return integer new_idx The index of the newly added value.
M.push = function(value, frozen)
	ValuesSize = ValuesSize + 1

  --- @type Segment
  Statusline[ValuesSize] = {
    [IDX_VALUE] = value ,
    frozen = frozen,
  }
	return ValuesSize
end


--- Sets the value for a specific component.
--- @param idxs integer[] The index of the component to set the value for.
--- @param hl_name string|nil The highlight group name to assign to the specified component.
M.set_value_highlight = function(idxs, hl_name, force)
  for i = 1, #idxs do
    local seg = Statusline[idxs[i]]
    if force or not seg[IDX_HL] then
      seg[IDX_HL], seg[IDX_MERGED_HL_VAL] = hl_name, nil
    else
      return -- Do not overwrite existing highlight
    end
  end
end

--- Updates the highlight group name for the left or right side of a specific component.
--- @param idxs integer[] The index of the component to update the side highlight for.
--- @param side Side The side to set the highlight for. Use 1 for right and -1 for left.
--- @param hl_name string|nil The highlight group name to set for the specified side.
M.set_side_value_highlight = function(idxs, side, hl_name, force)
  local hl_key, merged_hl_key  = IDX_HL + side, IDX_MERGED_HL_VAL + side
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
    seg[IDX_VALUE] , seg[IDX_MERGED_HL_VAL], seg._total_display_width = value, nil, nil
  end
end

--- Sets the left or right side value for a specific component.
--- @param idxs integer|integer[] The index of the component to set the side value for.
--- @param side Side The side to set the value for. Use 1 for right and -1 for left.
--- @param value string The value to set for the specified side.
--- @param force boolean|nil If true, forces the update even if a value already exists for the specified side.
M.set_side_value = function(idxs, side, value, force)
  for i = 1, #idxs do
    local seg = Statusline[idxs[i]]
    local val = seg[IDX_VALUE + side]
    if force or not val then
      seg[IDX_VALUE + side], seg[IDX_MERGED_HL_VAL + side], seg._total_display_width = value, nil, nil
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
