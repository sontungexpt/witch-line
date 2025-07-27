---@generic T: string, I: integer
---@param list T[]
---@return table<T, I> | table<I, T>
---@return integer size the total number of unique items in the list
local function create_enum(list)
	local enum = {}
	local id = 0
	for i = 1, #list do
		local name = list[i]
		if not enum[name] then
			id = id + 1
			enum[name] = id
			enum[id] = name
		end
	end
	return enum, id
end

---@class DefaultId
---@field Mode 1
---@field FileName 2
---@field FileIcon 3
---@field Copilot 4
---@field DiagnosticError 5
---@field DiagnosticWarn 6
---@field DiagnosticInfo 7
---@field DiagnosticHint 8
---@field GitBranch 9
---@field GitAdd 10
---@field GitChange 11
local Id, Size = create_enum({
	"Mode",
	"FileName",
	"FileIcon",
	"Copilot",
	"DiagnosticError",
	"DiagnosticWarn",
	"DiagnosticInfo",
	"DiagnosticHint",
	"GitBranch",
	"GitAdd",
	"GitChange",
	"GitDelete",
	"GitModified",
})

return {
	Id = Id,
	-- helper function to generate an ID based on a number or an enum name
	-- make sure to use this function to avoid conflicts with the enum values
	id = function(id)
		if type(id) ~= "number" or not Id[id] then
			return id
		end
		return Size + id
	end,
}
