local api, type, next, pcall, pairs = vim.api, type, next, pcall, pairs
local nvim_set_hl, nvim_get_hl, nvim_get_color_by_name = api.nvim_set_hl, api.nvim_get_hl, api.nvim_get_color_by_name

local shallow_copy = require("witch-line.utils.tbl").shallow_copy

local M = {}

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
	local color_rgb_24bit_before, styles_before = ColorRgb24Bit, Styles

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

--- Adds a highlight name to a string.hi
--- @param str string The string to which the highlight name will be added.
--- @param hl_name string|nil The highlight name to add.
M.assign_highlight_name = function(str, hl_name)
	return hl_name and str ~= "" and "%#" .. hl_name .. "#" .. str .. "%*" or str
end

--- Replace a string contains highlight segment with new highlight name.
--- @param str string The string that may contains highlight segment.
--- @param new_hl_name string|nil The new string with the new replaced highlight name.
M.replace_highlight_name = function(str, new_hl_name, first)
	return string.gsub(str, "%%#.-#", "%#" .. new_hl_name .. "#", first and 1)
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
--- @return vim.api.keyset.get_hl_info|nil props  A table containing highlight properties
---                                               (e.g., `fg`, `bg`, `bold`, `italic`), or `nil` if not found.
M.safe_nvim_get_hl = function(opts)
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
		local ok, s = pcall(nvim_get_hl, 0, {
			name = child,
			create = false,
		})
		---@diagnostic disable-next-line: cast-local-type
		child = ok and s or nil
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
		local ok, pstyle = pcall(nvim_get_hl, 0, {
			name = parent,
			create = false,
		})
		---@diagnostic disable-next-line: param-type-mismatch, return-type-mismatch
		return ok and vim.tbl_deep_extend("keep", child or {}, pstyle) or child
	end
	---@cast child CompStyle
	return child
end

--- Resolve a color definition into a concrete 24-bit RGB value or an inherited highlight property.
---
--- This function converts a given color specification into an actual numeric RGB value.
--- The input may be:
--- - A numeric RGB value (e.g. `0xFFAA00`)
--- - A named color string (e.g. `"red"`, `"LightGrey"`)
--- - A highlight group name (e.g. `"Normal"`, `"StatusLine"`)
--- - The literal string `"NONE"`
---
--- ### Lookup Order
--- 1. **Numeric check:** If `c` is already a number, return it directly.
--- 2. **Cached lookup:** Try to resolve from the cached table `ColorRgb24Bit`.
--- 3. **Neovim API:** Use `nvim_get_color_by_name(c)` to resolve standard color names or hex strings.
--- 4. **Highlight group:** If still unresolved, call `get_hlprop(c)` to fetch another group's color field (`"fg"` or `"bg"`).
---
--- ### Notes
--- - `"NONE"` is returned unchanged to indicate transparent/no color.
--- - Successfully resolved colors are cached in `ColorRgb24Bit` for reuse.
--- - Returns `nil` if the color cannot be resolved.
---
--- @param c string|integer  Color name, numeric RGB value, or highlight group name.
--- @param field "fg"|"bg"   The field to extract when resolving from another highlight group.
--- @return integer|string|nil color  The resolved 24-bit RGB color, `"NONE"`, or `nil` if not found.
local function resolve_color(c, field)
	local t = type(c)
	if t == "number" then
		return c
	elseif t ~= "string" or c == "" then
		return nil
	elseif c == "NONE" then
		return "NONE"
	end
	local num = ColorRgb24Bit[c]
	if num then
		return num
	end
	num = nvim_get_color_by_name(c)
	if num ~= -1 then
		ColorRgb24Bit[c] = num
		return num
	end
	local ok, style = pcall(nvim_get_hl, 0, {
		name = c,
		create = false,
	})
	return ok and style[field] or nil
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
--- @param hl_style string|table The style definition — either a link target or a style table.
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

	local style = shallow_copy(hl_style)
	style.foreground = resolve_color(style.foreground or style.fg, "fg")
	style.background = resolve_color(style.background or style.bg, "bg") or "NONE"
	style.fg, style.bg = nil, nil
	nvim_set_hl(0, group_name, style)
	return true
end

return M
