---@alias DefaultId
--- | "wl.mode"
---
--- | "wl.file.interface"
--- | "wl.file.name"
--- | "wl.file.icon"
--- | "wl.file.modifier"
--- | "wl.file.size"
---
--- | "wl.copilot"
--- | "wl.codeium"
--- | "wl.codeium.neocodeium"
---
--- | "wl.diagnostic.interface"
--- | "wl.diagnostic.error"
--- | "wl.diagnostic.warn"
--- | "wl.diagnostic.info"
--- | "wl.diagnostic.hint"
---
--- | "wl.cursor.pos"
--- | "wl.cursor.progress"
---
--- | "wl.encoding"
--- | "wl.lsp.clients"
--- | "wl.indent"
---
--- | "wl.git.branch"
--- | "wl.git.diff.interface"
--- | "wl.git.diff.added"
--- | "wl.git.diff.removed"
--- | "wl.git.diff.modified"
---
--- | "wl.battery"
--- | "wl.datetime"
--- | "wl.os_uname"
--- | "wl.nvim_dap"
---
--- | "wl.search.count"
--- | "wl.selection.count"

--- @type table<DefaultId, fun(): DefaultComponent, any>
local Loaders = {
    ["wl.mode"]                 = function() return require("witch-line.component.mode") end,

    ["wl.file.interface"]       = function() return require("witch-line.component.file").interface end,
    ["wl.file.name"]            = function() return require("witch-line.component.file").name end,
    ["wl.file.icon"]            = function() return require("witch-line.component.file").icon end,
    ["wl.file.modifier"]        = function() return require("witch-line.component.file").modifier end,
    ["wl.file.size"]            = function() return require("witch-line.component.file").size end,

    ["wl.copilot"]              = function() return require("witch-line.component.ai.copilot") end,
    ["wl.codeium"]              = function() return require("witch-line.component.ai.codeium.codeium") end,
    ["wl.codeium.neocodeium"]   = function() return require("witch-line.component.ai.codeium.neocodeium") end,

    ["wl.diagnostic.interface"] = function() return require("witch-line.component.diagnostic").interface end,
    ["wl.diagnostic.error"]     = function() return require("witch-line.component.diagnostic").error end,
    ["wl.diagnostic.warn"]      = function() return require("witch-line.component.diagnostic").warn end,
    ["wl.diagnostic.info"]      = function() return require("witch-line.component.diagnostic").info end,
    ["wl.diagnostic.hint"]      = function() return require("witch-line.component.diagnostic").hint end,

    ["wl.cursor.pos"]           = function() return require("witch-line.component.cursor").pos end,
    ["wl.cursor.progress"]      = function() return require("witch-line.component.cursor").progress end,

    ["wl.encoding"]             = function() return require("witch-line.component.encoding") end,
    ["wl.lsp.clients"]          = function() return require("witch-line.component.lsp").clients end,
    ["wl.indent"]               = function() return require("witch-line.component.indent") end,

    ["wl.git.branch"]           = function() return require("witch-line.component.git").branch end,
    ["wl.git.diff.interface"]   = function() return require("witch-line.component.git").diff.interface end,
    ["wl.git.diff.added"]       = function() return require("witch-line.component.git").diff.added end,
    ["wl.git.diff.removed"]     = function() return require("witch-line.component.git").diff.removed end,
    ["wl.git.diff.modified"]    = function() return require("witch-line.component.git").diff.modified end,

    ["wl.battery"]              = function() return require("witch-line.component.battery") end,
    ["wl.datetime"]             = function() return require("witch-line.component.datetime") end,
    ["wl.os_uname"]             = function() return require("witch-line.component.os_uname") end,
    ["wl.nvim_dap"]             = function() return require("witch-line.component.nvim_dap") end,

    ["wl.search.count"]         = function() return require("witch-line.component.search").count end,
    ["wl.selection.count"]      = function() return require("witch-line.component.selection").count end,
}

--- @type table<DefaultId, DefaultComponent>
local Components = {}

setmetatable(Components, {
    __index = function(self, id)
        local loader = Loaders[id]
        return loader and loader()
    end,
})

return Components
