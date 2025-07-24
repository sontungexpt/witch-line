local type, str_rep, rawset = type, string.rep, rawset
local CompManager = require("witch-line.core.CompManager")
local highlight = require("witch-line.utils.highlight")

local M = {}

--- @enum SepStyle
local SepStyle = {
	Full = 0, -- use the style of the component
	SepFg = 1,
	SepBg = 2,
	Reverse = 3, -- use the reverse style of the component
}

local LEFT_SUFFIX = "L"
local RIGHT_SUFFIX = "R"
---
---@alias Id string|number|function

---@class Component
---@field id Id|nil the unique identifier of the component, can be a string or an integer
---@field inherit Id|nil the id of the component that this component inherits from, can be used to extend the functionality of another component
---@field timing boolean|integer|nil|Id|Id[] if true, the component will be updated every time interval
---@field lazy boolean|nil if true, the component will be initialized lazily
---@field events string[]|Id[]|nil a table of events that the component will listen to
---@field user_events string[]|Id[]|nil a table of user defined events that the component will listen to
---
---@field left_style table |nil a table of styles that will be applied to the left part of the component
---@field left string|nil the left part of the component, can be a string or another component
---@field right_style table |nil a table of styles that will be applied to the right part of the component
---@field right string|nil the right part of the component, can be a string or another component
---@field padding integer|nil|{left: integer, right:integer} the padding of the component, can be used to add space around the component
---
---@field style Id|vim.api.keyset.highlight|nil|fun(self: Component, ctx: NotString, static: NotString): vim.api.keyset.highlight a table of styles that will be applied to the component
---@field static Id|table|nil a table of static values that will be used in the component
---@field context Id|nil|fun(self:Component, static:any): NotString a table that will be passed to the component's update function
---
---@field init nil|fun(self: Component) called when the component is initialized, can be used to set up the context
---@field pre_update nil|fun(self: Component, ctx: NotString, static: NotString) called before the component is updated, can be used to set up the context
---@field update string|fun(self:Component, ctx: NotString, static: NotString): string called to update the component, should return a string that will be displayed
---@field post_update nil|fun(self: Component,ctx: NotString, static: NotString) called after the component is updated, can be used to clean up the context
---@field should_display Id|nil|fun(self: Component, ctx:NotString, static: NotString): boolean called to check if the component should be displayed, should return true or false
---@field min_screen_width integer|nil the minimum screen width required to display the component, used for lazy loading components
---
---@field _indices integer[]|nil A list of indices of the component in the Values table, used for rendering the component (only the root component had)
---@field _hl_name string|nil the highlight group name for the component
---@field _left_hl_name string|nil the highlight group name for the component
---@field _right_hl_name string|nil the highlight group name for the component
---@field _hidden boolean|nil if true, the component is hidden and should not be displayed, used for lazy loading components
---

--- @param comp Component the component to update
--- @param ctx any the context to pass to the component's update function
--- @param static any the static values to pass to the component's update function
--- @param session_id SessionId the session id to use for the component, used for lazy loading components
M.update_style = function(comp, ctx, static, session_id)
	local style, ref_comp = CompManager.get_style(comp, session_id, ctx, static)
	local left_type, right_type = type(comp.left), type(comp.right)

	if type(style) == "table" then
		local force = false
		if ref_comp and comp ~= ref_comp then
			if not comp._hl_name then
				rawset(ref_comp, "_hl_name", ref_comp._hl_name or highlight.gen_hl_name_by_id(ref_comp.id))
				rawset(comp, "_hl_name", ref_comp._hl_name)
				force = true
			elseif type(ref_comp.style) == "function" then
				force = true
			end
		elseif not comp._hl_name then
			rawset(comp, "_hl_name", highlight.gen_hl_name_by_id(comp.id))
			force = true
		end

		if force or type(comp.style) == "function" then
			highlight.hl(comp._hl_name, style)
		end

		if left_type == "string" then
			local left_style = comp.left_style or SepStyle.SepBg
			local hl_name = comp._hl_name or highlight.gen_hl_name_by_id(comp.id)
			local left_hl_name = hl_name .. LEFT_SUFFIX
			if left_style == SepStyle.SepFg then
				if force or not comp._left_hl_name then
					highlight.hl(left_hl_name, {
						fg = style.fg,
						bg = "NONE",
					})
				end
				rawset(comp, "_left_hl_name", left_hl_name)
			elseif left_style == SepStyle.SepBg then
				if force or not comp._left_hl_name then
					highlight.hl(left_hl_name, {
						fg = style.bg,
						bg = "NONE",
					})
				end
				rawset(comp, "_left_hl_name", left_hl_name)
			elseif left_style == SepStyle.Reverse then
				if force or not comp._left_hl_name then
					local s = highlight.get_hlprop(hl_name)
					if s then
						highlight.hl(left_hl_name, {
							fg = s.bg,
							bg = s.fg,
						})
					end
				end
				rawset(comp, "_left_hl_name", left_hl_name)
			else
				rawset(comp, "_left_hl_name", comp._hl_name)
			end
		end
		if right_type == "string" then
			local right_style = comp.right_style or SepStyle.SepBg
			local hl_name = comp._hl_name or highlight.gen_hl_name_by_id(comp.id)
			local right_hl_name = hl_name .. RIGHT_SUFFIX
			if right_style == SepStyle.SepFg then
				if force or not comp._right_hl_name then
					highlight.hl(right_hl_name, {
						fg = style.fg,
						bg = "NONE",
					})
				end
				rawset(comp, "_right_hl_name", right_hl_name)
			elseif right_style == SepStyle.SepBg then
				if force or not comp._right_hl_name then
					highlight.hl(right_hl_name, {
						fg = style.bg,
						bg = "NONE",
					})
				end
				rawset(comp, "_right_hl_name", right_hl_name)
			elseif right_style == SepStyle.Reverse then
				if force or not comp._right_hl_name then
					local s = highlight.get_hlprop(hl_name)
					if s then
						highlight.hl(right_hl_name, {
							fg = s.bg,
							bg = s.fg,
						})
					end
				end
				rawset(comp, "_right_hl_name", right_hl_name)
			else
				rawset(comp, "_right_hl_name", comp._hl_name)
			end
		end
	end

	if left_type == "string" and comp.left ~= "" then
		local left_style = comp.left_style
		if comp._left_hl_name then
			if type(left_style) == "function" then
				left_style = left_style(comp, ctx, static)
				if type(left_style) == "table" then
					highlight.hl(comp._left_hl_name, left_style)
				end
			end
		else
			local hl_name = comp._hl_name or highlight.gen_hl_name_by_id(comp.id)
			local left_hl_name = hl_name .. LEFT_SUFFIX
			if type(left_style) == "function" then
				left_style = left_style(comp, ctx, static)
			end
			if type(left_style) == "table" then
				highlight.hl(left_hl_name, left_style)
				rawset(comp, "_left_hl_name", left_hl_name)
			end
		end
	end
	if right_type == "string" and comp.right ~= "" then
		local right_style = comp.right_style
		if comp._right_hl_name then
			if type(right_style) == "function" then
				right_style = right_style(comp, ctx, static)
				if type(right_style) == "table" then
					highlight.hl(comp._right_hl_name, right_style)
				end
			end
		else
			local hl_name = comp._hl_name or highlight.gen_hl_name_by_id(comp.id)
			local right_hl_name = hl_name .. RIGHT_SUFFIX
			if type(right_style) == "function" then
				right_style = right_style(comp, ctx, static)
			end
			if type(right_style) == "table" then
				highlight.hl(right_hl_name, right_style)
				rawset(comp, "_right_hl_name", right_hl_name)
			end
		end
	end
end

--- @param comp Component the component to evaluate
--- @return string value the new value of the component
M.evaluate = function(comp, ctx, static)
	if type(comp.pre_update) == "function" then
		comp.pre_update(comp, ctx, static)
	end

	local value = comp.update
	if type(value) == "function" then
		value = value(comp, ctx, static)
	end

	if type(value) ~= "string" then
		value = ""
	elseif value ~= "" then
		local padding = comp.padding or 1
		if type(padding) == "number" then
			value = str_rep(" ", padding) .. value .. str_rep(" ", padding)
		elseif type(padding) == "table" then
			local left, right = padding.left, padding.right
			if type(left) == "number" and left > 0 then
				value = str_rep(" ", left) .. value
			end

			if type(right) == "number" and right > 0 then
				value = value .. str_rep(" ", right)
			end
		end
	end

	if type(comp.post_update) == "function" then
		comp.post_update(comp, ctx, static)
	end

	return value
end

return M
