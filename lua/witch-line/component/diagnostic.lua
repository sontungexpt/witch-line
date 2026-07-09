local diagnostic = vim.diagnostic
local DiagnosticSeverity = diagnostic.severity

--- @type DefaultId
local InterfaceId = "wl.diagnostic.interface"

--- @type DefaultComponent
local Interface = {
    id = InterfaceId,
    ___builtin = true,
    abstract = true,
    events = "DiagnosticChanged",
    config = {
        icons = {
            [DiagnosticSeverity.ERROR] = "",
            [DiagnosticSeverity.WARN] = "",
            [DiagnosticSeverity.INFO] = "",
            [DiagnosticSeverity.HINT] = "",
        },
    },
    hidden = function(self, _)
        return vim.bo.filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
    end,
    ---@param self ManagedComponent
    ---@return {count: table, icon: table}
    context = function(self)
        local icons = {}
        for id, value in pairs(self.config.icons) do
            icons[id] = value
        end
        local signs = diagnostic.config().signs
        if type(signs) == "table" then
            local text = signs.text
            if type(text) == "table" then
                for id, value in pairs(icons) do
                    icons[id] = text[id] or text[DiagnosticSeverity[id]] or value
                end
            end
        end
        return {
            count = diagnostic.count(0),
            icon = icons,
        }
    end,
}

local SHARED_REF = {
    events = InterfaceId,
    hidden = InterfaceId,
    context = InterfaceId
}

--- @type DefaultComponent
local Error = {
    id = "wl.diagnostic.error",
    ___builtin = true,
    ref = SHARED_REF,
    style = { fg = "DiagnosticError" },
    update = function(self, session)
        local ctx = self.context(self, session)
        local id = DiagnosticSeverity.ERROR
        local count = ctx.count[id] or 0
        return count > 0 and ctx.icon[id] .. " " .. count or ""
    end,
}

--- @type DefaultComponent
local Warn = {
    id = "wl.diagnostic.warn",
    ___builtin = true,
    ref = SHARED_REF,
    style = { fg = "DiagnosticWarn" },
    update = function(self, session)
        local ctx = self.context(self, session)
        local id = DiagnosticSeverity.WARN
        local count = ctx.count[id] or 0
        return count > 0 and ctx.icon[id] .. " " .. count or ""
    end,
}

--- @type DefaultComponent
local Info = {
    id = "wl.diagnostic.info",
    ___builtin = true,
    ref = SHARED_REF,
    style = { fg = "DiagnosticInfo" },
    update = function(self, session)
        local ctx = self.context(self, session)
        local id = DiagnosticSeverity.INFO
        local count = ctx.count[id] or 0
        return count > 0 and ctx.icon[id] .. " " .. count or ""
    end,
}

--- @type DefaultComponent
local Hint = {
    id = "wl.diagnostic.hint",
    ___builtin = true,
    ref = SHARED_REF,
    style = { fg = "DiagnosticHint" },
    update = function(self, session)
        local ctx = self.context(self, session)
        local id = DiagnosticSeverity.HINT
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
