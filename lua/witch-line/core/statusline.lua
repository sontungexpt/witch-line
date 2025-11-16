local bit = require("bit")
local bor, band, lshift = bit.bor, bit.band, bit.lshift

local vim, concat, type, ipairs = vim, table.concat, type, ipairs
local o, bo, api = vim.o, vim.bo, vim.api
local nvim_strwidth = api.nvim_strwidth
local Highlight = require("witch-line.core.highlight")
local assign_highlight_name = Highlight.assign_highlight_name
local replace_highlight_name = Highlight.replace_highlight_name

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

--- @class StatuslineCompId : CompId|integer

--- @class StatuslineState
--- @field comp_state table<StatuslineCompId, CompState> The window-specific component state map.
--- @field slots StatuslineCompId[] The list of components in the statusline.
--- @field flexible_sorted? ({[1]: integer, [2]: CompId})[] The sorted list of flexible components.

--- Map: window_id -> (component_id -> CompState)
--- @type table<integer, StatuslineState>
local StatuslineState = {}

--- @type StatuslineState
local GlobalStatuslineState

--- @type integer # integer = literal component id
local LiteralCount = 0

--- Lazy-initializes the global and per-window statusline state tables.
---
--- Behavior summary:
---   - `StatuslineState` is a map: winid → window-state table.
---   - Window 0 stores the **global default state**.
---   - Each window inherits all fields from the global state, except
---     `comp_state`, which is a component-state map (comp_id → state).
---   - Component state is lazily created per window, and each component
---     inherits from its global default state (`global_comp_state`).
---   - When a window closes, its state entry is removed.
---
--- Structure:
---   StatuslineState = {
---       [0] = {
---           comp_state = { [comp_id] = CompState },
---           slots = {},
---           ... other global keys ...
---       },
---       [winid] = {
---           comp_state = { [comp_id] = deepcopy(global_comp_state[comp_id]) },
---           slots = (fallback to global),
---           ... window-specific overrides ...
---       }
---   }
---
--- Notes:
---   - All state is created on demand through metatables, so nothing is
---     allocated until a window or component is actually accessed.
---   - Inheritance is shallow per window, but component-state inheritance
---     is deep (via deepcopy).
local function lazy_setup()
	GlobalStatuslineState = StatuslineState[0]
	if not GlobalStatuslineState then
		GlobalStatuslineState = {
			comp_state = {},
			slots = {},
		}
		StatuslineState[0] = GlobalStatuslineState
	end

	local global_comp_state = GlobalStatuslineState.comp_state

	setmetatable(StatuslineState, {
		__index = function(t, winid)
			local win_state = setmetatable({}, {
				__index = function(t1, key)
					local base = GlobalStatuslineState[key]
					if key == "comp_state" then
						local new = setmetatable({}, {
							__index = function(t2, comp_id)
								local global = global_comp_state[comp_id]
								local comp_state = global and vim.deepcopy(global) or {}
								t2[comp_id] = comp_state
								return comp_state
							end,
						})
						t1.comp_state = new
						return new
					end
					return base
				end,
			})
			t[winid] = win_state
			return win_state
		end,
	})
	api.nvim_create_autocmd("WinClosed", {
		callback = function(e)
			StatuslineState[tonumber(e.match)] = nil
		end,
	})
end

--- Returns the state table associated with a window.
---
--- If `winid` is nil, the current window ID is used.
--- Window states are lazily created via WinStateMap's metatable.
---
--- @param winid? integer Window ID to fetch. Defaults to current window.
--- @return StatuslineState state Window-level state table.
local function get_statusline_state(winid)
	return StatuslineState[winid or 0]
end

--- Returns the sorted list of flexible components.
--- @param win_state StatuslineState The window state to fetch the sorted list from.
--- @return {[1]: integer, [2]: CompId}[] sorted The sorted list of flexible components.
local function get_flex_sorted(win_state)
	-- use cached value
	local flexible_sorted = win_state.flexible_sorted
	if flexible_sorted then
		return flexible_sorted
	end

	local sorted = {}
	local comp_state, slots = win_state.comp_state, win_state.slots

	for i, comp_id in ipairs(slots) do
		local comp = comp_state[comp_id]
		if comp.flex then
			sorted[#sorted + 1] = { comp.flex, i, comp_id }
		end
	end
	--- sort by descending flex value
	table.sort(sorted, function(a, b)
		return a[1] > b[1]
	end)

	flexible_sorted = vim.tbl_map(function(value)
		return { value[2], value[3] }
	end, sorted)

	-- cache flexible_sorted
	win_state.flexible_sorted = flexible_sorted

	return flexible_sorted
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
	StatuslineState[winid or 0].comp_state[comp_id].flex = priority
end

--- Inspects the current statusline values.
--- @param kind? "statusline" The type of values to inspect. If nil or "values", inspects the statusline values.
M.inspect = function(kind)
	local notifier = require("witch-line.utils.notifier")
	notifier.info(vim.inspect(StatuslineState))
end

--- Resets the value of a statusline component before caching.
--- @param segment CompState The statusline component to reset.
local format_state_before_cache = function(segment, frozen)
	local frozen_fields = {
		"flex",
		"idxs",
	}
	for k, _ in pairs(segment) do
		if k == VALUE_SHIFT then
			if not frozen then
				segment[k] = "" -- Clear unfrozen main value
			end
		elseif not vim.tbl_contains(frozen_fields, k) then
			segment[k] = nil
		end
	end
end

--- Handles necessary operations before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for caching the statusline.
M.on_vim_leave_pre = function(CacheDataAccessor)
	-- Clear unfrozen values to reset statusline on next startup
	GlobalStatuslineState.flexible_sorted = nil
	for key, value in pairs(GlobalStatuslineState.comp_state) do
		format_state_before_cache(value, type(key) == "number")
	end
	CacheDataAccessor.set("GlobalStatuslineState", GlobalStatuslineState)
end

--- Loads the statusline cache.
--- @param CacheDataAccessor Cache.DataAccessor The data accessor module to use for loading the statusline.
--- @return function undo function to restore the previous state
M.load_cache = function(CacheDataAccessor)
	StatuslineState[0] = CacheDataAccessor.get("GlobalStatuslineState")
	return function()
		StatuslineState[0] = nil
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
--- @param win_state StatuslineState The window state to compute the width for.
--- @return integer total_width The total display width of all statusline components.
local compute_statusline_width = function(win_state)
	local total_width = 0
	local slots, comp_state = win_state.slots, win_state.comp_state

	for i = 1, #slots do
		local comp_id = slots[i]
		total_width = total_width + compute_slot_width(comp_state[comp_id])
	end
	return total_width
end

--- Builds the final statusline string by merging highlight segments and optional
--- click-handler wrappers, while skipping any indices marked in a bitmask.
---
--- Each statusline segment consists of:
---   - left part      (optional)
---   - main value     (required to include the segment)
---   - right part     (optional)
---   - click handler  (optional: wraps the whole segment using "%X")
---
--- Segments whose main value is an empty string are skipped entirely.
---
---
--- @param slots (CompId|integer)[] The indices of the statusline components to build the value for.
--- @param comp_state CompState The statusline component to build the value for.
--- @param skip_bitmasks? integer A bitmask (1-based indices) specifying which segments should be skipped. If nil, no skipping is applied.
--- @return string value The fully concatenated statusline string.
local function build_value(slots, comp_state, skip_bitmasks)
	skip_bitmasks = skip_bitmasks or 0ULL

	local values, n = {}, 0
	for i = 1, #slots do
		if not is_marked(skip_bitmasks, i) then
			local state = comp_state[slots[i]]
			local val = state[VALUE_SHIFT] or ""
			-- If no main value, skip the whole segment including its left and right parts
			if val ~= "" then
				local click_handler_form = state.click_handler_form
				if click_handler_form then
					n = n + 1
					values[n] = click_handler_form
				end

				local left, right = state[left_idx(VALUE_SHIFT)], state[right_idx(VALUE_SHIFT)]
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
	return concat(values)
end

--- Renders the statusline by concatenating all component values and setting it to `o.statusline`.
--- If the statusline is disabled, it sets `o.statusline` to a single space.
--- @param winid? integer The window ID to render the statusline for.
M.render = function(winid)
	if winid and not api.nvim_win_is_valid(winid) then
		return
	end

	local laststatus = o.laststatus
	local dynamic_o, statusline_state
	if laststatus == 0 then
		return
	elseif laststatus == 3 then
		statusline_state = GlobalStatuslineState
		dynamic_o = vim.o
	else
		winid = winid or api.nvim_get_current_win()
		statusline_state = get_statusline_state(winid)
		dynamic_o = vim.wo[winid]
	end

	local comp_state = statusline_state.comp_state

	local flex_sorted = get_flex_sorted(statusline_state)
	local flexible = flex_sorted[1]
	if not flexible then
		local str = build_value(statusline_state.slots, comp_state)
		dynamic_o.statusline = str ~= "" and str or " "
		return
	end

	local remove_idx = 1
	local slot_skipped_bitmask = 0ULL

	local statusline_width = compute_statusline_width(statusline_state)

	local limit_width = winid and api.nvim_win_get_width(winid) or o.columns

	while flexible and statusline_width > limit_width do
		slot_skipped_bitmask = mark_bit(slot_skipped_bitmask, flexible[1])
		statusline_width = statusline_width - compute_slot_width(comp_state[flexible[2]])
		remove_idx = remove_idx + 1
		flexible = flex_sorted[remove_idx]
	end

	local str = build_value(statusline_state.slots, comp_state, slot_skipped_bitmask)
	dynamic_o.statusline = str ~= "" and str or " "
end

--- Appends a new value to the statusline values list.
--- @param comp_id? CompId The component ID. Nil means it is a literal component
--- @param value string The value to append.
--- @param winid? integer The window ID to set the value for.
--- @return integer new_idx The index of the newly added value.
M.push = function(comp_id, value, winid)
	local statusline_state = get_statusline_state(winid)

	local slots = rawget(statusline_state, "slots")
	if not slots then
		slots = {}
		statusline_state.slots = slots
	end

	local new_slots_size = #slots + 1

	if not comp_id then
		LiteralCount = LiteralCount + 1
		---@diagnostic disable-next-line: cast-local-type
		comp_id = LiteralCount
	end

	--- Rawget to avoid automatically creating the table
	local comp_state = statusline_state.comp_state
	local state = rawget(comp_state, comp_id)
	if state then
		state.idxs[#state.idxs + 1] = new_slots_size
	else
		local width = nvim_strwidth(value)
		--- @type CompState
		comp_state[comp_id] = {
			[VALUE_SHIFT] = value,
			[WIDTH_SHIFT] = width,
			total_width = width,
			idxs = { new_slots_size },
		}
	end
	slots[new_slots_size] = comp_id
	return new_slots_size
end

--- Hides a specific component by setting its value to an empty string.
--- @param comp_id CompId The index of the component to hide.
--- @param winid? integer The window ID to set the value for.
M.hide_segment = function(comp_id, winid)
	local state = get_statusline_state(winid).comp_state[comp_id]
	if not state then
		error(comp_id .. winid)
	end
	state[VALUE_SHIFT] = ""
	state[WIDTH_SHIFT], state.total_width = 0, nil
end

--- Sets the value for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param value string The value to set for the specified side.
--- @param hl_name? string The highlight group name to set for segment.
--- @param winid? integer The window ID to set the value for.
M.set_value = function(comp_id, value, hl_name, winid)
	local state = get_statusline_state(winid).comp_state[comp_id]
	state[WIDTH_SHIFT], state.total_width = nvim_strwidth(value), nil
	state[VALUE_SHIFT] = assign_highlight_name(value, hl_name)
end

--- Sets the highlight_name for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param new_hl_name string|nil The new highlight group name to set for the segment.
--- @param winid? integer The window ID to set the value for.
M.set_hl_name = function(comp_id, new_hl_name, winid)
	local state = get_statusline_state(winid).comp_state[comp_id]
	local curr_value = state[VALUE_SHIFT]
	if curr_value then
		state[VALUE_SHIFT] = replace_highlight_name(curr_value, new_hl_name, true)
	end
end

--- Sets the left or right side value for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param shift_side -1|1 The shift side value to get the side idx. 1 Right, -1 Left
--- @param value string The value to set for the specified side.
--- @param hl_name? string The highlight group name to set for the specified side.
--- @param force? boolean If true, forces the update even if a value already exists for the specified side.
--- @param winid? integer The window ID to set the value for.
--- @return boolean success If true the value is change otherwise does nothing.
M.set_side_value = function(comp_id, shift_side, value, hl_name, force, winid)
	local vidx = side_idx(VALUE_SHIFT, shift_side)
	local state = get_statusline_state(winid).comp_state[comp_id]
	if force or not state[vidx] then
		state[side_idx(WIDTH_SHIFT, shift_side)], state.total_width = nvim_strwidth(value), nil
		state[vidx] = assign_highlight_name(value, hl_name)
		return true
	end
	return false
end

--- Sets the left or right side value for a specific component.
--- @param comp_id CompId The index of the component to set the side value for.
--- @param shift_side -1|1 The shift side value to get the side idx. 1 Right, -1 Left
--- @param new_hl_name? string The new highlight group name to set for the specified side.
--- @param winid? integer The window ID to set the value for.
M.set_side_hl_name = function(comp_id, shift_side, new_hl_name, winid)
	local state = get_statusline_state(winid).comp_state[comp_id]
	local idx = side_idx(VALUE_SHIFT, shift_side)
	local curr_value = state[idx]
	if curr_value then
		state[idx] = replace_highlight_name(curr_value, new_hl_name, 1)
	end
end

--- Updates the click handler for a specific component.
--- @param comp_id CompId The index in the statusline of the component to update the click handler for.
--- @param click_handler string The click handler to set for the specified component.
--- @param force? boolean If true, forces the update even if a click handler already exists.
--- @param winid? integer The window ID to set the value for.
M.set_click_handler = function(comp_id, click_handler, force, winid)
	local state = get_statusline_state(winid).comp_state[comp_id]
	if force or not state.click_handler_form then
		state.click_handler_form = "%@v:lua." .. click_handler .. "@"
	end
end

--- Setup the necessary things for statusline rendering.
--- @param disabled_opts UserConfig.Disabled|nil The disabled configuration to apply.
M.setup = function(disabled_opts)
	lazy_setup()

	--- For automatically rerender statusline on Vim or window resize when there are flexible components.
	local render_debounce = require("witch-line.utils").debounce(M.render, 100)
	api.nvim_create_autocmd("VimResized", {
		callback = function(e)
			render_debounce()
		end,
	})

	if type(disabled_opts) == "table" then
		local disabled_filetypes = type(disabled_opts.filetypes) == "table" and disabled_opts.filetypes
		local disabled_buftypes = type(disabled_opts.buftypes) == "table" and disabled_opts.buftypes

		if disabled_buftypes or disabled_filetypes then
			--- Determines if a buffer is disabled based on its filetype and buftype.
			--- @param bufnr integer The buffer number to check.
			--- @return boolean
			local is_buf_disabled = function(bufnr)
				local buf_o = bo[bufnr]
				if disabled_filetypes then
					local filetype = buf_o.filetype
					for _, ft in ipairs(disabled_filetypes) do
						if filetype == ft then
							return true
						end
					end
				end

				if disabled_buftypes then
					local buftype = buf_o.buftype
					for _, bt in ipairs(disabled_buftypes) do
						if buftype == bt then
							return true
						end
					end
				end

				return false
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
