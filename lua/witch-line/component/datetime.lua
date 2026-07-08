---@type DefaultComponent
return {
    id = "wl.datetime",
    ___builtin = true,
    timing = true,
    config = {
        format = "default",
    },
    update = function(self, _)
        local fmt = self.config.format
        if fmt == "default" then
            fmt = "%A, %B %d | %H.%M"
        elseif fmt == "us" then
            fmt = "%m/%d/%Y"
        elseif fmt == "uk" then
            fmt = "%d/%m/%Y"
        elseif fmt == "iso" then
            fmt = "%Y-%m-%d"
        end
        return os.date(fmt)
    end,
}
