local bit = require("bit")
local band, rshift, lshift, bor = bit.band, bit.rshift, bit.lshift, bit.bor

local api = vim.api
local hlID, nvim_set_hl, nvim_get_hl, nvim_get_color_by_name =
	vim.fn.hlID, api.nvim_set_hl, api.nvim_get_hl, api.nvim_get_color_by_name
local type, next, pcall, pairs = type, next, pcall, pairs
local string_gsub = string.gsub

local M = {}

local auto_theme_enabled = true

--- Because this is builtin so we can pre compute the id of StatusLine hl group
local STATUSLINE_HL = {
	id = api.nvim_get_hl_id_by_name("StatusLine"),
}

---@type table<string, integer>
local ColorRgb24Bit = {}

---@type table<string, CompStyle>
local Styles = {}

--- Retrieves the style for a given component.
--- @param comp ManagedComponent The component to retrieve the style for.
--- @return CompStyle|nil style The style of the component or nil if not found.
M.get_style = function(comp)
	if comp._hl_name then
		return Styles[comp._hl_name]
	end
	return nil
end

--- Sets the auto theme value.
M.set_auto_theme = function(value)
	auto_theme_enabled = value
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
		notifier.info(vim.inspect {
			ColorRgb24Bit = ColorRgb24Bit,
			Styles = Styles,
		})
	end
end

--- Highlight all styles in the Styles table.
local function restore_highlight_styles()
	for hl_name, style in pairs(Styles) do
		M.highlight(hl_name, style)
	end
end

--- Toggles the auto-theme feature.
M.toggle_auto_theme = function()
	auto_theme_enabled = not auto_theme_enabled
	restore_highlight_styles()
	require("witch-line.utils.notifier").info(
		"Auto theme is " .. (auto_theme_enabled and "enabled" or "disabled")
	)
end

api.nvim_create_autocmd("Colorscheme", {
	callback = restore_highlight_styles,
})

--- The function to be called before Vim exits to save the highlight cache.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the highlight cache.
M.on_vim_leave_pre = function(CacheDataAccessor)
	CacheDataAccessor["ColorRgb24Bit"] = ColorRgb24Bit
	CacheDataAccessor["HighlightStyles"] = Styles
end

--- Loads the data from cache  from the persistent storage.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the highlight cache.
M.load_cache = function(CacheDataAccessor)
	ColorRgb24Bit = CacheDataAccessor["ColorRgb24Bit"] or ColorRgb24Bit
	Styles = CacheDataAccessor["HighlightStyles"] or Styles
	restore_highlight_styles()
end

--- Generates a valid highlight group name from an ID.
--- @param id CompId The ID to generate the highlight name for.
--- @return string hl_name The generated highlight name.
M.make_hl_name_from_id = function(id)
	return "WL" .. string_gsub(id, "[^%w_]", "")
end

--- Adds a highlight name to a string.hi
--- @param str string The string to which the highlight name will be added.
--- @param hl_name string|nil The highlight name to add.
M.assign_highlight_name = function(str, hl_name)
	return hl_name and str ~= "" and "%#" .. hl_name .. "#" .. str .. "%*" or str
end

--- Replace a string contains highlight segment with new highlight name.
--- @param str string The string that may contains highlight segment.
--- @param new_hl_name string|nil The new string with the new replaced highlight name.
--- @param n? integer Whether to replace the first occurrence only.
M.replace_highlight_name = function(str, new_hl_name, n)
	return string_gsub(str, "%%#.-#", "%#" .. new_hl_name .. "#", n)
end

--- Retrieve highlight properties for a given highlight group.
---
--- This function safely queries Neovim's highlight table to obtain
--- the resolved highlight style for a given group name. It uses `pcall`
--- to avoid throwing errors if the highlight group does not exist.
---
--- Example:
--- ```lua
--- local fg_color = M.safe_nvim_get_hl({ name = "Comment" })
--- if fg_color then
---   print(fg_color.fg) -- e.g. 0xa9b1d6
--- end
--- ```
---
--- @param opts table      Options passed to `nvim_get_hl`, typically including `{ name = hl_name }`.
--- @return vim.api.keyset.get_hl_info|nil props  A table containing highlight properties (e.g., `fg`, `bg`, `bold`, `italic`), or `nil` if not found.
M.safe_nvim_get_hl = function(opts)
	-- Not cache here because c can be changed by user
	local ok, style = pcall(nvim_get_hl, 0, opts)
	return ok and style or nil
end

--- Merge a child highlight definition with a parent highlight or highlight group.
---
--- This function combines two highlight sources into one, giving priority to the
--- child’s properties. The parent can be either:
---   - A **table** containing highlight fields (e.g. `{ fg = "#ffffff", bold = true }`), or
---   - A **string** name of an existing highlight group (e.g. `"Comment"`).
---
--- Behavior:
--- 1. If `parent` is a table and has no `link` field, it merges directly with `child`.
--- 2. If `parent` is a table containing a `link`, it uses that linked group name instead.
--- 3. If `parent` is a string, it attempts to retrieve the highlight properties of that group
---    using `nvim_get_hl`, then merges them with the `child` table.
--- 4. Merge strategy uses `"keep"` mode — child properties take precedence over parent values.
---
--- Example:
--- ```lua
--- local child = { fg = "#ffffff" }
--- local merged = M.merge_hl(child, "Comment")
--- -- Result: child color kept, inherits missing fields from Comment group
--- ```
---
--- @param child CompStyle|nil The child highlight definition (fields take precedence).
--- @param parent CompStyle|nil The parent highlight definition or group name.
--- @param n integer The total number of parents in the inheritance chain
--- @return CompStyle merged The merged highlight table (or the child table if no merge occurred).
M.merge_hl = function(child, parent, n)
	if type(child) == "string" then
		local hlid = hlID(child)
		---@diagnostic disable-next-line: cast-local-type
		child = hlid ~= 0 and nvim_get_hl(0, {
			id = hlid,
			create = false,
		}) or nil
	end
	local pt = type(parent)
	if pt == "table" then
		if not parent.link then
			---@diagnostic disable-next-line: param-type-mismatch, return-type-mismatch
			return vim.tbl_deep_extend("keep", child or {}, parent)
		end
		---@diagnostic disable-next-line: cast-local-type
		parent = parent.link
		pt = "string"
	end

	if pt == "string" then
		local hlid = hlID(parent)
		local pstyle = hlid ~= 0 and nvim_get_hl(0, {
			id = hlid,
			create = false,
		}) or nil
		---@diagnostic disable-next-line: param-type-mismatch, return-type-mismatch
		return pstyle and vim.tbl_deep_extend("keep", child or {}, pstyle) or child
	end
	---@cast child CompStyle
	return child
end

--- Adjust a 24-bit RGB color for better contrast against a background.
--- Steps:
--- 1) Lighten or darken the color depending on background luminance.
--- 2) Apply soft desaturation to avoid harsh colors.
--- 3) Push color components away from background values if too similar.
--- 4) Restore some saturation while preserving hue.
--- The goal is to improve visibility without blowing the color to white.
local adjust = function(c, bg)
	-- Unpack background RGB
	local bg_r = rshift(bg, 16)
	local bg_g = band(rshift(bg, 8), 0xFF)
	local bg_b = band(bg, 0xFF)

	-- Unpack color RGB
	local r = rshift(c, 16)
	local g = band(rshift(c, 8), 0xFF)
	local b = band(c, 0xFF)

	-- Background luminance ×1000 to avoid floats
	local Lbg = bg_r * 299 + bg_g * 587 + bg_b * 114
	local is_dark = Lbg < 140000

	-- Balanced lighten/darken (safer on bright backgrounds)
	local gain = is_dark and 1080 or 860
	r = rshift(r * gain, 10)
	g = rshift(g * gain, 10)
	b = rshift(b * gain, 10)

	-- Soft desaturation (push toward a soft gray)
	local gray = rshift(r + g + b, 2)
	-- Light background → reduce saturation stronger to reduce glare
	local desat = is_dark and 0.75 or 0.5
	r = gray + (r - gray) * desat
	g = gray + (g - gray) * desat
	b = gray + (b - gray) * desat

	-- Push components away if too close to background
	local threshold = is_dark and 58 or 68
	local base_push = is_dark and 26 or 34

	-- Weighted push: channels with higher difference get stronger push
	local d = r - bg_r
	if d < threshold and d > -threshold then
		r = d > 0 and r + base_push or r - base_push
	end

	local d2 = g - bg_g
	if d2 < threshold and d2 > -threshold then
		g = d2 > 0 and g + base_push or g - base_push
	end

	local d3 = b - bg_b
	if d3 < threshold and d3 > -threshold then
		b = d3 > 0 and b + base_push or b - base_push
	end

	-- Adaptive saturation: depends on color-background brightness contrast
	local gray2 = (r + g + b) * 0.333
	local sat2 = is_dark and 1.15 or 1.30
	r = gray2 + (r - gray2) * sat2
	g = gray2 + (g - gray2) * sat2
	b = gray2 + (b - gray2) * sat2

	-- Clamp to valid range
	r = r < 0 and 0 or r > 255 and 255 or r
	g = g < 0 and 0 or g > 255 and 255 or g
	b = b < 0 and 0 or b > 255 and 255 or b

	-- Pack RGB back into 24-bit
	return bor(lshift(r, 16), lshift(g, 8), b)
end

--- Resolve a color into a 24-bit RGB value, a highlight group property, or "NONE".
---
--- Supports:
--- 1. Numeric RGB (e.g., 0xFFAA00) → returned directly (optionally adjusted).
--- 2. Named colors (e.g., "red") → resolved via Neovim API and cached.
--- 3. Highlight groups (e.g., "Normal") → fetch `fg` or `bg` field.
--- 4. "NONE" → returned as-is.
---
--- @param c string|integer|nil  Color name, RGB value, or highlight group.
--- @param field "fg"|"bg"   Field to fetch from highlight group.
--- @param auto_adjust? boolean  Adjust color based on statusline background if true.
--- @return integer|string|nil  Resolved 24-bit RGB, "NONE", or nil if not found.
local function resolve_color(c, field, auto_adjust)
	local t = type(c)
	local num = c
	if t == "string" then
		if c == "NONE" then
			return "NONE"
		elseif c == "" then
			return nil
		end
		-- Read cache
		num = ColorRgb24Bit[c]
		if not num then
			num = nvim_get_color_by_name(c)
			if num ~= -1 then
				-- cache color
				ColorRgb24Bit[c] = num
			else
				local hlid = hlID(c)
				if hlid == 0 then
					return nil
				end
				-- Not cache here because c can be changed by user
				num = nvim_get_hl(0, { id = hlid, create = false })[field]
			end
		end
	elseif t ~= "number" then
		return nil
	end

	--- num is number here
	if auto_theme_enabled and auto_adjust then
		local stbg = nvim_get_hl(0, STATUSLINE_HL).bg
		return stbg and adjust(num, stbg) or num
	end
	return num
end

--- Defines or updates a Neovim highlight group with the given style.
---
--- This function normalizes and resolves highlight properties (e.g. `fg`, `bg`, `foreground`, `background`)
--- before calling `nvim_set_hl()`. It also caches the style in `Styles` for persistence and automatic
--- restoration on colorscheme reload.
---
--- Behavior:
--- - If `hl_style` is a string, it creates a linked highlight group.
--- - If `hl_style` is a table, it resolves color names and sets the group directly.
--- - If empty or invalid, the function does nothing and returns false.
---
--- @param group_name string The name of the highlight group to define or update.
--- @param hl_style CompStyle The style definition — either a link target or a style table.
--- @return boolean success True if the highlight was applied successfully, false otherwise.
M.highlight = function(group_name, hl_style)
	if group_name == "" then
		return false
	end
	local hl_style_type = type(hl_style)
	if hl_style_type == "string" and hl_style ~= "" then
		nvim_set_hl(0, group_name, { link = hl_style, default = true })
		return true
	elseif hl_style_type ~= "table" or not next(hl_style) then
		return false
	end

	Styles[group_name] = hl_style

	local style = {} --- Shallow copy
	for k, v in pairs(hl_style) do
		style[k] = v
	end

	local auto_theme = style.auto_theme

	style.fg = resolve_color(style.fg or style.foreground, "fg", auto_theme)
	style.bg = resolve_color(style.bg or style.background, "bg", auto_theme) or "NONE"

	--- Removed this before highlight because this is the custom value and not valid in nvim_set_hl
	style.auto_theme = nil

	nvim_set_hl(0, group_name, style)
	return true
end

return M
