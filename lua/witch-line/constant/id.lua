---@alias DefaultId
--- | CompId
---
--- | "mode"
---
--- | "file.interface"
--- | "file.name"
--- | "file.icon"
--- | "file.modifier"
--- | "file.size"
---
--- | "copilot"
--- | "windsurf"
--- | "windsurf.neocodeium"
---
--- | "diagnostic.interface"
--- | "diagnostic.error"
--- | "diagnostic.warn"
--- | "diagnostic.info"
--- | "diagnostic.hint"
---
--- | "cursor.pos"
--- | "cursor.progress"
---
--- | "encoding"
--- | "lsp.clients"
--- | "indent"
---
--- | "git.branch"
--- | "git.diff.interface"
--- | "git.diff.added"
--- | "git.diff.removed"
--- | "git.diff.modified"
---
--- | "battery"
--- | "datetime"
--- | "os_uname"
--- | "nvim_dap"
---
--- | "search.count"
--- | "selection.count"
---
--- | "weather.location"
--- | "weather.data"
--- | "weather.icon"
--- | "weather.temp"
--- | "weather.text"
--- | "weather"


--- @type table<DefaultId, string[]>
local PathMap = {
    mode                     = { "mode" },

    ["file.interface"]       = { "file", "interface" },
    ["file.name"]            = { "file", "name" },
    ["file.icon"]            = { "file", "icon" },
    ["file.modifier"]        = { "file", "modifier" },
    ["file.size"]            = { "file", "size" },

    ["copilot"]              = { "ai.copilot" },
    ["windsurf"]             = { "ai.windsurf", "windsurf" },
    ["windsurf.neocodeium"]  = { "ai.windsurf", "neocodeium" },

    ["diagnostic.interface"] = { "diagnostic", "interface" },
    ["diagnostic.error"]     = { "diagnostic", "error" },
    ["diagnostic.warn"]      = { "diagnostic", "warn" },
    ["diagnostic.info"]      = { "diagnostic", "info" },
    ["diagnostic.hint"]      = { "diagnostic", "hint" },

    ["cursor.pos"]           = { "cursor", "pos" },
    ["cursor.progress"]      = { "cursor", "progress" },

    encoding                 = { "encoding" },
    ["lsp.clients"]          = { "lsp", "clients" },
    indent                   = { "indent" },

    ["git.branch"]           = { "git", "branch" },
    ["git.diff.interface"]   = { "git", "diff", "interface" },
    ["git.diff.added"]       = { "git", "diff", "added" },
    ["git.diff.removed"]     = { "git", "diff", "removed" },
    ["git.diff.modified"]    = { "git", "diff", "modified" },

    battery                  = { "battery" },
    datetime                 = { "datetime" },
    os_uname                 = { "os_uname" },
    nvim_dap                 = { "nvim_dap" },

    ["search.count"]         = { "search", "count" },
    ["selection.count"]      = { "selection", "count" },

    ["weather.location"]     = { "weather", "location" },
    ["weather.data"]         = { "weather", "data" },
    ["weather.icon"]         = { "weather", "icon" },
    ["weather.temp"]         = { "weather", "temp" },
    ["weather.text"]         = { "weather", "text" },
    weather                  = { "weather", "weather" },
}

return {
    ---@param id DefaultId
    ---@return string[]|nil
    path = function(id) return PathMap[id] end,

    ---@param id DefaultId
    ---@return boolean
    existed = function(id) return PathMap[id] ~= nil end,

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
