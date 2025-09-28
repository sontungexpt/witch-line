local M = {}

local TIMER_TICK = 1000 -- 1 second

---@alias TimerStore table<uinteger , Id[] >
---@type TimerStore
local TimerStore = {
	-- Stores component IDs for timers with a specific interval
	-- [interval] = {
	--   comp_id1,
	--   comp_id2,
	--   ...
	-- }
}

--- @type table<uinteger, uv.uv_timer_t>
local Timers = {
	-- [interval] = uv.new_timer(), -- Timer object for the component
}


--- Stops and clears all active timers.
M.stop_all_timers = function()
	for interval, timer in pairs(Timers) do
		timer:stop() -- Stop the timer if it exists
		timer:close() -- Close the timer to free resources
	end
	Timers = {}
end

--- Cache the timer store before exiting Neovim.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for caching the timer store.
M.on_vim_leave_pre = function(CacheDataAccessor)
	CacheDataAccessor.set("TimerStore", TimerStore)
end

--- Load the event and timer stores from the persistent storage.
--- @param 	CacheDataAccessor Cache.DataAccessor The cache module to use for loading the stores.
--- @return function undo function to restore the previous state of the stores
M.load_cache = function(CacheDataAccessor)
	local before_timer_store = TimerStore

	TimerStore = CacheDataAccessor.get("TimerStore") or TimerStore

	return function()
		M.stop_all_timers()
		TimerStore = before_timer_store
	end
end
--- Register a timer for a component.
--- @param comp Component The component to register the timer for.
M.register_timer = function(comp)
	local interval = comp.timing == true and TIMER_TICK or comp.timing

	if type(interval) == "number" and interval > 0 then
		local ids = TimerStore[interval] or {}
		ids[#ids + 1] = comp.id
		TimerStore[interval] = ids
	end
end

--- Initialize the timer for components that have timers registered.
M.on_timer_trigger = function(work)
	if not next(TimerStore) then
		return
	end

	local uv = vim.uv or vim.loop
	for interval, ids in pairs(TimerStore) do
		local timer = uv.new_timer()
		timer:start(
			0,
			interval,
			vim.schedule_wrap(function()
				local Session = require("witch-line.core.Session")
				Session.run_once(function(session_id)
					work(session_id, ids, interval)
				end)
			end)
		)
		Timers[interval] = timer
	end
end

return M
