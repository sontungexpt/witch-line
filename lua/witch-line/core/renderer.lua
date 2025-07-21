local vim = vim
local api, opt, uv = vim.api, vim.opt, vim.uv or vim.loop
local schedule = vim.schedule
local autocmd, augroup = api.nvim_create_autocmd, api.nvim_create_augroup
local type, ipairs, concat = type, ipairs, table.concat

local Component = require("witch-line.core.Comp")
local highlight = require("witch-line.utils.highlight")

-- local cache_module = require("witch-line.cache")
-- local PLUG_NAME = "witch-line"
-- local COMP_DIR = "witch-line.components."

local components = {}

local M = {}

--- @type string[] The list of render value of component .
local Values = {}

function M.render()
	local str = concat(Values)
	opt.statusline = str ~= "" and str or " "
end

local highlight_comp = function(comp)
	highlight.hl(comp._hl_name, comp.styles)
end

--- Update the component value and highlight if necessary.
--- @param comp Component
local function update_comp(comp)
	local dispersed = comp.dispersed
	local left = comp.left
	if dispersed and left then
		---@diagnostic disable-next-line: param-type-mismatch
		update_comp(left)
	end

	local indices = comp._indices
	if indices then
		local v, s = Component.evaluate(comp)
		for _, idx in ipairs(indices) do
			Values[idx] = highlight.add_hl_name(v, comp._hl_name)
		end
		if s then
			highlight_comp(comp)
		end
	end

	local right = comp.right
	if dispersed and right then
		---@diagnostic disable-next-line: param-type-mismatch
		update_comp(right)
	end
end
M.update_comp = update_comp

local function registry(c)
	local comp = Component:new(c)
	if comp.lazy then
		for node in Component.inorder_iter(comp) do
			Values[#Values + 1] = ""
		end
		return
	end

	for _, v in ipairs(comp._flat) do
		local next_pos = #Values + 1

		if type(v.update) == "string" then
			Values[next_pos] = highlight.add_hl_name(v.update, v._hl_name)
		else
			Values[next_pos] = ""

			-- updatable component
			local _indices = comp._indices or {}
			_indices[#_indices + 1] = next_pos
			comp._indices = _indices
		end
		if highlight.is_hl_styles(comp.style) then
			highlight_comp(comp)
		end
	end
end

function M.setup(configs)
	for _, comp in ipairs(configs.components) do
		registry(comp)
	end
	-- update_comp = configs.update_comp or update_comp
end

return M
