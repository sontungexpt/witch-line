local Session = require("witch-line.core.Session")

local M = {}

local EventInfoStoreId = "EventInfo"

---@class SpecialEvent
---@field name  string
---@field patterns string[]
---@field ids CompId[]

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
					table.sort(ps)
					local found = false
					for k = 1, #store do
						local entry = store[k]
						local entry_patterns = entry.patterns
						local pcount = #entry_patterns
						if entry.name == ename and pcount == n then
							local same = true
							for l = 1, pcount do
								if ps[l] ~= entry_patterns[l] then
									same = false
									break
								end
							end
							if same then
								entry.ids[#entry.ids + 1] = comp.id
								found = true
								break
							end
						end
					end
					if not found then
						store[#store + 1] = {
							name = ename,
							patterns = patterns,
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
				pattern = entry.patterns,
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
