local fn_searchcount = vim.fn.searchcount

local SearchCount = {
    id = "wl.search.count",
    ___builtin = true,
    events = "CmdlineLeave /,?",
    hidden = function(self, _)
        return vim.v.hlsearch == 0
    end,
    update = function(self, _)
        local search = fn_searchcount({ maxcount = 999 })
        if not search or search.total == 0 then return "" end
        return search.current .. "/" .. search.total
    end,
}

return {
    count = SearchCount,
}
