local unpack = unpack

--- Debounces a function, ensuring it is only called after a specified delay.
--- @generic Fn
--- @param func Fn  The function to debounce.
--- @param delay integer  The delay in milliseconds.
--- @return Fn  The debounced function.
return function(func, delay)
    local timer, args

    local cb = vim.schedule_wrap(function()
        func(unpack(args))
    end)

    return function(...)
        if timer == nil then
            timer = assert((vim.uv or vim.loop).new_timer())
        end

        args = { ... }

        timer:stop()
        timer:start(delay, 0, cb)
    end
end
