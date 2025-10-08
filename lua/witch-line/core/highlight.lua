local vim, type, next, pcall, pairs = vim, type, next, pcall, pairs
local api = vim.api
local nvim_set_hl, nvim_get_hl, nvim_get_color_by_name = api.nvim_set_hl, api.nvim_get_hl, api.nvim_get_color_by_name

local shallow_copy = require("witch-line.utils.tbl").shallow_copy

local M = {}


---@type table<string, integer>
local ColorRgb24Bit = {}

---@type table<string, vim.api.keyset.highlight>
local Styles = {}

--- Retrieves the style for a given component.
--- @param comp Component The component to retrieve the style for.
--- @return table|nil style The style of the component or nil if not found.
M.get_style = function(comp)
	if comp._hl_name then
		return Styles[comp._hl_name]
	end
	return nil
end

--- Inspects the current highlight cache.
--- @param target "rgb24bit"|"styles"|nil target to inspect
M.inspect = function(target)
	local notifier = require("witch-line.utils.notifier")
	if target == "rgb24bit" then
		notifier.info(vim.inspect(ColorRgb24Bit))
	elseif target == "styles" then
		notifier.info(vim.inspect(Styles))
	else
		notifier.info(vim.inspect({
			ColorRgb24Bit = ColorRgb24Bit,
			Styles = Styles,
		}))
	end
end

--- Highlight all styles in the Styles table.
local function restore_highlight_styles()
	for hl_name, style in pairs(Styles) do
		M.highlight(hl_name, style)
	end
end

api.nvim_create_autocmd("Colorscheme", {
	callback = restore_highlight_styles,
})


--- The function to be called before Vim exits to save the highlight cache.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the highlight cache.
M.on_vim_leave_pre = function(CacheDataAccessor)
	CacheDataAccessor.set("ColorRgb24Bit", ColorRgb24Bit)
	CacheDataAccessor.set("HighlightStyles", Styles)
end


--- Loads the data from cache  from the persistent storage.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the highlight cache.
--- @return function undo function to restore the previous state
M.load_cache = function(CacheDataAccessor)
	local color_rgb_24bit_before = ColorRgb24Bit
	local styles_before = Styles

	ColorRgb24Bit = CacheDataAccessor.get("ColorRgb24Bit") or {}
	Styles = CacheDataAccessor.get("HighlightStyles")

	restore_highlight_styles()

	return function()
		ColorRgb24Bit = color_rgb_24bit_before
		Styles = styles_before
	end
end


--- Generates a valid highlight group name from an ID.
--- @param id CompId The ID to generate the highlight name for.
--- @return string hl_name The generated highlight name.
M.make_hl_name_from_id = function(id)
	return "WL" .. string.gsub(tostring(id), "[^%w_]", "")
end

-- Convert color names to 24-bit RGB numbers
--- @param color string The color name to convert.
local function color_to_24bit(color)
	local c = ColorRgb24Bit[color]
	if c then
		return c
	end
	local num = nvim_get_color_by_name(color)

	if num ~= -1 then
		ColorRgb24Bit[color] = num
	end
	return num
end

--- Adds a highlight name to a string.
--- @param str string The string to which the highlight name will be added.
--- @param hl_name string The highlight name to add.
M.assign_highlight_name = function(str, hl_name)
	return hl_name and str ~= "" and "%#" .. hl_name .. "#" .. str .. "%*" or str
end


--- Retrieves the highlight information for a given highlight group name.
--- @param hl_name string The highlight group name.
--- @return vim.api.keyset.get_hl_info|nil props The highlight properties or nil if not found.
local get_hlprop = function(hl_name)
	if hl_name == "" then
		return nil
	end

	local ok, style = pcall(nvim_get_hl, 0, {
		name = hl_name,
	})

	return ok and style or nil
end

M.get_hlprop = get_hlprop

--- Defines or updates a highlight group with the specified styles.
---@param group_name string The highlight group name.
---@param hl_style string|vim.api.keyset.highlight The highlight styles to apply.
M.highlight = function(group_name, hl_style)
	if group_name == "" then
		return
	end

  local hl_style_type = type(hl_style)
  if hl_style_type == "string" and hl_style ~="" then
    nvim_set_hl(0, group_name, { link = hl_style, default = true} )
    return
  elseif hl_style_type ~="table" or not next(hl_style) then
    return
  end

	Styles[group_name] = hl_style

	local style = shallow_copy(hl_style)
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
	nvim_set_hl(0, group_name, style)
end

return M
