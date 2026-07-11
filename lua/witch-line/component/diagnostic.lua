local diagnostic = vim.diagnostic
local DiagnosticSeverity = diagnostic.severity

local get_diag_count = function()
    return diagnostic.count(0)
end

local get_config_signs_text = function()
    local signs = diagnostic.config().signs
    if type(signs) == "table" then
        local text = signs.text
        if type(text) == "table" then
            return text
        end
    end
    return {}
end

local hidden = function(self, session)
    return vim.bo.filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
end

local update_value = function(self, severity, session)
    if hidden(self, session) then
        return ""
    end

    local cache = session:cache()
    local config = self.config
    local icon = config.icon or cache:memo(get_config_signs_text)[severity] or ""
    local count = cache:memo(get_diag_count)[severity] or 0
    return count > 0 and (icon ~= "" and icon .. " " or "") .. count or ""
end


--- @type DefaultComponent
local Error = {
    id = "wl.diagnostic.error",
    ___builtin = true,
    events = "DiagnosticChanged",
    style = { fg = "DiagnosticError" },
    config = {
        icon = ""
    },
    update = function(self, session)
        return update_value(self, DiagnosticSeverity.ERROR, session)
    end,
}

--- @type DefaultComponent
local Warn = {
    id = "wl.diagnostic.warn",
    ___builtin = true,
    events = "DiagnosticChanged",
    style = { fg = "DiagnosticWarn" },
    config = {
        icon = ""
    },
    update = function(self, session)
        return update_value(self, DiagnosticSeverity.WARN, session)
    end,
}

--- @type DefaultComponent
local Info = {
    id = "wl.diagnostic.info",
    ___builtin = true,
    events = "DiagnosticChanged",
    style = { fg = "DiagnosticInfo" },
    config = {
        icon = ""
    },
    update = function(self, session)
        return update_value(self, DiagnosticSeverity.INFO, session)
    end,
}

--- @type DefaultComponent
local Hint = {
    id = "wl.diagnostic.hint",
    ___builtin = true,
    events = "DiagnosticChanged",
    config = {
        icon = ""
    },
    style = { fg = "DiagnosticHint" },
    update = function(self, session)
        return update_value(self, DiagnosticSeverity.HINT, session)
    end,
}

return {
    interface = Interface,
    error = Error,
    warn = Warn,
    info = Info,
    hint = Hint,
}
