local vim, type = vim, type
local api = vim.api
local nvim_set_hl, nvim_get_hl, nvim_get_color_by_name = api.nvim_set_hl, api.nvim_get_hl, api.nvim_get_color_by_name
local shallow_copy = require("utils.tbl").shallow_copy

local M = {}
local cache = {
	nums = {},
	styles = {},
}

do
	local counter = 0
	function M.reset_counter()
		counter = 0
	end
	function M.gen_hl_name()
		counter = counter + 1
		return "witch-line" .. counter
	end

	function M.gen_hl_name_by_id(id)
		return "witch-line" .. id
	end
end

-- Convert color names to 24-bit RGB numbers
local function color_to_24bit(color)
	local c = cache.nums[color]
	if c then
		return c
	end
	local num = nvim_get_color_by_name(color)
	if num ~= -1 then
		cache.nums[color] = num
	end
	return -1
end

M.add_hl_name = function(str, hl_name)
	return str ~= "" and "%#" .. hl_name .. "#" .. str .. "%*" or str
end

M.is_hl_name = function(hl_name)
	return type(hl_name) == "string" and hl_name ~= ""
end

M.is_hl_styles = function(hl_styles)
	return type(hl_styles) == "table" and next(hl_styles)
end

--- Retrieves the highlight information for a given highlight group name.
---@param hl_name string
---@return vim.api.keyset.get_hl_info
M.get_hl = function(hl_name)
	local c = cache.styles[hl_name]
	if c then
		return c
	end
	local style = nvim_get_hl(0, { name = hl_name })
	if next(style) then
		cache.styles[hl_name] = style
	end

	return style
end

---@param group_name string
---@param hl_styles vim.api.keyset.highlight
M.hl = function(group_name, hl_styles)
	local styles = shallow_copy(hl_styles)

	local fg = styles.foreground or styles.fg
	local bg = styles.background or styles.bg

	if type(fg) == "string" then
		if fg ~= "NONE" then
			local num = color_to_24bit(fg)
			fg = num ~= -1 and num or M.get_hl(fg).fg
		end
	end

	if type(bg) == "string" then
		if bg ~= "NONE" then
			local num = color_to_24bit(bg)
			bg = num ~= -1 and num or M.get_hl(bg).bg
		end
	end

	if bg == nil then
		bg = M.get_hl("StatusLine").bg
		-- styles.background = M.get_hl("StatusLine").bg
	end

	styles.foreground = fg
	styles.background = bg
	styles.fg = nil
	styles.bg = nil
	pcall(nvim_set_hl, 0, group_name, styles)
end

return M
