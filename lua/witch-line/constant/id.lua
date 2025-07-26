---@generic T: string, I: integer
---@param list T[]
---@return table<T, I> | table<I, T>
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
	return enum
end

---@class DefaultId
---@field Mode 1
---@field FileName 2
---@field FileIcon 3
---@field Copilot 4
local Id = create_enum({
	"Mode",
	"FileName",
	"FileIcon",
	"Copilot",
})

return Id
