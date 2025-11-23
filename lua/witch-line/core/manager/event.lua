local next, type, pairs, vim = next, type, pairs, vim
local nvim_create_autocmd = vim.api.nvim_create_autocmd

local Session = require("witch-line.core.Session")

local M = {}

local AUGROUP = vim.api.nvim_create_augroup("WitchLineEvent", { clear = true })
local EVENT_INFO_STORE_ID = "EventInfo"

--- Options used for configuring a special event.
--- These fields control event behavior but do not include identifiers.
--- @class SpecialEventOpts
--- @field once? boolean  Optional flag. If true, the event is triggered only once.
--- @field remove_when? fun():boolean The event will be remove when `remove_when` return true
---
--- Optional file/buffer pattern(s).
--- Can be:
---   - string: a single pattern
---   - string[]: list of patterns
---   - nil: no pattern filtering
--- Empty strings or "*" are treated as no pattern.
--- @field pattern? string|string[]|nil

--- Represents a fully registered special event entry stored in the event registry.
--- This type includes resolved event names and the list of component IDs bound to it.
--- @class SpecialEvent : SpecialEventOpts
---
--- One or more event names.
--- After normalization, this is **always** a list-of-strings.
--- @field name string|string[]
--- @field ids CompId[] Array of component IDs associated with this event.

--- Input shape for incoming special events before being stored.
--- This type is used when registering new events.
--- It omits `ids` because the store is responsible for managing and appending them.
--- @class SpecialEventInput : SpecialEvent
--- @field ids nil `ids` must be nil. The system will create and populate this field.

--- @class EventStore
--- Stores component dependencies for nvim events
--- ### Example
---   events = {
---     [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for nvim events
---   },
--- @field events table<string, CompId[]>
--- Stores component dependencies for user-defined events
--- ### Example
--    user_events = {
-- 	    [event] = { comp_id1, comp_id2, ... } -- Stores component dependencies for user-defined events
--    },
--- @field user_events table<string, CompId[]>
--- Stores component dependencies for user-defined events
--- ### Example
---   special_events = {
---     {
---       name = "BufEnter",
---       pattern = "*lua"
---       ids = { comp1, comp2 }
---     }
---   }
--- @field special_events SpecialEvent[]
local EventStore = {
	events = {},
	user_events = {},
	special_events = {},
}

--- The function to be called before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the stores.
M.on_vim_leave_pre = function(CacheDataAccessor)
	local special_events = EventStore.special_events
	if special_events then
		local Persist = require("witch-line.utils.persist")
		for _, entry in ipairs(special_events) do
			Persist.serialize_function(entry)
		end
	end
	CacheDataAccessor["EventStore"] = EventStore
end

--- Load the event and timer stores from the persistent storage.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the stores.
M.load_cache = function(CacheDataAccessor)
	EventStore = CacheDataAccessor.EventStore or EventStore
end

M.inspect = function()
	require("witch-line.utils.notifier").info(vim.inspect(EventStore))
end

--- Compare two values that may each be either:
--- - a string, or
--- - an array (list) of strings.
---
--- Extended behavior:
--- - If one side is a string and the other is a list with **exactly one element**,
---   the two are considered equal **if that single element equals the string**.
---
--- @param a string|table The first value to compare
--- @param b string|table The second value to compare
--- @return boolean equal True if the two values are equal, false otherwise
local function string_list_equal(a, b)
	local ta, tb = type(a), type(b)

	-- Case 1: Same type
	if ta == tb then
		if ta == "string" then
			return a == b
		elseif ta == "table" then
			--- @cast b table
			return require("witch-line.utils.tbl").array_equal(a, b)
		end
		return false
	end

	-- Case 2: Compare string vs single-element list
	-- Normalize: ensure "list" is always first variable
	local str, list
	if ta == "string" and tb == "table" then
		str, list = a, b
	elseif ta == "table" and tb == "string" then
		str, list = b, a
	else
		return false -- unsupported types
	end

	-- Only equal if list is exactly one element AND matches string
	if #list == 1 then
		return list[1] == str
	end

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
	if a.once ~= b.once then
		return false
	elseif a.remove_when ~= b.remove_when then
		return false
	elseif not string_list_equal(a.pattern, b.pattern) then
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
--- ### Example:
--- ```lua
--- local idx = find_existed_special_event(event_store, new_event)
--- if idx ~= -1 then
---   print("Event already exists at index:", idx)
--- end
--- ```
---
--- ### Implementation details:
--- - Uses a **linear search** over `store`.
--- - Equality between two events is determined by `same_special_event(existed, e)`.
--- - Stops at the first match for efficiency.
---
--- @param store table A list (array) of existing special events.
--- @param e table The event to check for existence.
--- @return integer The index of the existing event if found, otherwise `-1`.
local find_matching_special_event = function(store, e)
	for k = 1, #store do
		local existed = store[k]
		if same_special_event_opts(existed, e) then
			return k
		end
	end
	return -1
end

--- Push a component ID into `store[name]`.
--- If the list does not exist, create it before appending.
--- @param store table<string, table> The store table containing event lists.
--- @param event string The name of the list inside the store.
--- @param comp_id CompId The value to append into the list.
local function register_normal_event(store, event, comp_id)
	if not comp_id then
		error("Component id must not be nil")
	end

	local list = store[event]
	if not list then
		store[event] = { comp_id }
	else
		list[#list + 1] = comp_id
	end
	return list
end

--- Register or update an entry in the special-event store.
--- If a matching event entry exists, append the component ID and merge event names.
--- Otherwise, insert a new entry.
---
--- @param store SpecialEventInput[] The list storing SpecialEvent items.
--- @param event SpecialEventInput The incoming event definition.
--- @param comp_id CompId The component ID to register.
--- @return nil
local function register_special_event_entry(store, event, comp_id)
	-- Normalize incoming_names into either string or list-of-strings
	local event_name = event.name
	if type(event_name) == "table" then
		local names = event.name
		if type(names) == "table" then
			event_name = vim.tbl_filter(function(v)
				return v ~= ""
			end, event_name)
			local n = #event_name
			if n == 0 then
				return
			end
			if n == 1 then
				event_name = event_name[1]
			end
		end
	end

	-- Find existing entry index (-1 if not found)
	local entry_index = find_matching_special_event(store, event)
	if entry_index > 0 then
		local entry = store[entry_index]

		-- Append component ID
		entry.ids[#entry.ids + 1] = comp_id

		-- Normalize "name" to list
		local name_list, name_list_size = entry.name or {}, nil
		if type(name_list) == "string" then
			name_list = { name_list }
			name_list_size = 1
		else
			name_list_size = #name_list
		end

		-- Merge event.name into existing list
		if type(event_name) == "table" then
			for i, name in ipairs(event_name) do
				name_list[name_list_size + i] = name
			end
		else
			name_list[name_list_size + 1] = event_name
		end
		entry.name = name_list
	else
		event.name = event_name
		event.ids = { comp_id }
		-- Insert a brand new event entry
		store[#store + 1] = event
	end
end

--- Register an autocommand event represented as a plain string.
---
--- Supported formats include:
---   "BufEnter *.lua"
---   "BufEnter *.lua",*.js,...
---   "User MyEvent"
---   "CursorHold"
---
--- This function performs the following steps:
--- 1. Parses the raw declaration into:
---       - `ename`: the event identifier (e.g. "BufEnter", "User", "CursorHold")
---       - `patterns`: zero or more trailing patterns (e.g. "*.lua", "MyEvent")
---
--- 2. Classifies the parsed event into one of three internal buckets:
---       - User-defined events:
---           "User <Pattern>"  → stored in `user_events`
---
---       - Special events with patterns:
---           "<Event> <Pattern>"  → stored in `special_events`
---           (e.g.: "BufEnter *.lua")
---
---       - Normal events without patterns:
---           "<Event>" → stored in `normal_events`
---
--- Parsing behavior:
---   "BufEnter *.lua" → ename = "BufEnter", patterns = "*.lua"
---   "User MyEvent"   → ename = "User",    patterns = "MyEvent"
---   "CursorHold"     → ename = "CursorHold", patterns = ""
---
--- @param e string  A raw event declaration from the component. Must follow one of the
---                  supported formats and must not include nested tables or callback keys.
--- @param comp_id CompId component id
local function register_string_event(e, comp_id)
	-- Extract the event name and trailing pattern section.
	local event_name, patterns = e:match("^(%S+)%s*(.*)$")
	if not event_name then
		return
	elseif patterns == "" then
		-- No patterns (E.g.: "CursorHold")
		register_normal_event(EventStore.events, event_name, comp_id)
	elseif event_name == "User" then
		-- E.g User LazyLoad
		local store = EventStore.user_events
		for p in patterns:gmatch("[^,%s]+") do
			if p ~= "*" then
				register_normal_event(store, p, comp_id)
			end
		end
	else
		-- E.g BufEnter *.lua
		local ps, n = {}, 0
		for p in patterns:gmatch("[^,%s]+") do
			if p ~= "*" then
				n = n + 1
				ps[n] = p
			end
		end
		register_special_event_entry(EventStore.special_events, {
			name = event_name,
			pattern = n > 1 and ps or ps[1], -- store string if only 1 value for reduce memory usage.,
		}, comp_id)
	end
end

--- Process a table-based event definition.
--- This function extracts numeric-index event names, normalizes the pattern,
--- and decides whether to register a normal event or a special event.
---
--- Example accepted input:
--- {
---   [1] = "BufEnter",
---   [2] = "BufLeave",
---   pattern = "*.lua",
---   once = true,
--- }
---
--- @param e Component.SpecialEvent The raw event definition supplied by user. May contain:
---   - numeric keys → event names
---   - "pattern" (string|string[]|nil)
---   - "once" (boolean|nil)
--- @param comp_id CompId Component object that contains `id`
local function register_tbl_event(e, comp_id)
	local event_names, event_count, opts, outs_count = {}, 0, {}, 0
	for k, v in pairs(e) do
		if type(k) == "number" and v ~= "" then
			event_count = event_count + 1
			event_names[event_count] = v
		elseif k ~= "pattern" then
			outs_count = outs_count + 1
			opts[outs_count] = k
		end
	end
	if event_count == 0 then
		return
	end

	-- Normalize pattern
	local pattern = e.pattern
	if pattern then
		-- Format pattern
		local pattern_type = type(pattern)
		if pattern_type == "table" then
			-- Faster manual filtering (avoid vim.tbl_filter)
			local new = {}
			local n = 0
			for i = 1, #pattern do
				local v = pattern[i]
				if v ~= "" and v ~= "*" then
					n = n + 1
					new[n] = v
				end
			end
			if n == 0 then
				pattern = nil
			elseif n == 1 then
				pattern = new[1]
			else
				pattern = new
			end
		elseif pattern_type ~= "string" then
			error("Invalid pattern in " .. vim.inspect(e))
		elseif pattern == "" or pattern == "*" then
			pattern = nil
		end
	end

	-- No options, no pattern → register as normal event
	if outs_count == 0 and not pattern then
		local store = EventStore.events
		for k = 1, event_count do
			register_normal_event(store, event_names[k], comp_id)
		end
		return
	end

	local new = {
		name = event_names,
		pattern = pattern,
	}
	for i = 1, outs_count do
		local opt = opts[i]
		new[opt] = e[opt]
	end

	-- Otherwise → special event
	register_special_event_entry(EventStore.special_events, new, comp_id)
end

--- Register events declared by a component.
--- This function accepts three event declaration formats:
---   1. A single string event → "BufEnter *.lua"
---   2. A list of string events → { "BufEnter *.lua", "CursorHold" }
---   3. A list of table-based special events → { { "BufEnter", pattern = "*.lua" }, ... }
---
--- The function detects the type of each event entry and delegates to:
---   - register_string_event()  for string-based event definitions
---   - register_tbl_event()     for table-based (special) events
---
--- @param comp ManagedComponent  The component to register events
M.register_events = function(comp)
	local cid, events = comp.id, comp.events
	local t = type(events)
	if t == "string" then
		register_string_event(events, cid)
	elseif t == "table" then
		for i = 1, #events do
			local e = events[i]
			local etype = type(e)
			if etype == "string" then
				register_string_event(e, cid)
			elseif etype == "table" then
				--- @cast e Component.SpecialEvent
				register_tbl_event(e, cid)
			end
		end
	end
end

--- Register the component for VimResized event.
--- @param comp ManagedComponent The component to register for VimResized event.
M.register_vim_resized = function(comp)
	register_normal_event(EventStore.events, "VimResized", comp.id)
end

--- Register the component for WinEnter event.
--- @param comp ManagedComponent The component to register for WinEnter event.
M.register_win_enter = function(comp)
	register_normal_event(EventStore.events, "WinEnter", comp.id)
end

--- Get the event information for a component in a session.
--- @param comp ManagedComponent The component to get the event information for.
--- @param sid SessionId The session id to get the event information for.
--- @return vim.api.keyset.create_autocmd.callback_args|nil event_info The event information for the component, or nil if not found.
--- @see Hook.use_event_info
M.get_event_info = function(comp, sid)
	local store = Session.get_store(sid, EVENT_INFO_STORE_ID)
	return store and store[comp.id] or nil
end

--- Initialize the autocmd for events and user events.
--- @param work fun(sid: SessionId, ids: CompId[], event_info: table<CompId, vim.api.keyset.create_autocmd.callback_args>) The function to execute when an event is triggered. It receives the sid, component IDs, and event information as arguments.
M.on_event = function(work)
	local events, user_events, spectial_events =
		EventStore.events, EventStore.user_events, EventStore.special_events

	--- @type table<CompId, vim.api.keyset.create_autocmd.callback_args>
	local event_queue = {}

	local dispatch_events = function(sid)
		Session.new_store(sid, EVENT_INFO_STORE_ID, event_queue)
		work(sid, vim.tbl_keys(event_queue), event_queue)
		event_queue = {}
	end

	local dispatch_debounce = require("witch-line.utils").debounce(function()
		Session.with_session(dispatch_events)
	end, 100)

	if next(events) then
		nvim_create_autocmd(vim.tbl_keys(events), {
			group = AUGROUP,
			callback = function(e)
				for _, id in ipairs(events[e.event]) do
					event_queue[id] = e
				end
				dispatch_debounce()
			end,
		})
	end

	if next(user_events) then
		nvim_create_autocmd("User", {
			pattern = vim.tbl_keys(user_events),
			group = AUGROUP,
			callback = function(e)
				for _, id in ipairs(user_events[e.match]) do
					event_queue[id] = e
				end
				dispatch_debounce()
			end,
		})
	end

	if next(spectial_events) then
		for i = 1, #spectial_events do
			local entry = spectial_events[i]
			nvim_create_autocmd(entry.name, {
				pattern = entry.pattern,
				once = entry.once,
				group = AUGROUP,
				callback = function(e)
					for _, id in ipairs(entry.ids) do
						event_queue[id] = e
					end
					dispatch_debounce()

					local remove_when = require("witch-line.utils.persist").lazy_decode(entry, "remove_when")
					if type(remove_when) == "function" then
						return remove_when()
					end
				end,
			})
		end
	end
end
return M
