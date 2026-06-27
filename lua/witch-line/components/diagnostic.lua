local DiagnosticSevrity = vim.diagnostic.severity

--- @type DefaultComponent
local Interface = {
    id = "wl.diagnostic.interface",
    _plug_provided = true,
    events = "DiagnosticChanged",
    static = {
        icons = {
            [DiagnosticSevrity.ERROR] = "",
            [DiagnosticSevrity.WARN] = "",
            [DiagnosticSevrity.INFO] = "",
            [DiagnosticSevrity.HINT] = "",
        },
    },
    hidden = function(self, _)
        return vim.bo.filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
    end,
    ---@param self ManagedComponent
    ---@return {count: table, icon: table}
    context = function(self)
        local icons = {}
        for id, value in pairs(self.static.icons) do
            icons[id] = value
        end
        local signs = vim.diagnostic.config().signs
        if type(signs) == "table" then
            local text = signs.text
            if type(text) == "table" then
                local severity = vim.diagnostic.severity
                for id, value in pairs(icons) do
                    icons[id] = text[id] or text[severity[id]] or value
                end
            end
        end
        return {
            count = vim.diagnostic.count(0),
            icon = icons,
        }
    end,
}
local SHARED_REF = {
    events = "wl.diagnostic.interface",
    context = "wl.diagnostic.interface",
    hidden = "wl.diagnostic.interface",
}

--- @type DefaultComponent
local Error = {
    id = "wl.diagnostic.error",
    _plug_provided = true,
    style = { fg = "DiagnosticError" },
    ref = SHARED_REF,
    update = function(self, session)
        local ctx = self:with_session(session).context(self, session)
        local id = vim.diagnostic.severity.ERROR
        local count = ctx.count[id] or 0
        return count > 0 and ctx.icon[id] .. " " .. count or ""
    end,
}

--- @type DefaultComponent
local Warn = {
    id = "wl.diagnostic.warn",
    _plug_provided = true,
    ref = SHARED_REF,
    style = { fg = "DiagnosticWarn" },
    update = function(self, session)
        local ctx = self:with_session(session).context(self, session)
        local id = vim.diagnostic.severity.WARN
        local count = ctx.count[id] or 0
        return count > 0 and ctx.icon[id] .. " " .. count or ""
    end,
}

--- @type DefaultComponent
local Info = {
    id = "wl.diagnostic.info",
    _plug_provided = true,
    ref = SHARED_REF,
    style = { fg = "DiagnosticInfo" },
    update = function(self, session)
        local ctx = self:with_session(session).context(self, session)
        local id = vim.diagnostic.severity.INFO
        local count = ctx.count[id] or 0
        return count > 0 and ctx.icon[id] .. " " .. count or ""
    end,
}

--- @type DefaultComponent
local Hint = {
    id = "wl.diagnostic.hint",
    _plug_provided = true,
    ref = SHARED_REF,
    style = { fg = "DiagnosticHint" },
    update = function(self, session)
        local ctx = self:with_session(session).context(self, session)
        local id = vim.diagnostic.severity.HINT
        local count = ctx.count[id] or 0
        return count > 0 and ctx.icon[id] .. " " .. count or ""
    end,
}

return {
    interface = Interface,
    error = Error,
    warn = Warn,
    info = Info,
    hint = Hint,
}
