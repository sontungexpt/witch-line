local pairs = pairs
local M = {}

function M.merge_tbl(to, from, skip_type_check)
	if to == nil then
		return from
	elseif from == nil then
		return to
	end

	local to_type = type(to)
	local from_type = type(from)

	if not skip_type_check and to_type ~= from_type then
		return to
	elseif from_type ~= "table" then
		return from
	elseif to_type == "table" then
		if vim.islist(to) and vim.islist(from) then
			-- If both are lists, merge them
			for _, v in ipairs(from) do
				to[#to + 1] = v
			end
			return to
		end

		for k, v in pairs(from) do
			to[k] = M.merge_tbl(to[k], v, skip_type_check)
		end
	end
	return to
end

function M.tbl_keys(tbl)
	local list, size = {}, 0
	for k, _ in pairs(tbl) do
		size = size + 1
		list[size] = k
	end
	return list, size
end

return M
