local type, str_rep, rawset = type, string.rep, rawset
local CompManager = require("witch-line.core.CompManager")
local highlight = require("witch-line.utils.highlight")
local call_or_get = require("witch-line.utils").call_or_get

local COMP_MODULE_PATH = "witch-line.components."

local M = {}

--- @enum SepStyle
local SepStyle = {
	Full = 0, -- use the style of the component
	SepFg = 1,
	SepBg = 2,
	Reverse = 3, -- use the reverse style of the component }
}

local LEFT_SUFFIX = "L"
local RIGHT_SUFFIX = "R"

---@alias Id string|number

--- @class Ref
--- @field events Id[]|nil a table of events that the component will listen to
--- @field user_events Id[]|nil a table of user defined events that the component will listen to
--- @field timing Id[]|nil if true, the component will be updated every time interval
--- @field style Id|nil a table of styles that will be applied to the component
--- @field static Id|nil a table of static values that will be used in the component
--- @field context Id|nil a table that will be passed to the component's update function
--- @field hide Id[]|nil if true, the component is hidden and should not be displayed, used for lazy loading components

local InheritField = {
	timing = true,
	lazy = true,
	events = true,
	user_events = true,
	ref = true,
	style = true,
	static = true,
	context = true,
	min_screen_width = true,
}

---@alias RefFieldType Id|nil
---@alias RefFieldTypes Id[]|nil
---

---@class Component
---@field [integer] string|Component a table of childs, can be used to create a list of components
---@field id Id the unique identifier of the component, can be a string or an integer
---@field inherit Id|nil the id of the component that this component inherits from, can be used to extend the functionality of another component
---@field timing boolean|integer|nil if true, the component will be updated every time interval
---@field lazy boolean|nil if true, the component will be initialized lazily
---@field events string[]|nil a table of events that the component will listen to
---@field user_events string[]|nil a table of user defined events that the component will listen to
---@field ref Ref|nil a table of references to other components, used for lazy loading components
---
---@field left_style table |nil a table of styles that will be applied to the left part of the component
---@field left string|nil|fun(self: Component, ctx: any, static: any) the left part of the component, can be a string or another component
---@field right_style table |nil a table of styles that will be applied to the right part of the component
---@field right string|nil|fun(self: Component, ctx: any, static: any) the right part of the component, can be a string or another component
---@field padding integer|nil|{left: integer|nil, right:integer|nil}|fun(self: Component, ctx: any, static: any): number|{left: integer|nil, right:integer|nil} the padding of the component, can be used to add space around the component
---
---@field style vim.api.keyset.highlight|nil|fun(self: Component, ctx: any, static: any): vim.api.keyset.highlight a table of styles that will be applied to the component
---@field static any a table of static values that will be used in the component
---@field context nil|fun(self: Component, static:any): any a table that will be passed to the component's update function
---
---@field init nil|fun(raw_self: Component) called when the component is initialized, can be used to set up the context
---@field pre_update nil|fun(self: Component, ctx: any, static: any) called before the component is updated, can be used to set up the context
---@field update nil|string|fun(self:Component, ctx: any, static: any): string|nil called to update the component, should return a string that will be displayed
---@field post_update nil|fun(self: Component,ctx: any, static: any) called after the component is updated, can be used to clean up the context
---@field hide nil|fun(self: Component, ctx:any, static: any): boolean|nil called to check if the component should be displayed, should return true or false
---@field min_screen_width integer|nil the minimum screen width required to display the component, used for lazy loading components
---
---@private
---@field _indices integer[]|nil A list of indices of the component in the Values table, used for rendering the component (only the root component had)
---@field _hl_name string|nil the highlight group name for the component
---@field _left_hl_name string|nil the highlight group name for the component
---@field _right_hl_name string|nil the highlight group name for the component
---@field _parent boolean|nil if true, the component is loaded and should be displayed, used for lazy loading components
---@field _hidden boolean|nil if true, the component is hidden and should not be displayed, used for lazy loading components
---@field _loaded boolean|nil if true, the component is loaded and should be displayed, used for lazy loading components
---@field _abstract boolean|nil if true, the component is an abstract component and should not be displayed, used for lazy loading components
---

---@class DefaultComponent : Component
---@field _plug_provided true If true, the component is provided by plugin

--- Gets the id of the component, if the id is a number, it will be converted to a string.
--- @param comp Component|DefaultComponent the component to get the id from
--- @param alt_id Id|nil an alternative id to use if the component does not have an id
--- @return Id id the id of the component
M.valid_id = function(comp, alt_id)
	local Id = require("witch-line.constant.id")
	local id = comp.id or alt_id
	if not comp._plug_provided then
		id = Id.id(id)
	end
	if id == nil then
		require("witch-line.utils.notifier").error("Component id is nil" .. vim.inspect(comp))
	end
	rawset(comp, "id", id) -- Ensure the component has an ID field

	---@diagnostic disable-next-line: return-type-mismatch
	return id
end

--- Inherits the parent component's fields and methods, allowing for component extension.
--- @param comp Component the component to inherit from
--- @param parent Component the parent component to inherit from
M.inherit_parent = function(comp, parent)
	setmetatable(comp, {
		---@diagnostic disable-next-line: unused-local
		__index = function(t, key)
			if not InheritField[key] then
				return nil
			end
			return parent[key]
		end,
	})
end

--- Checks if the component has a parent, which is used for lazy loading components.
--- @param comp Component the component to check
--- @return boolean has_parent true if the component has a parent, false otherwise
M.has_parent = function(comp)
	return comp._parent == true
end

---Checks if the component is hidden, which is used for lazy loading components.
---@param comp Component the component to check
---@param style_field "left_style"|"right_style" the field name of the side style, used for left or right styles
---@param hl_name_field "_left_hl_name"|"_right_hl_name" the field name of the side highlight group, used for left or right styles
---@param suffix string the suffix to append to the main highlight group name, used for left or right styles
---@param ctx any the context to pass to the component's update function
---@param static any the static values to pass to the component's update function
---@param ... any additional arguments to pass to the component's update function
local function update_side_style(comp, style_field, hl_name_field, main_style, suffix, ctx, static, ...)
	local side_hl_name = comp[hl_name_field] or comp._hl_name
	local style = comp[style_field]

	if not side_hl_name then
		side_hl_name = highlight.gen_hl_name_by_id(comp.id) .. suffix
		rawset(comp, hl_name_field, side_hl_name)

		-- initial time
		if type(style) == "table" then
			highlight.hl(side_hl_name, style)
			return
		end
	end

	if type(style) == "function" then
		style = style(comp, ctx, static, ...)
		--- Always update the highlight if a function
		if type(style) == "table" then
			highlight.hl(side_hl_name, style)
		end
	elseif main_style then
		if style == SepStyle.SepFg then
			style = {
				fg = main_style.fg,
				bg = "NONE",
			}
		elseif style == SepStyle.SepBg then
			style = {
				fg = main_style.bg,
				bg = "NONE",
			}
		elseif style == SepStyle.Reverse then
			style = {
				fg = main_style.bg,
				bg = main_style.fg,
			}
		else
			return
		end

		if type(style) == "table" then
			highlight.hl(side_hl_name, style)
		end
	end

	-- inherited style from the main style
	-- return main_hl_name, nil
end

--- @param comp Component the component to update
--- @param session_id SessionId the session id to use for the component, used for lazy loading components
--- @param ctx any the context to pass to the component's update function
--- @param static any the static values to pass to the component's update function
--- @param ... any additional arguments to pass to the component's update function
M.update_style = function(comp, session_id, ctx, static, ...)
	local style, ref_comp = CompManager.get_style(comp, session_id, ctx, static, ...)
	local force = false

	if type(style) == "table" then
		if not comp._hl_name then
			force = true
			if comp ~= ref_comp then
				rawset(ref_comp, "_hl_name", ref_comp._hl_name or highlight.gen_hl_name_by_id(ref_comp.id))
				rawset(comp, "_hl_name", ref_comp._hl_name)
			else
				rawset(comp, "_hl_name", highlight.gen_hl_name_by_id(comp.id))
			end
			highlight.hl(comp._hl_name, style)
		elseif type(ref_comp.style) == "function" then
			force = true
			highlight.hl(comp._hl_name, style)
		end
	end

	if comp.left then
		update_side_style(comp, "left_style", "_left_hl_name", force and style, LEFT_SUFFIX, ctx, static, ...)
	end
	if comp.right then
		update_side_style(comp, "right_style", "_right_hl_name", force and style, RIGHT_SUFFIX, ctx, static, ...)
	end
end

--- @param comp Component the component to evaluate
--- @param ctx any the context to pass to the component's update function
--- @param static any the static values to pass to the component's update function
--- @param ... any additional arguments to pass to the component's update function
--- @return string value the new value of the component
M.evaluate = function(comp, ctx, static, ...)
	if type(comp.pre_update) == "function" then
		comp.pre_update(comp, ctx, static)
	end

	local result = nil
	if type(comp.update) == "function" then
		result = comp.update(comp, ctx, static)
	end

	if type(result) ~= "string" then
		result = ""
	elseif result ~= "" then
		local padding = call_or_get(comp.padding or 1, comp, ctx, static)
		local p_type = type(padding)
		if p_type == "number" and padding > 0 then
			result = str_rep(" ", padding) .. result .. str_rep(" ", padding)
		elseif p_type == "table" then
			local left, right = padding.left, padding.right
			if type(left) == "number" and left > 0 then
				result = str_rep(" ", left) .. result
			end
			if type(right) == "number" and right > 0 then
				result = result .. str_rep(" ", right)
			end
		end
	end

	if type(comp.post_update) == "function" then
		comp.post_update(comp, ctx, static)
	end

	return result
end

--- Evaluates the left and right parts of the component, returning their values.
--- @param comp Component the component to evaluate
--- @param ctx any the context to pass to the component's update function
--- @param static any the static values to pass to the component's update function
--- @return string|nil left the left part of the component, or an empty string if it is not defined
--- @return string|nil right the right part of the component, or an empty string if it is not defined
M.evaluate_left_right = function(comp, ctx, static)
	local left, right = comp.left, comp.right

	--- All are hided or uninitialized
	--- So need to compare the left and right accurate
	if comp._hidden ~= false then
		if left then
			if type(left) == "function" then
				left = left(comp, ctx, static)
			end
			if type(left) ~= "string" then
				left = ""
			end
		end
		if right then
			if type(right) == "function" then
				right = right(comp, ctx, static)
			end
			if type(right) ~= "string" then
				right = ""
			end
		end
	else
		-- nil means no need to update
		-- Why?
		-- Because in case the left or right is string type
		-- It never update so we don't need to set statusline again
		if type(left) == "function" then
			left = left(comp, ctx, static)
			if type(left) ~= "string" then
				left = nil
			end
		else
			left = nil
		end
		if type(right) == "function" then
			right = right(comp, ctx, static)
			if type(right) ~= "string" then
				right = nil
			end
		else
			right = nil
		end
	end
	return left, right
end

--- Requires a default component by its id.
--- @param id Id the path to the component, e.g. "file.name" or "git.status"
--- @return Component|nil comp the component if it exists, or nil if it does not
M.require_by_id = function(id)
	local Id = require("witch-line.constant.id").Id
	local path = Id[id]
	---@cast path string
	return path and M.require(path)
end

--- @param path string the path to the component, e.g. "file.name" or "git.status"
--- @return Component|nil comp the component if it exists, or nil if it does not
M.require = function(path)
	local paths = vim.split(path, ".", { plain = true })
	local size = #paths
	local module_path = COMP_MODULE_PATH .. paths[1]

	local ok, component = pcall(require, module_path)
	if not ok then
		return nil
	end

	for j = 2, size do
		component = component[paths[j]]
		if not component then
			return nil
		end
	end
	return component
end

--- Removes the state of the component before caching it, ensuring that it does not retain any state from previous updates.
--- @param comp Component the component to remove the state from
M.remove_state_before_cache = function(comp)
	rawset(comp, "_parent", nil)
	rawset(comp, "_hidden", nil)
	setmetatable(comp, nil) -- Remove metatable to avoid inheritance issues
end

--- Creates a custom statistic component, which can be used to display custom statistics in the status line.
--- @param comp Component the component to create the statistic for
--- @param override table|nil a table of overrides for the component, can be used to set custom fields or values
--- @return Component stat_comp the statistic component with the necessary fields set
M.overrides = function(comp, override)
	if type(override) ~= "table" then
		return comp
	end

	local accepted = {
		padding = { "number", "table" },
		static = { "any" },
		timing = { "boolean", "number" },
		style = { "function", "table" },
		min_screen_width = { "number" },
		hide = { "function", "boolean" },
		left_style = { "function", "table" },
		left = { "string", "function" },
		right_style = { "function", "table" },
		right = { "string", "function" },
	}
	for k, v in pairs(override or {}) do
		if accepted[k] then
			local type_v = type(v)
			if vim.tbl_contains(accepted[k], type_v) then
				if type_v == "table" then
					rawset(comp, k, vim.tbl_deep_extend("force", comp[k] or {}, v))
				else
					rawset(comp, k, v)
				end
			end
		end
	end

	return comp
end

return M
