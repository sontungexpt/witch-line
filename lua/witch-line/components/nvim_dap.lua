--- @type DefaultComponent
return {
    id = "nvim_dap",
    _plug_provided = true,
    events = { "CursorHold", "CursorMoved", "BufEnter" },
    update = function()
        return require("dap").status()
    end,
    hidden = function()
        local session = require("dap").session()
        return session == nil
    end,
}
