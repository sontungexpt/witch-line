---@enum DefaultId
local Id = {
	["mode"] = "mode",
	["file.interface"] = "file.interface",
	["file.name"] = "file.name",
	["file.icon"] = "file.icon",
	["file.modifier"] = "file.modifier",
  ["file.size"] = "file.size",
	["copilot"] = "copilot",
	["diagnostic.interface"] = "diagnostic.interface",
	["diagnostic.error"] = "diagnostic.error",
	["diagnostic.warn"] = "diagnostic.warn",
	["diagnostic.info"] = "diagnostic.info",
	["diagnostic.hint"] = "diagnostic.hint",
	["cursor.pos"] = "cursor.pos",
	["cursor.progress"] = "cursor.progress",
	["encoding"] = "encoding",
	["lsp.clients"] = "lsp.clients",
	["indent"] = "indent",

	["git.branch"] = "git.branch",
	["git.diff.interface"] = "git.diff.interface",
	["git.diff.added"] = "git.diff.added",
	["git.diff.removed"] = "git.diff.removed",
	["git.diff.modified"] = "git.diff.modified",

  ["battery"] = "battery",
  ["datetime"] = "datetime",
  ["os_uname"] = "os_uname",


  ["nvim_dap"] = "nvim_dap",


}

return {

	Id = Id,
	--- Check if the id already exists in the default ids.
	--- @param id CompId id to check
	--- @return boolean true if the id exists, false otherwise
	existed = function(id)
		return Id[id] ~= nil
	end,
	--- @param id CompId|nil id to validate
	--- @return CompId? id the id of the component
	validate = function(id)
		if not id then
			require("witch-line.utils.notifier").error("Id must not be null")
		elseif Id[id] then
			require("witch-line.utils.notifier").error("Id must be different from default id: " .. tostring(id))
		end
		return id
	end,
}
