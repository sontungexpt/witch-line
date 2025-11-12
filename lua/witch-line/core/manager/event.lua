local Session = require("witch-line.core.Session")

local M = {}

local EventInfoStoreId = "EventInfo"

--- @class SpecialEventOpts
--- @field once? boolean
--- @field pattern? string|string[]

--- @class SpecialEvent : SpecialEventOpts
--- @field name string|string[]
--- @field ids CompId[]

---@class EventStore
---@field events nil|table<string, CompId[]> Stores component dependencies for nvim events
---@field user_events nil|table<string, CompId[]> Stores component dependencies for user-defined events
---@field special_events nil|SpecialEvent[] Stores component dependencies for user-defined events
local EventStore = {
	-- Stores component dependencies for events
	-- Only init if needed
	-- events = {
	-- 	-- [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for nvim events
	-- },

	-- -- -- Stores component dependencies for user events
	-- Only init if needed
	-- user_events = {
	-- 	-- [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for user-defined events
	-- },

	-- special_events = {
	--   {
	--     name = "BufEnter",
	--     pattern = "*lua"
	--     ids = { comp1, comp2 }
	--   }
	-- }
}

--- The function to be called before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the stores.
M.on_vim_leave_pre = function(CacheDataAccessor)
	CacheDataAccessor.set("EventStore", EventStore)
end

--- Load the event and timer stores from the persistent storage.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the stores.
--- @return function undo function to restore the previous state of the stores
M.load_cache = function(CacheDataAccessor)
	local before_event_store = EventStore

	EventStore = CacheDataAccessor.get("EventStore") or EventStore

	return function()
		EventStore = before_event_store
	end
end

M.inspect = function()
	require("witch-line.utils.notifier").info(vim.inspect(EventStore))
end

--- Check whether two values are the same when they can each be either a string or an array of strings.
---
--- This function provides flexible equality for cases where a field can hold:
--- - a single string value, or
--- - a list (array) of string values.
---
--- Comparison behavior:
--- 1. **Different types:**
---    - If one is a string and the other is a table → returns `false`.
--- 2. **Both strings:**
---    - Compares them directly using `==`.
--- 3. **Both tables (arrays):**
---    - Compares them by content, ignoring element order,
---      using `array_equal()` (which performs multiset comparison).
--- 4. **Unsupported types:**
---    - Returns `false` by default.
---
--- ### 🧩 Example:
--- ```lua
--- same_string_or_array("foo", "foo")            --> true
--- same_string_or_array({"a", "b"}, {"b", "a"})  --> true
--- same_string_or_array("foo", {"foo"})          --> false
--- same_string_or_array({"x"}, {"x", "y"})       --> false
--- ```
---
--- ### 💡 Use case:
--- Useful when comparing dynamic fields like `component.name` or `tags`
--- that can store either a single string or an array of names.
---
--- @param a string|table The first value to compare.
--- @param b string|table The second value to compare.
--- @return boolean `true` if both are equal (order-insensitive for arrays), otherwise `false`.
local function same_string_or_array(a, b)
	local ta, tb = type(a), type(b)

	-- Different types (e.g., "string" vs "table") -> not equal
	if ta ~= tb then
		return false
	end

	if ta == "string" then
		-- Direct string comparison
		return a == b
	elseif ta == "table" then
		-- Compare arrays (order-insensitive, content-based)
		--- @cast b table
		return require("witch-line.utils.tbl").array_equal(a, b)
	end

	-- Fallback: unsupported types
	return false
end

--- Compare two special event option objects to determine if they are equivalent.
--- This function checks whether both events share the same `pattern` (string or array)
--- and the same `once` flag. Used to detect duplicate or redundant special event
--- definitions when registering autocmd-like events.
---
--- @param a SpecialEventOpts|SpecialEvent # The first special event or its options table.
--- @param b SpecialEventOpts|SpecialEvent # The second special event options table to compare against.
--- @return boolean                        # `true` if both have the same `pattern` and `once` values; otherwise `false`.
local same_special_event_opts = function(a, b)
	if not same_string_or_array(a.pattern, b.pattern) then
		return false
	end
	if a.once ~= b.once then
		return false
	end
	return true
end

--- Find the index of an existing special event in the given store.
---
--- This function iterates through the event store and checks whether
--- a given event `e` already exists based on custom comparison logic
--- defined in `same_special_event()`.
---
--- If a matching event is found, its index in the `store` array is returned.
--- If no match is found, the function returns `-1`.
---
--- ### 🧩 Example:
--- ```lua
--- local idx = find_existed_special_event(event_store, new_event)
--- if idx ~= -1 then
---   print("Event already exists at index:", idx)
--- end
--- ```
---
--- ### ⚙️ Implementation details:
--- - Uses a **linear search** over `store`.
--- - Equality between two events is determined by `same_special_event(existed, e)`.
--- - Stops at the first match for efficiency.
---
--- @param store table A list (array) of existing special events.
--- @param e table The event to check for existence.
--- @return integer The index of the existing event if found, otherwise `-1`.
local find_existed_special_event_opts = function(store, e)
	for k = 1, #store do
		local existed = store[k]
		if same_special_event_opts(existed, e) then
			return k
		end
	end
	return -1
end

--- Register events for components.
---@param comp Component
M.register_events = function(comp)
	local events = comp.events
	local t = type(events)
	if t == "string" then
		events, t = { events }, "table"
	end

	if t == "table" then
		local store
		for i = 1, #events do
			local e = events[i]
			local etype = type(e)
			if etype == "string" then
				local ename, patterns = e:match("^(%S+)%s*(.*)$")
				if ename then
					if ename == "User" then
						-- User LazyLoad
						if patterns and patterns ~= "" then
							store = EventStore.user_events or {}
							EventStore.user_events = store
							for pat in patterns:gmatch("[^,%s]+") do
								local store_e = store[pat] or {}
								store_e[#store_e + 1] = comp.id
								store[pat] = store_e
							end
						end
					elseif patterns and patterns ~= "" then
						store = EventStore.special_events or {}
						EventStore.special_events = store
						local ps, n = {}, 0
						for pat in patterns:gmatch("[^,%s]+") do
							n = n + 1
							ps[n] = pat
						end
						local pattern = n > 1 and ps or ps[1] -- store string if only 1 value for reduce memory usage.
						local idx = find_existed_special_event_opts(store, {
							pattern = pattern,
						})
						if idx > 0 then
							local existed = store[idx]
							existed.ids[#existed.ids + 1] = comp.id
							local names = existed.name or {}
							if type(names) == "string" then
								names = { names }
							end
							names[#names + 1] = ename
							existed.name = names
						else
							store[#store + 1] = {
								name = ename,
								pattern = pattern,
								ids = { comp.id },
							}
						end
					else
						-- BufEnter
						store = EventStore.events or {}
						EventStore.events = store
						local store_e = store[e] or {}
						store_e[#store_e + 1] = comp.id
						store[e] = store_e
					end
				end
			elseif etype == "table" then
				local names, n, no_opts = {}, 0, true
				for k, val in pairs(e) do
					if type(k) == "number" and val ~= "" then
						n = n + 1
						names[n] = val
					elseif k ~= "pattern" then
						no_opts = false
					end
				end

				if n > 0 then
					local pattern = e.pattern
					if pattern then
						local pattern_type = type(pattern)
						if pattern_type == "table" then
							pattern = vim.tbl_filter(function(value)
								return value ~= ""
							end, pattern)
							local size = #pattern
							if size == 0 then
								pattern = nil
							elseif size == 1 then
								pattern = pattern[1]
							end
						elseif pattern_type ~= "string" then
							error("Invalid pattern in " .. vim.inspect(e))
						elseif pattern == "" then
							pattern = nil
						end
					end

					--- Just contains event names
					if no_opts and not pattern then
						store = EventStore.events or {}
						EventStore.events = store
						for k = 1, n do
							local name = names[k]
							local store_e = store[name] or {}
							store_e[#store_e + 1] = comp.id
							store[name] = store_e
						end
					else
						store = EventStore.special_events or {}
						EventStore.special_events = store
						local idx = find_existed_special_event_opts(store, {
							pattern = pattern, -- store string if only 1 value for reduce memory usage.
							once = e.once,
						})
						if idx > 0 then
							local existed = store[idx]
							existed.ids[#existed.ids + 1] = comp.id
							local existed_names = existed.name or {}
							if type(existed_names) == "string" then
								existed_names = { existed_names }
							end
							for k = 1, n do
								local name = names[k]
								existed_names[#existed_names + 1] = name
							end
							existed.name = existed_names
						else
							store[#store + 1] = {
								name = n > 1 and names or names[1],
								pattern = pattern, -- store string if only 1 value for reduce memory usage.
								once = e.once,
								ids = { comp.id },
							}
						end
					end
				end
			end
		end
	end
end

--- Register the component for VimResized event if it has a minimum screen width.
--- @param comp Component The component to register for VimResized event.
M.register_vim_resized = function(comp)
	local store = EventStore.events or {}
	EventStore.events = store
	local es = store["VimResized"] or {}
	es[#es + 1] = comp.id
	store["VimResized"] = es
end

--- Get the event information for a component in a session.
--- @param comp Component The component to get the event information for.
--- @param sid SessionId The session id to get the event information for.
--- @return vim.api.keyset.create_autocmd.callback_args|nil event_info The event information for the component, or nil if not found.
--- @see Hook.use_event_info
M.get_event_info = function(comp, sid)
	local store = Session.get_store(sid, EventInfoStoreId)
	return store and store[comp.id] or nil
end

--- Initialize the autocmd for events and user events.
--- @param work fun(sid: SessionId, ids: CompId[], event_info: table<string, any>) The function to execute when an event is triggered. It receives the sid, component IDs, and event information as arguments.
M.on_event = function(work)
	local events, user_events, spectial_events = EventStore.events, EventStore.user_events, EventStore.special_events

	--- @type table<CompId, vim.api.keyset.create_autocmd.callback_args>
	local id_event_info_map = {}

	local emit = require("witch-line.utils").debounce(function()
		Session.with_session(function(sid)
			Session.new_store(sid, EventInfoStoreId, id_event_info_map)
			work(sid, vim.tbl_keys(id_event_info_map), id_event_info_map)
			id_event_info_map = {}
		end)
	end, 120)

	local api = vim.api
	local group = api.nvim_create_augroup("WitchLineEvents", { clear = true })
	if events and next(events) then
		api.nvim_create_autocmd(vim.tbl_keys(events), {
			group = group,
			callback = function(e)
				for _, id in ipairs(events[e.event]) do
					id_event_info_map[id] = e
				end
				emit()
			end,
		})
	end

	if user_events and next(user_events) then
		api.nvim_create_autocmd("User", {
			pattern = vim.tbl_keys(user_events),
			group = group,
			callback = function(e)
				for _, id in ipairs(user_events[e.match]) do
					id_event_info_map[id] = e
				end
				emit()
			end,
		})
	end

	if spectial_events and next(spectial_events) then
		for i = 1, #spectial_events do
			local entry = spectial_events[i]
			api.nvim_create_autocmd(entry.name, {
				pattern = entry.pattern,
				once = entry.once,
				group = group,
				callback = function(e)
					for _, id in ipairs(entry.ids) do
						id_event_info_map[id] = e
					end
					emit()
				end,
			})
		end
	end
end
return M
