local require = require

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
---
--- | "wl.spell"
--- | "wl.macro.recording"

--- @type table<DefaultId, fun(): DefaultComponent, any>
local Loaders = {
    ["wl.mode"]                 = function() return require("witch-line.components.builtin.mode") end,

    ["wl.file.interface"]       = function() return require("witch-line.components.builtin.file").interface end,
    ["wl.file.name"]            = function() return require("witch-line.components.builtin.file").name end,
    ["wl.file.icon"]            = function() return require("witch-line.components.builtin.file").icon end,
    ["wl.file.modifier"]        = function() return require("witch-line.components.builtin.file").modifier end,
    ["wl.file.size"]            = function() return require("witch-line.components.builtin.file").size end,

    ["wl.copilot"]              = function() return require("witch-line.components.builtin.ai.copilot") end,
    ["wl.codeium"]              = function() return require("witch-line.components.builtin.ai.codeium") end,
    ["wl.codeium.neocodeium"]   = function() return require("witch-line.components.builtin.ai.neocodeium") end,

    ["wl.diagnostic.error"]     = function() return require("witch-line.components.builtin.diagnostic").error end,
    ["wl.diagnostic.warn"]      = function() return require("witch-line.components.builtin.diagnostic").warn end,
    ["wl.diagnostic.info"]      = function() return require("witch-line.components.builtin.diagnostic").info end,
    ["wl.diagnostic.hint"]      = function() return require("witch-line.components.builtin.diagnostic").hint end,

    ["wl.cursor.pos"]           = function() return require("witch-line.components.builtin.cursor").pos end,
    ["wl.cursor.progress"]      = function() return require("witch-line.components.builtin.cursor").progress end,

    ["wl.encoding"]             = function() return require("witch-line.components.builtin.encoding") end,
    ["wl.lsp.clients"]          = function() return require("witch-line.components.builtin.lsp").clients end,
    ["wl.indent"]               = function() return require("witch-line.components.builtin.indent") end,

    ["wl.git.branch"]           = function() return require("witch-line.components.builtin.git").branch end,
    ["wl.git.diff.interface"]   = function() return require("witch-line.components.builtin.git").diff.interface end,
    ["wl.git.diff.added"]       = function() return require("witch-line.components.builtin.git").diff.added end,
    ["wl.git.diff.removed"]     = function() return require("witch-line.components.builtin.git").diff.removed end,
    ["wl.git.diff.modified"]    = function() return require("witch-line.components.builtin.git").diff.modified end,

    ["wl.battery"]              = function() return require("witch-line.components.builtin.battery") end,
    ["wl.datetime"]             = function() return require("witch-line.components.builtin.datetime") end,
    ["wl.os_uname"]             = function() return require("witch-line.components.builtin.os_uname") end,
    ["wl.nvim_dap"]             = function() return require("witch-line.components.builtin.nvim_dap") end,

    ["wl.search.count"]         = function() return require("witch-line.components.builtin.search").count end,
    ["wl.selection.count"]      = function() return require("witch-line.components.builtin.selection").count end,

    ["wl.spell"]                = function() return require("witch-line.components.builtin.spell") end,
    ["wl.macro.recording"]      = function() return require("witch-line.components.builtin.macro") end,
}

--- @type table<DefaultId, DefaultComponent>
local Components = setmetatable({}, {
    __index = function(self, id)
        local loader = Loaders[id]
        return loader and loader()
    end,
})

return Components
