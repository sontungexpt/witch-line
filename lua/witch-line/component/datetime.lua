---@type DefaultComponent
return {
    id = "wl.datetime",
    ___builtin = true,
    timing = true,
    static = {
        format = "default",
    },
    update = function(self, _)
        local static = self.static
        --- @cast  static {format: string}
        local fmt = static.format or "default"
        --- @cast fmt string
        if fmt == "default" then
            fmt = "%A, %B %d | %H.%M"
        elseif fmt == "us" then
            fmt = "%m/%d/%Y"
        elseif fmt == "uk" then
            fmt = "%d/%m/%Y"
        elseif fmt == "iso" then
            fmt = "%Y-%m-%d"
        end
        return tostring(os.date(fmt))
    end,
}
