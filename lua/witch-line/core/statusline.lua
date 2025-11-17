local bit = require("bit")
local bor, band, lshift = bit.bor, bit.band, bit.lshift

local vim, concat, type = vim, table.concat, type
local o, api = vim.o, vim.api
local nvim_strwidth, nvim_get_current_win = api.nvim_strwidth, api.nvim_get_current_win

local Highlight = require("witch-line.core.highlight")
local assign_highlight_name = Highlight.assign_highlight_name

local M = {}
-- Constants controlling the relative index positions for layout calculation.
-- These are typically used to determine horizontal shifts (e.g., for padding, borders, etc.)
---@type integer  Offset index for the left side.
local LEFT_SHIFT = -1
---@type integer  Offset index for the right side
local RIGHT_SHIFT = 1
---@type integer  Distance (gap) between consecutive shift indices.
local SHIFT_GAP = 3
---@type integer  Base offset applied to value computations.
local VALUE_SHIFT = 2
---@type integer  Derived offset for string width calculations
local WIDTH_SHIFT = VALUE_SHIFT + SHIFT_GAP

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

--- Represents a single segment within the statusline layout.
--- Each segment defines a visual or interactive element, such as text,
--- icons, or clickable areas.
---
--- The layout uses a system of indexed "shifts" to manage relative positions.
--- These indices determine where each visual property is stored and how
--- it aligns with neighboring segments:
---   - `VALUE_SHIFT` →  The main content area index.
---   - `WIDTH_SHIFT` →  The computed width of main value index.
---
--- Using these shift constants, the positions of the **left** and **right**
--- edges can be derived programmatically via:
---   - `left_idx(VALUE_SHIFT)`   → left boundary index
---   - `right_idx(VALUE_SHIFT)`  → right boundary index
---   - or dynamically with `side_idx(VALUE_SHIFT, -1 | 1)`
---
--- This structure allows fast spatial computation and efficient redraws,
--- since each segment’s positional indices can be updated arithmetically
--- without rebuilding layout tables.
--- @class CompState
--- @field [VALUE_SHIFT]? string The main content area index.
--- @field [WIDTH_SHIFT]? integer The computed width of main value index.
--- @field click_handler_form? string The name or ID of the click handler assigned to the segment (not cached).
--- @field total_width? integer The total rendered width of the segment (not cached).
--- @field flex? integer The priority of the flexible component.

--- @alias Statusline.CompId CompId|integer
--- @alias CompStateMap table<CompId, CompState>
--- @alias FlexSorted ({[1]: integer, [2]: CompId}[])
--- @alias Slots Statusline.CompId[]

--- @class Statusline
--- @field state_map CompStateMap The window-specific component state map.
--- @field slots Slots The list of components in the statusline.
--- @field flexs? FlexSorted The sorted list of flexible components.

--- Map: window_id -> (component_id -> CompState)
--- @type table<integer, Statusline>
local Statusline = {}

--- @type Statusline
local GlobalStatusline

--- @type integer # integer = literal component id
local LiteralCount = 0

--- Lazy-initialize global & per-window statusline state.
---
--- Summary:
---   - `Statusline[0]` = global default state.
---   - `Statusline[winid]` = per-window state that falls back to global.
---   - `state_map` (component states) is created per window; each entry
---       inherits from the global component defaults via metatable.
---   - Window state is created only when accessed.
---   - When a window closes, its state table is removed.
---
--- Structure:
---   Statusline = {
---     [0] = { state_map = {...}, slots = {...}, ... },
---     [win] = {
---       state_map = setmetatable({}, { __index = Statusline[0].state_map }),
---       slots = (fallback to global),
---       ...
---     },
---   }
---
--- Notes:
---   - Only global tables exist initially; per-window tables appear on demand.
---   - Component state uses shallow inheritance per window, but each component
---     merges from global defaults automatically.
local lazy_setup = function()
	GlobalStatusline = Statusline[0]
	if not GlobalStatusline then
		GlobalStatusline = {
			state_map = {},
			slots = {},
		}
		Statusline[0] = GlobalStatusline
	end

	local auid, state_map_mt = nil, nil
	setmetatable(Statusline, {
		__index = function(t, winid)
			local win_state = setmetatable({}, {
				__index = function(t1, key)
					--- Lazily create shared metatable for component state
					state_map_mt = state_map_mt or {
						__index = GlobalStatusline.state_map,
					}

					--- Each window has its own state map
					if key == "state_map" then
						local new = setmetatable({}, state_map_mt)
						t1[key] = new
						return new
					end
					return GlobalStatusline[key]
				end,
			})

			auid = auid
				or api.nvim_create_autocmd("WinClosed", {
					callback = function(e)
						Statusline[tonumber(e.match)] = nil
					end,
				})

			t[winid] = win_state
			return win_state
		end,
	})
end

--- Returns the window-level statusline state.
--- If `vim.o.laststatus` is 3, returns the global statusline state.
--- If `winid` is nil, returns the global statusline state.
--- If `winid` is 0, returns the global statusline state.
--- Otherwise, returns the per-window statusline state.
--- @param winid? integer Window ID to fetch. Defaults to current window.
--- @return Statusline state Window-level state table.
local get_statusline = function(winid)
	return (o.laststatus == 3 or winid == nil) and GlobalStatusline or Statusline[winid]
end

--- Ensure `statusline.slots` exists (lazy-create if missing).
--- @param statusline Statusline Window or global statusline state.
--- @return Slots slots The existing or newly created slots table.
local ensure_window_slots = function(statusline)
	local slots = rawget(statusline, "slots")
	if not slots then
		slots = {}
		statusline.slots = slots
	end
	return slots
end

--- Returns the sorted list of flexible components.
--- @param statusline Statusline The window state to fetch the sorted list from.
--- @return Statusline.CompId[] sorted The sorted list of flexible components.
local get_flex_sorted = function(statusline)
	-- use cached value
	local flex_sorted = statusline.flexs
	if flex_sorted then
		return flex_sorted
	end

	local sorted, n = {}, 0
	local comps, slots = statusline.state_map, statusline.slots
	for i = 1, #slots do
		local comp_id = slots[i]
		local flex = comps[comp_id].flex
		if flex then
			n = n + 1

			--- insertion sort by decreasing flex
			local l = n
			while l > 1 and flex > sorted[l - 1][1] do
				sorted[l] = sorted[l - 1]
				l = l - 1
			end
			sorted[l] = { flex, i, comp_id }
		end
	end

	flex_sorted = {}
	for i = 1, n do
		local e = sorted[i]
		flex_sorted[i] = { e[2], e[3] }
	end

	-- cache flexible_sorted
	statusline.flexs = flex_sorted
	return flex_sorted
end

--- Marks specific indices to be skipped during the merging process.
--- @param bitmasks integer The current bitmask representing indices to skip.
--- @param idx integer The index to mark for skipping.
--- @return integer new_mask The updated bitmask with the specified index marked for skipping.
local mark_bit = function(bitmasks, idx)
	return bor(bitmasks, lshift(1, idx - 1))
end

--- Checks if a specific index is marked to be skipped in the bitmask.
--- @param bitmasks integer The bitmask representing indices to skip.
--- @param idx integer The index to check for skipping.
--- @return boolean is_skipped True if the index is marked to be skipped, false otherwise.
local is_marked = function(bitmasks, idx)
	return band(bitmasks, lshift(1, idx - 1)) ~= 0
end

--- Tracks a component as flexible with a given priority.
--- Components with lower priority values are considered more important and will be retained longer when space is limited.
--- @param comp_id CompId The component ID of the flexible component.
--- @param priority integer The priority of the component; lower values indicate higher importance.
--- @param winid? integer The window ID to track the flexible component for.
M.track_flexible = function(comp_id, priority, winid)
	get_statusline(winid).state_map[comp_id].flex = priority
end

--- Inspects the current statusline values.
M.inspect = function()
	require("witch-line.utils.notifier").info(vim.inspect(Statusline))
end

--- Resets the value of a statusline component before caching.
--- @param state CompState The statusline component to reset.
local format_state_before_cache = function(state, frozen)
	local frozen_fields = {
		"flex",
		"idxs",
	}

	for k, _ in pairs(state) do
		if k == VALUE_SHIFT then
			if not frozen then
				state[k] = "" -- Clear unfrozen main value
			end
		elseif not vim.tbl_contains(frozen_fields, k) then
			state[k] = nil
		end
	end
end

--- Handles necessary operations before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for caching the statusline.
M.on_vim_leave_pre = function(CacheDataAccessor)
	-- Clear unfrozen values to reset statusline on next startup
	for key, value in pairs(GlobalStatusline.state_map) do
		format_state_before_cache(value, type(key) == "number")
	end
	CacheDataAccessor.set("GlobalStatusline", GlobalStatusline)
end

--- Loads the statusline cache.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for loading the statusline.
--- @return function undo function to restore the previous state
M.load_cache = function(CacheDataAccessor)
	Statusline[0] = CacheDataAccessor.get("GlobalStatusline")
	return function()
		Statusline[0] = nil
	end
end

--- Computes the total display width of a statusline component including its left and right parts.
--- This function caches the computed width to optimize performance.
--- @param comp_state CompState The statusline component to compute the width for.
--- @return integer width The total display width of the component including its left and right parts.
local compute_slot_width = function(comp_state)
	local width = comp_state.total_width
	if width then
		return width
	end
	width = comp_state[WIDTH_SHIFT] or 0
	if width > 0 then
		width = width + (comp_state[left_idx(WIDTH_SHIFT)] or 0) + (comp_state[right_idx(WIDTH_SHIFT)] or 0)
	end
	comp_state.total_width = width
	return width
end

--- Computes the total display width of all statusline components.
--- This function caches the computed widths to optimize performance.
--- @param win_state Statusline The window state to compute the width for.
--- @return integer total_width The total display width of all statusline components.
local compute_statusline_width = function(win_state)
	local total, slots, comps = 0, win_state.slots, win_state.state_map
	for i = 1, #slots do
		total = total + compute_slot_width(comps[slots[i]])
	end
	return total
end

--- Builds the final statusline string by merging highlight segments and optional
--- click-handler wrappers, while skipping any indices marked in a bitmask.
---
--- @param slots Slots The indices of the statusline components to build the value for.
--- @param state_map CompStateMap The statusline component to build the value for.
--- @param skip_mask? integer A bitmask (1-based indices) specifying which segments should be skipped. If nil, no skipping is applied.
--- @return string value Final concatenated statusline string.
local build_value = function(slots, state_map, skip_mask)
	skip_mask = skip_mask or 0ULL

	local out, n = {}, 0
	for i = 1, #slots do
		if not is_marked(skip_mask, i) then
			local state = state_map[slots[i]]
			local val = state[VALUE_SHIFT] or ""

			-- If no main value, skip the whole segment including its left and right parts
			if val ~= "" then
				local click_handler_form = state.click_handler_form
				if click_handler_form then
					n = n + 1
					out[n] = click_handler_form
				end

				local left, right = state[left_idx(VALUE_SHIFT)], state[right_idx(VALUE_SHIFT)]
				if left and left ~= "" then
					n = n + 1
					out[n] = left
				end

				--- Main part
				n = n + 1
				out[n] = val

				--- Right part
				if right and right ~= "" then
					n = n + 1
					out[n] = right
				end

				if click_handler_form then
					n = n + 1
					out[n] = "%X"
				end
			end
		end
	end
	local result = concat(out)
	return result ~= "" and result or " "
end

--- Renders the statusline by concatenating all component values and setting it to `o.statusline`.
--- If the statusline is disabled, it sets `o.statusline` to a single space.
--- @param winid? integer The window ID to render the statusline for.
M.render = function(winid)
	local laststatus = o.laststatus
	if
		(winid and not api.nvim_win_is_valid(winid))
		or laststatus == 0
		or (laststatus == 1 and #api.nvim_tabpage_list_wins(0) < 2)
	then
		-- statusline is hidden no need to render
		return
	end

	local statusline, opt = GlobalStatusline, vim.o
	if laststatus ~= 3 then
		winid = winid or nvim_get_current_win()
		statusline, opt = get_statusline(winid), vim.wo[winid]
	end

	local comp_state = statusline.state_map

	local flex_list = get_flex_sorted(statusline)
	local current_flex = flex_list[1]

	if not current_flex then
		opt.statusline = build_value(statusline.slots, comp_state)
		return
	end

	-- Bitmask describing which slots should be hidden
	local hidden_slots = 0ULL

	-- Total width of current statusline
	local rendered_width = compute_statusline_width(statusline)

	-- Allowed width of window or entire screen
	local max_width = winid and api.nvim_win_get_width(winid) or o.columns

	-- Iterate through flexible components, hiding them one by one
	-- until the statusline fits the max width.
	local flex_idx = 1

	while current_flex and rendered_width > max_width do
		local slot_id, comp_id = current_flex[1], current_flex[2]
		hidden_slots = mark_bit(hidden_slots, slot_id)
		rendered_width = rendered_width - compute_slot_width(comp_state[comp_id])
		flex_idx = flex_idx + 1
		current_flex = flex_list[flex_idx]
	end

	opt.statusline = build_value(statusline.slots, comp_state, hidden_slots)
end

--- Appends a new value to the statusline values list.
--- @param comp_id? CompId The component ID. Nil means it is a literal component
--- @param value string The value to append.
--- @param winid? integer The window ID to set the value for.
--- @return integer new_idx The index of the newly added value.
M.push = function(comp_id, value, winid)
	local statusline = winid and Statusline[winid] or GlobalStatusline
	-- local statusline = get_statusline(winid)
	local slots = ensure_window_slots(statusline)

	local new_slots_size = #slots + 1

	if not comp_id then
		LiteralCount = LiteralCount + 1
		---@diagnostic disable-next-line: cast-local-type
		comp_id = LiteralCount
	end

	--- Rawget to avoid automatically creating the table
	local state_map = statusline.state_map
	local state = rawget(state_map, comp_id)
	if not state then
		local width = value == "" and 0 or nvim_strwidth(value)
		--- @type CompState
		state_map[comp_id] = {
			[VALUE_SHIFT] = value,
			[WIDTH_SHIFT] = width,
			total_width = width,
		}
	end
	slots[new_slots_size] = comp_id
	return new_slots_size
end

--- Ensures that a specific component state exists.
--- @param winid? integer The window ID to set the value for.
--- @param comp_id CompId The component ID to ensure.
--- @return CompState state The existing or newly created component state.
local ensure_comp_state = function(winid, comp_id)
	local state_map = get_statusline(winid).state_map
	local state = rawget(state_map, comp_id) or {}
	state_map[comp_id] = state
	return state
end

--- Hides a specific component by setting its value to an empty string.
--- @param comp_id CompId The index of the component to hide.
--- @param winid? integer The window ID to set the value for.
M.hide_segment = function(comp_id, winid)
	local state = ensure_comp_state(winid, comp_id)
	state[VALUE_SHIFT] = ""
	state[WIDTH_SHIFT], state.total_width = 0, nil
end

--- Sets the value for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param value string The value to set for the specified side.
--- @param hl_name? string The highlight group name to set for segment.
--- @param winid? integer The window ID to set the value for.
M.set_value = function(comp_id, value, hl_name, winid)
	local state = ensure_comp_state(winid, comp_id)
	state[WIDTH_SHIFT], state.total_width = nvim_strwidth(value), nil
	state[VALUE_SHIFT] = assign_highlight_name(value, hl_name)
end

--- Sets the highlight_name for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param new_hl_name string|nil The new highlight group name to set for the segment.
--- @param winid? integer The window ID to set the value for.
M.set_hl_name = function(comp_id, new_hl_name, winid)
	local state = ensure_comp_state(winid, comp_id)
	local curr_value = state[VALUE_SHIFT]
	state[VALUE_SHIFT] = curr_value and Highlight.replace_highlight_name(curr_value, new_hl_name, 1) or curr_value
end

--- Sets the left or right side value for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param shift_side -1|1 The shift side value to get the side idx. 1 Right, -1 Left
--- @param value string The value to set for the specified side.
--- @param hl_name? string The highlight group name to set for the specified side.
--- @param force? boolean If true, forces the update even if a value already exists for the specified side.
--- @param winid? integer The window ID to set the value for.
M.set_side_value = function(comp_id, shift_side, value, hl_name, force, winid)
	local state = ensure_comp_state(winid, comp_id)
	local vidx = side_idx(VALUE_SHIFT, shift_side)
	if force or not state[vidx] then
		state[side_idx(WIDTH_SHIFT, shift_side)], state.total_width = nvim_strwidth(value), nil
		state[vidx] = assign_highlight_name(value, hl_name)
	end
end

--- Sets the left or right side value for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param shift_side -1|1 The shift side value to get the side idx. 1 Right, -1 Left
--- @param new_hl_name? string The new highlight group name to set for the specified side.
--- @param winid? integer The window ID to set the value for.
M.set_side_hl_name = function(comp_id, shift_side, new_hl_name, winid)
	local state = ensure_comp_state(winid, comp_id)
	local idx = side_idx(VALUE_SHIFT, shift_side)
	local curr_value = state[idx]
	state[idx] = curr_value and Highlight.replace_highlight_name(curr_value, new_hl_name, 1) or curr_value
end

--- Updates the click handler for a specific component.
--- @param comp_id CompId The index in the statusline of the component to update the click handler for.
--- @param click_handler string The click handler to set for the specified component.
--- @param force? boolean If true, forces the update even if a click handler already exists.
--- @param winid? integer The window ID to set the value for.
M.set_click_handler = function(comp_id, click_handler, force, winid)
	local state = ensure_comp_state(winid, comp_id)
	if force or not state.click_handler_form then
		state.click_handler_form = "%@v:lua." .. click_handler .. "@"
	end
end

--- Setup the necessary things for statusline rendering.
--- @param disabled_opts? UserConfig.Disabled The disabled configuration to apply.
M.setup = function(disabled_opts)
	lazy_setup()

	--- For automatically rerender statusline on Vim or window resize when there are flexible components.
	local render_debounce = require("witch-line.utils").debounce(M.render, 100)
	api.nvim_create_autocmd("VimResized", {
		callback = function()
			local flexs = get_statusline(nvim_get_current_win()).flexs
			if flexs and #flexs > 0 then
				render_debounce()
			end
		end,
	})

	if type(disabled_opts) == "table" then
		local disabled_filetypes = type(disabled_opts.filetypes) == "table" and disabled_opts.filetypes
		local disabled_buftypes = type(disabled_opts.buftypes) == "table" and disabled_opts.buftypes

		if disabled_buftypes or disabled_filetypes then
			local bo = vim.bo
			--- Determines if a buffer is disabled based on its filetype and buftype.
			--- @param bufnr integer The buffer number to check.
			--- @return boolean disabled True if the buffer is disabled, false otherwise.
			local is_buf_disabled = function(bufnr)
				local buf_o = bo[bufnr]
				return (disabled_filetypes and vim.list_contains(disabled_filetypes, buf_o.filetype))
					or (disabled_buftypes and vim.list_contains(disabled_buftypes, buf_o.buftype))
					or false
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

						local disabled = is_buf_disabled(bufnr)

						if not disabled and o.laststatus == 0 then
							api.nvim_set_option_value("laststatus", user_laststatus, {})
							render_debounce() -- rerender statusline after enabling
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
	end
end

return M
