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
---@field ["file.interface"] 2
---@field ["file.name"] 3
---@field ["file.icon"] 4
---@field ["copilot"] 5
---@field ["diagnostic.interface"] 6
---@field ["diagnostic.error"] 7
---@field ["diagnostic.warn"] 8
---@field ["diagnostic.info"] 9
---@field ["diagnostic.hint"] 10
---@field ["cursor.pos"] 11
---@field ["cursor.progress"] 12
---@field ["encoding"] 13
local Id, Size = create_enum({
	[1] = "mode",
	[2] = "file.interface",
	[3] = "file.name",
	[4] = "file.icon",
	[5] = "copilot",
	[6] = "diagnostic.interface",
	[7] = "diagnostic.error",
	[8] = "diagnostic.warn",
	[9] = "diagnostic.info",
	[10] = "diagnostic.hint",
	[11] = "cursor.pos",
	[12] = "cursor.progress",
	[13] = "encoding",

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
