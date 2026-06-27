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
--- | "wl.windsurf"
--- | "wl.windsurf.neocodeium"
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
--- | "wl.weather.location"
--- | "wl.weather.data"
--- | "wl.weather.icon"
--- | "wl.weather.temp"
--- | "wl.weather.text"
--- | "wl.weather"

--- Identity map for default component IDs.
--- @type table<DefaultId, DefaultId>
local Id = {}

--- @type table<DefaultId, string[]>
local PathMap = {
    ["wl.mode"]                 = { "mode" },

    ["wl.file.interface"]       = { "file", "interface" },
    ["wl.file.name"]            = { "file", "name" },
    ["wl.file.icon"]            = { "file", "icon" },
    ["wl.file.modifier"]        = { "file", "modifier" },
    ["wl.file.size"]            = { "file", "size" },

    ["wl.copilot"]              = { "ai.copilot" },
    ["wl.windsurf"]             = { "ai.windsurf", "windsurf" },
    ["wl.windsurf.neocodeium"]  = { "ai.windsurf", "neocodeium" },

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

    ["wl.weather.location"]     = { "weather", "location" },
    ["wl.weather.data"]         = { "weather", "data" },
    ["wl.weather.icon"]         = { "weather", "icon" },
    ["wl.weather.temp"]         = { "weather", "temp" },
    ["wl.weather.text"]         = { "weather", "text" },
    ["wl.weather"]              = { "weather" },
}


return {
    ---@param id CompId
    ---@return string[]|nil
    path = function(id) return PathMap[id] end,

    ---@param id CompId
    ---@return boolean
    existed = function(id) return PathMap[id] ~= nil end,

    --- Validate a user-provided id string.
    --- An error is emitted if the id collides with a built-in DefaultId.
    ---@param id string
    ---@return string?
    validate = function(id)
        local notifier = require("witch-line.utils.notifier")
        if type(id) ~= "string" then
            notifier.error("Id must be a string")
        elseif PathMap[id] then
            notifier.error("Id must be different from default id: " .. tostring(id))
        end
        return id
    end,
}
