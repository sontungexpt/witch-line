--- @type DefaultComponent
return {
    id = "wl.nvim_dap",
    ___plug_provided = true,
    events = { "CursorHold", "CursorMoved", "BufEnter" },
    update = function()
        return require("dap").status()
    end,
    hidden = function()
        local session = require("dap").session()
        return session == nil
    end,
}
