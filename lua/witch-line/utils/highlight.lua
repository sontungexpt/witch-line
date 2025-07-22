local vim = vim
local api = vim.api
local nvim_set_hl, nvim_get_hl = api.nvim_set_hl, api.nvim_get_hl
local is_color = api.nvim_get_color_by_name

local type = type

local M = {}

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

M.add_hl_name = function(str, hl_name)
	return str ~= "" and "%#" .. hl_name .. "#" .. str .. "%*" or str
end

M.is_hl_name = function(hl_name)
	return type(hl_name) == "string" and hl_name ~= ""
end

M.is_hl_styles = function(hl_styles)
	return type(hl_styles) == "table" and next(hl_styles)
end

M.get_hl = function(hl_name)
	return api.nvim_get_hl(0, {
		name = hl_name,
	})
end

---@param group_name string
---@param hl_styles vim.api.keyset.highlight
M.hl = function(group_name, hl_styles, force)
	local styles = vim.deepcopy(hl_styles)

	styles.foreground = styles.fg
	styles.background = styles.bg
	styles.fg = nil
	styles.bg = nil

	if
		type(styles.foreground) == "string"
		and styles.foreground ~= "NONE"
		---@diagnostic disable-next-line: param-type-mismatch
		and api.nvim_get_color_by_name(styles.foreground) == -1
	then
		styles.foreground = M.get_hl(styles.foreground).fg
	end

	if
		type(styles.background) == "string"
		and styles.background ~= "NONE"
		---@diagnostic disable-next-line: param-type-mismatch
		and api.nvim_get_color_by_name(styles.background) == -1
	then
		styles.background = M.get_hl(hl_styles.bg).bg
	end

	if styles.background == nil then
		styles.background = M.get_hl("StatusLine").bg
	end

	pcall(nvim_set_hl, 0, group_name, styles)
end

return M
