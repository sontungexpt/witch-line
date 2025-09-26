local M = {}

local TIMER_TICK = 1000 -- 1 second

---@alias TimerStore table<uinteger , Id[] | {timer: uv.uv_timer_t}>
---@type TimerStore
local TimerStore = {
	-- Stores component IDs for timers
	-- Stores component IDs for timers with a specific interval
	-- [interval] = {
	--   comp_id1,
	--   comp_id2,
	--   ...
	--   ...
	-- }
}
local timers = {
	-- [interval] = uv.new_timer(), -- Timer object for the component
}

M.on_vim_leave_pre = function(Cache)
	Cache.cache(TimerStore, "TimerStore")
end

--- Load the event and timer stores from the persistent storage.
--- @param Cache Cache The cache module to use for loading the stores.
--- @return function undo function to restore the previous state of the stores
M.load_cache = function(Cache)
	local before_timer_store = TimerStore

	TimerStore = Cache.get("TimerStore") or TimerStore

	return function()
		for interval, timer in pairs(timers) do
			timer:stop() -- Stop the timer if it exists
			timer:close() -- Close the timer to free resources
		end
		timers = {}
		TimerStore = before_timer_store
	end
end
--- Register a timer for a component.
--- @param comp Component The component to register the timer for.
M.registry_timer = function(comp)
	local timing = comp.timing == true and TIMER_TICK or comp.timing

	if type(timing) == "number" and timing > 0 then
		local ids = TimerStore[timing] or {}
		ids[#ids + 1] = comp.id
		TimerStore[timing] = ids
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
		timer = uv.new_timer()
		timer:start(
			0,
			interval,
			vim.schedule_wrap(function()
				local Session = require("witch-line.core.Session")
				Session.run_once(function(session_id)
					work(session_id, ids)
				end)
			end)
		)
		timers[interval] = timer
	end
end

return M
