local pairs, type = pairs, type

local M = {}

local ONE_SECOND = 1000 -- 1 second

--- The full mapping:
--- {
---   [1000] = {
---     [1000] = {"comp1"},
---     [2000] = {"comp2"},
---   },
---   [400] = {
---     [400] = {"compA"},
---     [800] = {"compX"},
---   }
--- }
--- @type table<integer, table<integer, CompId[]>>
local TimerStore = {}

--- @type table<integer, uv.uv_timer_t>
--- Active libuv timers keyed by their base interval.
local Timers = {}

M.inspect = function()
    require("witch-line.utils.notifier").info(vim.inspect(TimerStore))
end

--- Stops and clears all active timers.
M.stop_all_timers = function()
    for _, timer in pairs(Timers) do
        timer:stop()  -- Stop the timer if it exists
        timer:close() -- Close the timer to free resources
    end
    Timers = {}
end


--- Register a timer for a component.
--- @param comp ManagedComponent The component to register the timer for.
M.register_timer = function(comp)
    local interval = comp.timing == true and ONE_SECOND or comp.timing
    if type(interval) ~= "number" or interval <= 0 then
        return
    end

    local cid = comp.id
    for base, group in pairs(TimerStore) do
        if interval % base == 0 then
            local list = group[interval] or {}
            list[#list + 1] = cid
            group[interval] = list
            return
        elseif base % interval == 0 then
            group[interval] = { cid }
            TimerStore[interval] = group
            TimerStore[base] = nil
            return
        end
    end

    TimerStore[interval] = { [interval] = { cid } }
end

--- Least Common Multiple of two positive integers.
--- Inline GCD via Euclidean algorithm, then `(a / gcd) * b`.
--- @param a integer
--- @param b integer
--- @return integer
local function lcm(a, b)
    local x, y = a, b
    while y ~= 0 do
        x, y = y, x % y
    end
    return (a / x) * b
end

--- Initialize the timer for components that have timers registered.
--- @param work fun(ids: CompId[]) The function to execute when the timer triggers.
M.on_timer_trigger = function(work)
    if not next(TimerStore) then
        return
    end
    vim.schedule(function()
        local uv = vim.uv or vim.loop

        for base, group in pairs(TimerStore) do
            local timer = assert(uv.new_timer())
            local tick = 0
            local threshold = base

            timer:start(0, base, vim.schedule_wrap(function()
                tick = tick + 1
                local elapsed = tick * base
                local queue, qn = {}, 0

                for interval, comp_ids in pairs(group) do
                    if elapsed % interval == 0 then
                        for i = 1, #comp_ids do
                            local id = comp_ids[i]
                            qn = qn + 1
                            queue[qn] = id
                        end
                    end
                    if threshold % interval ~= 0 then
                        threshold = lcm(threshold, interval)
                    end
                end

                if qn > 0 then
                    work(queue)
                    queue, qn = {}, 0
                end

                if elapsed >= threshold then
                    tick = 0
                end
            end))
            Timers[base] = timer
        end
    end)
end

return M
