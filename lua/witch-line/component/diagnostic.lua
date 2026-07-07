local DiagnosticSeverity = vim.diagnostic.severity

local DEBUG_LOG = ("/tmp/witch-line-debug-%s.log"):format(vim.fn.getpid())
local function debug_log(...)
    vim.fn.writefile({ os.date("%H:%M:%S") .. " " .. table.concat({...}, " ") }, DEBUG_LOG, "a")
end

--- @type DefaultId
local InterfaceId = "wl.diagnostic.interface"

--- @type DefaultComponent
local Interface = {
    id = InterfaceId,
    ___builtin = true,
    abstract = true,

    events = "DiagnosticChanged",
    static = {
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
        for id, value in pairs(self.static.icons) do
            icons[id] = value
        end
        local signs = vim.diagnostic.config().signs
        if type(signs) == "table" then
            local text = signs.text
            if type(text) == "table" then
                for id, value in pairs(icons) do
                    icons[id] = text[id] or text[DiagnosticSeverity[id]] or value
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
        debug_log("DIAG_ERROR update", "self.id=" .. tostring(self.id))
        debug_log("DIAG_ERROR context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("DIAG_ERROR ctx", type(ctx))
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
        debug_log("DIAG_WARN update", "self.id=" .. tostring(self.id))
        debug_log("DIAG_WARN context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("DIAG_WARN ctx", type(ctx))
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
        debug_log("DIAG_INFO update", "self.id=" .. tostring(self.id))
        debug_log("DIAG_INFO context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("DIAG_INFO ctx", type(ctx))
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
        debug_log("DIAG_HINT update", "self.id=" .. tostring(self.id))
        debug_log("DIAG_HINT context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("DIAG_HINT ctx", type(ctx))
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
