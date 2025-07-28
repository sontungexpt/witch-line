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
---@field [integer] string
---@field ["mode"] 1
---@field ["file.name"] 2
---@field ["file.icon"] 3
---@field ["copilot"] 4
---@field ["diagnostic.error"] 5
---@field ["diagnostic.warn"] 6
---@field ["diagnostic.info"] 7
---@field ["diagnostic.hint"] 8
---@field GitBranch 9
---@field GitAdd 10
---@field GitChange 11
local Id, Size = create_enum({
	"mode",
	"file.name",
	"file.icon",
	"copilot",
	"diagnostic.error",
	"diagnostic.warn",
	"diagnostic.info",
	"diagnostic.hint",
	-- "git.branch",
	-- "GitAdd",
	-- "GitChange",
	-- "GitDelete",
	-- "GitModified",
})

return {
	Id = Id,
	-- helper function to generate an ID based on a number or an enum name
	-- make sure to use this function to avoid conflicts with the enum values
	id = function(id)
		if type(id) == "number" then
			return Id[id] and Size + id or id
		end
		return tostring(id)
	end,
}
