local vim, type, next, pcall = vim, type, next, pcall
local api = vim.api
local nvim_set_hl, nvim_get_hl, nvim_get_color_by_name = api.nvim_set_hl, api.nvim_get_hl, api.nvim_get_color_by_name
local shallow_copy = require("witch-line.utils.tbl").shallow_copy

local M = {}

local Cache = {
	color_nums = {},
	hl_styles = {},
}

do
	local counter = nil
	function M.reset_counter()
		counter = nil
	end
	function M.gen_hl_name()
		counter = (counter or 0) + 1
		return "Witchline" .. counter
	end
end

--- Generates a highlight name based on an ID.
--- @param id any The ID to generate the highlight name for.
--- @return string hl_name The generated highlight name.
M.gen_hl_name_by_id = function(id)
	return "WL" .. string.gsub(tostring(id), "[^%w_]", "")
end

-- Convert color names to 24-bit RGB numbers
--- @param color string The color name to convert.
local function color_to_24bit(color)
	local c = Cache.color_nums[color]
	if c then
		return c
	end

	local num = nvim_get_color_by_name(color)
	if num ~= -1 then
		Cache.color_nums[color] = num
	end
	return num
end

--- Adds a highlight name to a string.
--- @param str string The string to which the highlight name will be added.
--- @param hl_name string The highlight name to add.
M.add_hl_name = function(str, hl_name)
	return hl_name and str ~= "" and "%#" .. hl_name .. "#" .. str .. "%*" or str
end

M.is_hl_name = function(hl_name)
	return type(hl_name) == "string" and hl_name ~= ""
end

M.is_hl_styles = function(hl_styles)
	return type(hl_styles) == "table" and next(hl_styles)
end

--- Retrieves the highlight information for a given highlight group name.
---@param hl_name string
---@return vim.api.keyset.get_hl_info|nil
local get_hlprop = function(hl_name, force)
	local c = Cache.hl_styles[hl_name]
	if not force and c then
		return c
	elseif hl_name == "" then
		return nil
	end

	local ok, style = pcall(nvim_get_hl, 0, {
		name = hl_name,
	})

	if ok then
		Cache.hl_styles[hl_name] = style
		return style
	end
	return nil
end

M.get_hlprop = get_hlprop

---@param group_name string
---@param hl_style vim.api.keyset.highlight
M.hl = function(group_name, hl_style, force)
	if group_name == "" or type(hl_style) ~= "table" or not next(hl_style) then
		return
	end
	local style = Cache.hl_styles[group_name]
	if not force and style then
		nvim_set_hl(0, group_name, style)
		return
	end
	style = shallow_copy(hl_style)

	local fg = style.foreground or style.fg
	local bg = style.background or style.bg

	if type(fg) == "string" then
		if fg ~= "NONE" then
			local num = color_to_24bit(fg)
			if num == -1 then
				local hl_prop = get_hlprop(fg)
				fg = hl_prop and hl_prop.fg
			else
				fg = num
			end
		end
	end

	if type(bg) == "string" then
		if bg ~= "NONE" then
			local num = color_to_24bit(bg)
			if num == -1 then
				local hl_prop = get_hlprop(bg)
				bg = hl_prop and hl_prop.bg
			else
				-- 24-bit RGB color
				bg = num
			end
		end
	end

	if bg == nil then
		bg = "NONE"
		-- bg = M.get_hl("StatusLine").bg
	end

	style.foreground, style.background = fg, bg
	style.fg, style.bg = nil, nil

	Cache.hl_styles[group_name] = style
	nvim_set_hl(0, group_name, style)
end

return M
