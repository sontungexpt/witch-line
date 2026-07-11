--- Debug logging to a file.
---
--- Usage:
--- ```lua
--- local log = require("witch-line.util.debug_file")("/tmp/witch-debug.log")
--- log("hello %s", "world")
--- log("count: %d", 42)
--- ```
---
--- To disable, pass `false` or a falsy path.

local io_open = io.open

--- @param path string|false File path, or `false` to disable.
--- @return fun(msg: string, ...): nil
return function(path)
    if not path then
        return function() end
    end

    return function(msg, ...)
        if ... then
            msg = string.format(msg, ...)
        end
        local f, err = io_open(path, "a")
        if f then
            f:write(msg, "\n")
            f:close()
        elseif not rawget(_G, "_witch_debug_warned") then
            vim.notify("[witch] debug_file error: " .. tostring(err), vim.log.levels.WARN)
            _G._witch_debug_warned = true
        end
    end
end
