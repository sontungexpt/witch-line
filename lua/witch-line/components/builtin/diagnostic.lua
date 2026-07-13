local diagnostic = vim.diagnostic
local DiagnosticSeverity = diagnostic.severity

--- Get the diagnostic count for a given severity.
--- @return table<vim.diagnostic.Severity, integer>
local get_diag_count = function()
    return diagnostic.count(0)
end


--- Get the signs icon from the diagnostic config.
--- @return table
local get_config_signs_icon = function()
    local signs = diagnostic.config().signs
    if type(signs) == "table" then
        local text = signs.text
        if type(text) == "table" then
            return text
        end
    end
    return {}
end

local hidden = function()
    return vim.bo.filetype == "lazy" or vim.api.nvim_buf_get_name(0):match("%.env$")
end

--- @param self DefaultComponent
--- @param severity vim.diagnostic.Severity
--- @param session Session
local update_value = function(self, severity, session)
    local cache = session:cache()
    if cache:memo(hidden) then
        return ""
    end

    local config = self.config
    --- @cast config {icon: string}
    local icon = config.icon or cache:memo(get_config_signs_icon)[severity] or ""
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
    error = Error,
    warn = Warn,
    info = Info,
    hint = Hint,
}
