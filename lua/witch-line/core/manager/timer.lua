local M = {}

local ONE_SECOND = 1000 -- 1 second

--- @class TimerStore
--- Maps a base interval to a table of subintervals and component IDs.
--- Example:
--- {
---   [1000] = {
---     [1000] = {"comp_id1"},
---     [2000] = {"comp_id2"}
---   }
--- }
local TimerStore = {}

--- @type table<uinteger, uv.uv_timer_t>
--- Active libuv timers keyed by their base interval.
local Timers = {}

M.inspect = function()
	require("witch-line.utils.notifier").info(vim.inspect(TimerStore))
end

--- Stops and clears all active timers.
M.stop_all_timers = function()
	for _, timer in pairs(Timers) do
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
	local interval = comp.timing == true and ONE_SECOND or comp.timing

	if type(interval) == "number" and interval > 0 then
		for base, group in pairs(TimerStore) do
			if interval % base == 0 then
				-- If comp interval is multiple of existing base, reuse base timer
				local comp_ids = group[interval] or {}
				comp_ids[#comp_ids + 1] = comp.id
				group[interval] = comp_ids
				return
			elseif base % interval == 0 then
				-- If existing base is a multiple of new interval, replace base (new base = smaller one)
				group[interval] = { comp.id }
				TimerStore[interval] = group
				TimerStore[base] = nil
				return
			end
		end

		-- New base timer
		TimerStore[interval] = {
			[interval] = { comp.id },
		}
	end
end

--- Calculates the Least Common Multiple (LCM) of two positive integers.
--- Optimized for LuaJIT (which does not support the '//' integer division operator).
--- This function inlines the GCD (Greatest Common Divisor) calculation for speed.
---
--- Implementation details:
--- 1. Uses the Euclidean algorithm to compute GCD efficiently.
--- 2. Avoids floating-point arithmetic by using integer division equivalent:
---      (a - a % gcd) / gcd
---    which guarantees an integer result without calling `math.floor`.
--- 3. Returns (a / gcd) * b — the standard formula for LCM.
---
--- @param a integer First positive integer
--- @param b integer Second positive integer
--- @return integer lcm The least common multiple of `a` and `b`
local function lcm(a, b)
	-- Inline GCD computation using Euclidean algorithm
	local x, y = a, b
	while y ~= 0 do
		x, y = y, x % y
	end

	-- Compute LCM without using floating-point division or math.floor
	-- Formula: (a / gcd(a,b)) * b
	-- Using (a - a % x) / x ensures integer division result in LuaJIT
	return ((a - a % x) / x) * b
end

--- Initialize the timer for components that have timers registered.
--- @param work fun(sid: SessionId, ids: CompId[], interval: uinteger) The function to execute when the timer triggers. It receives the sid, component IDs, and interval as arguments.
M.on_timer_trigger = function(work)
	if not next(TimerStore) then
		return
	end

	local uv = vim.uv or vim.loop
	local Session = require("witch-line.core.Session")

	for base, group in pairs(TimerStore) do
		local timer = uv.new_timer()
		local tick = 0
		local threshold = base
		timer:start(
			0,
			base,
			vim.schedule_wrap(function()
				tick = tick + 1
				local elapsed = tick * base
				local queue, qn = {}, 0

				for interval, comp_ids in pairs(group) do
					if elapsed % interval == 0 then
						for i = 1, #comp_ids do
							-- Collect all components whose intervals match this tick
							qn = qn + 1
							queue[qn] = comp_ids[i]
						end
					end
					if threshold % interval ~= 0 then
						threshold = lcm(threshold, interval)
					end
				end

				if qn > 0 then
					--- Remove abandant queue part
					local i = qn + 1
					while queue[i] do
						queue[i] = nil
						i = i + 1
					end
					Session.with_session(function(sid)
						work(sid, queue, base)
						qn = 0 -- virtual clear queue
					end)
				end

				-- Reset cycle when reaching threshold			-- reach the threshold cycle then reset tick
				if elapsed >= threshold then
					tick = 0
				end
			end)
		)
		Timers[base] = timer
	end
end

return M
