--- Default component identifiers.
---
--- Each ID may contain two parts separated by a null byte (`\0`):
---   - The first part represents the **module name**.
---   - The second part represents the **component name** inside that module.
---
--- This avoids conflicts with dots (`.`) in normal module paths.
---
--- Examples:
--- - `"file\0name"` means the component `name` from the module `file`.
--- - `"git\0status"` means the component `status` from the module `git`.
--- - `"file.name"` (with dot) would normally refer to a file named `"file/name.lua"`,
---   so the null separator ensures proper distinction.
---@class DefaultComponentPath : string

---@enum DefaultId
local IdPathMap = {
	["mode"] = "mode",
	["file.interface"] = "file\0interface",
	["file.name"] = "file\0name",
	["file.icon"] = "file\0icon",
	["file.modifier"] = "file\0modifier",
  ["file.size"] = "file\0size",
	["copilot"] = "copilot",
	["diagnostic.interface"] = "diagnostic\0interface",
	["diagnostic.error"] = "diagnostic\0error",
	["diagnostic.warn"] = "diagnostic\0warn",
	["diagnostic.info"] = "diagnostic\0info",
	["diagnostic.hint"] = "diagnostic\0hint",
	["cursor.pos"] = "cursor\0pos",
	["cursor.progress"] = "cursor\0progress",
	["encoding"] = "encoding",
	["lsp.clients"] = "lsp\0clients",
	["indent"] = "indent",

	["git.branch"] = "git\0branch",
	["git.diff.interface"] = "git\0diff.interface",
	["git.diff.added"] = "git\0diff.added",
	["git.diff.removed"] = "git\0diff.removed",
	["git.diff.modified"] = "git\0diff.modified",

  ["battery"] = "battery",
  ["datetime"] = "datetime",
  ["os_uname"] = "os_uname",
  ["nvim_dap"] = "nvim_dap",
}

--- Metatable to access default component IDs with error handling.
--- @class DefaultComponentIds
--- @field ["mode"] DefaultId
--- @field ["file.interface"] DefaultId
--- @field ["file.name"] DefaultId
--- @field ["file.icon"] DefaultId
--- @field ["file.modifier"] DefaultId
--- @field ["file.size"] DefaultId
--- @field ["copilot"] DefaultId
--- @field ["diagnostic.interface"] DefaultId
--- @field ["diagnostic.error"] DefaultId
--- @field ["diagnostic.warn"] DefaultId
--- @field ["diagnostic.info"] DefaultId
--- @field ["diagnostic.hint"] DefaultId
--- @field ["cursor.pos"] DefaultId
--- @field ["cursor.progress"] DefaultId
--- @field ["encoding"] DefaultId
--- @field ["lsp.clients"] DefaultId
--- @field ["indent"] DefaultId
--- @field ["git.branch"] DefaultId
--- @field ["git.diff.interface"] DefaultId
--- @field ["git.diff.added"] DefaultId
--- @field ["git.diff.removed"] DefaultId
--- @field ["git.diff.modified"] DefaultId
--- @field ["battery"] DefaultId
--- @field ["datetime"] DefaultId
--- @field ["os_uname"] DefaultId
--- @field ["nvim_dap"] DefaultId
local Id = setmetatable({}, {
  __index = function(_, key)
    if IdPathMap[key] then
      return key
    else
      error("Id '" .. tostring(key) .. "' does not exist in default ids.")
    end
  end,
})

--- @cast IdPathMap table<CompId, DefaultComponentPath>
return {
  Id = Id,

  --- Get the path of the id.
  --- @param id CompId id to get the path
  --- @return DefaultComponentPath|nil path of the id, or nil if not found
  path = function (id)
    return IdPathMap[id]
  end,

	--- Check if the id already exists in the default ids.
	--- @param id CompId id to check
	--- @return boolean true if the id exists, false otherwise
	existed = function(id)
		return IdPathMap[id] ~= nil
	end,

	--- @param id CompId|nil id to validate
	--- @return CompId? id the id of the component
	validate = function(id)
		if not id then
			require("witch-line.utils.notifier").error("Id must not be null")
		elseif IdPathMap[id] then
			require("witch-line.utils.notifier").error("Id must be different from default id: " .. tostring(id))
		end
		return id
	end,
}
