local unpack = unpack

return function(func, delay)
    local timer, args

    local cb = vim.schedule_wrap(function()
        func(unpack(args))
    end)

    return function(...)
        if not timer then
            timer = assert((vim.uv or vim.loop).new_timer())
        end

        args = { ... }

        timer:stop()
        timer:start(delay, 0, cb)
    end
end
