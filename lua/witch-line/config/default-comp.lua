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
---



--- @type table<DefaultId, string[]>
local IdPathMap = {
    ["wl.mode"]                 = { "mode" },

    ["wl.file.interface"]       = { "file", "interface" },
    ["wl.file.name"]            = { "file", "name" },
    ["wl.file.icon"]            = { "file", "icon" },
    ["wl.file.modifier"]        = { "file", "modifier" },
    ["wl.file.size"]            = { "file", "size" },

    ["wl.copilot"]              = { "ai.copilot" },
    ["wl.codeium"]             = { "ai.codeium", "codeium" },
    ["wl.codeium.neocodeium"]  = { "ai.codeium", "neocodeium" },

    ["wl.diagnostic.interface"] = { "diagnostic", "interface" },
    ["wl.diagnostic.error"]     = { "diagnostic", "error" },
    ["wl.diagnostic.warn"]      = { "diagnostic", "warn" },
    ["wl.diagnostic.info"]      = { "diagnostic", "info" },
    ["wl.diagnostic.hint"]      = { "diagnostic", "hint" },

    ["wl.cursor.pos"]           = { "cursor", "pos" },
    ["wl.cursor.progress"]      = { "cursor", "progress" },

    ["wl.encoding"]             = { "encoding" },
    ["wl.lsp.clients"]          = { "lsp", "clients" },
    ["wl.indent"]               = { "indent" },

    ["wl.git.branch"]           = { "git", "branch" },
    ["wl.git.diff.interface"]   = { "git", "diff", "interface" },
    ["wl.git.diff.added"]       = { "git", "diff", "added" },
    ["wl.git.diff.removed"]     = { "git", "diff", "removed" },
    ["wl.git.diff.modified"]    = { "git", "diff", "modified" },

    ["wl.battery"]              = { "battery" },
    ["wl.datetime"]             = { "datetime" },
    ["wl.os_uname"]             = { "os_uname" },
    ["wl.nvim_dap"]             = { "nvim_dap" },

    ["wl.search.count"]         = { "search", "count" },
    ["wl.selection.count"]      = { "selection", "count" },
}

local COMP_CONTAINER = "witch-line.component."

--- @type table<DefaultId, DefaultComponent>
local CompMap = {}
setmetatable(CompMap, {
    --- Load a component by its module path id (derived from a DefaultId).
    --- Falls back to Component.require internally.
    --- @param id CompId
    --- @return DefaultComponent|nil
    __index = function(_, id)
        local paths = IdPathMap[id]
        if not paths then return nil end
        local component = require(COMP_CONTAINER .. paths[1])

        local i = 2
        local key = paths[i]
        while key do
            component = component[key]
            if component == nil then
                return nil
            end

            i = i + 1
            key = paths[i]
        end
        return component
    end,
})

return CompMap
