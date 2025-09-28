local type, str_rep, rawset = type, string.rep, rawset
local CompManager = require("witch-line.core.CompManager")
local highlight = require("witch-line.core.highlight")
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

--- @class CompId : Id

--- @class Ref : table
--- @field events CompId|CompId[]|nil A table of ids of components that this component references
--- @field user_events CompId|CompId[]|nil A table of ids of components that this component references
--- @field timing CompId|CompId[]|nil A table of ids of components that this component references
--- @field style CompId|nil A id of a component that this component references for its style
--- @field static CompId|nil A id of a component that this component references for its static values
--- @field context CompId|nil A id of a component that this component references for its context
--- @field hide CompId|CompId[]|nil A table of ids of components that this component references for its hide function
--- @field min_screen_width CompId|CompId[]|nil A table of ids of components that this component references for its minimum screen width

--- @class LiteralComponent : string
--- @class NestedComponent : Component, LiteralComponent
--- @field [integer] NestedComponent a table of childs, can be used to create a list of components

--- @class Component : table
--- @field id CompId The unique identifier for the component, can be a string or a number
--- @field inherit CompId|nil The id of the component to inherit from, can be used to extend a component
--- @field timing boolean|integer|nil If true the component will be updated on every tick, if a number it will be updated every n ticks
--- @field lazy boolean|nil If true the component will be loaded only when it is needed, used for lazy loading components
--- @field events string[]|nil A table of events that the component will listen to
--- @field user_events string[]|nil A table of user events that the component will listen to
--- @field min_screen_width integer|nil|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId):number|nil
--- The minimum screen width required to display the component
--- (can be used to hide components on smaller screens).
--- If the screen width is less than this value, the component will be hidden.
--- If nil, the component will always be displayed. If a function, it will be called with the component, context, static values, and session id as arguments and should return a number or nil.
--- @field ref Ref|nil A table of references to other components that this component depends on
--- @field left_style table|nil|fun(self: Component, ctx: any, static: any, session_id: SessionId):table|nil A table of styles that will be applied to the left part of the component
--- @field left string|nil|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId):string|nil The left part of the component, can be a string or another component
--- @field right_style table|nil|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId):table|nil a table of styles that will be applied to the right part of the component
--- @field right string|nil|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId):string|nil the right part of the component, can be a string or another component
--- @field padding integer|nil|{left: integer|nil, right:integer|nil}|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId): number|{left: integer|nil, right:integer|nil} the padding of the component, can be used to add space around the component
---
--- @field init nil|fun(raw_self: ManagedComponent) called when the component is initialized, can be used to set up the context
--- @field style vim.api.keyset.highlight|nil|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId): vim.api.keyset.highlight a table of styles that will be applied to the component
--- @field static any a table of static values that will be used in the component
--- @field context nil|fun(self: ManagedComponent, static:any, session_id: SessionId): any a table that will be passed to the component's update function
--- @field pre_update nil|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId) called before the component is updated, can be used to set up the context
--- @field update nil|string|fun(self:ManagedComponent, ctx: any, static: any, session_id: SessionId): string|nil called to update the component, should return a string that will be displayed
--- @field post_update nil|fun(self: ManagedComponent,ctx: any, static: any, session_id: SessionId) called after the component is updated, can be used to clean up the context
--- @field hide nil|fun(self: ManagedComponent, ctx:any, static: any, session_id: SessionId): boolean|nil called to check if the component should be displayed, should return true or false
---
--- @private
--- @field _loaded boolean|nil If true, the component is loaded
--- @field _indices integer[]|nil The render index of the component in the statusline
--- @field _hl_name string|nil The highlight group name for the component
--- @field _left_hl_name string|nil The highlight group name for the left part of the component
--- @field _right_hl_name string|nil The highlight group name for the right part of the component
--- @field _parent boolean|nil If true, the component has a parent and should inherit from it
--- @field _hidden boolean|nil If true, the component is hidden and should not be displayed
--- @field _abstract boolean|nil If true, the component is abstract and should not be displayed directly (all component are abstract)


---@class DefaultComponent : Component, NestedComponent The default components provided by witch-line
---@field id DefaultID the id of default component

--- @class ManagedComponent : Component, DefaultComponent, NestedComponent
--- @field [integer] CompId -- Child components by their IDs
--- @field _abstract true Always true, indicates that the component is abstract and should not be rendered directly
--- @field _loaded true Always true, indicates that the component has been loaded



--- Check if is default component
--- @param comp Component|DefaultComponent the component to get the id from
M.is_default = function(comp)
	local Id = require("witch-line.constant.id").Id
	return Id[comp.id] ~= nil
end

--- Gets the id of the component, if the id is a number, it will be converted to a string.
--- @param comp Component|DefaultComponent the component to get the id from
--- @return CompId id the id of the component
M.valid_id = function(comp)
	local id = comp.id and require("witch-line.constant.id").validate(comp.id)
		or (tostring(comp) .. tostring(math.random(1, 1000000)))
	rawset(comp, "id", id) -- Ensure the component has an ID field
	return id
end

--- Inherits the parent component's fields and methods, allowing for component extension.
--- @param comp Component the component to inherit from
--- @param parent Component the parent component to inherit from
M.inherit_parent = function(comp, parent)
	local inheritable_fields = require("witch-line.core.Component.inheritable_fields")
	setmetatable(comp, {
		---@diagnostic disable-next-line: unused-local
		__index = function(t, key)
			return inheritable_fields[key] and parent[key] or nil
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
---@param main_style table|nil the main style of the component, used to determine the side style
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
			highlight.highlight(side_hl_name, style)
			return
		end
	end

	if type(style) == "function" then
		style = style(comp, ctx, static, ...)
		--- Always update the highlight if a function
		if type(style) == "table" then
			highlight.highlight(side_hl_name, style)
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
			highlight.highlight(side_hl_name, style)
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
	local force_update = false

	if type(style) == "table" then
		if not comp._hl_name then
			force_update = true
			if comp ~= ref_comp then
				rawset(ref_comp, "_hl_name", ref_comp._hl_name or highlight.gen_hl_name_by_id(ref_comp.id))
				rawset(comp, "_hl_name", ref_comp._hl_name)
			else
				rawset(comp, "_hl_name", highlight.gen_hl_name_by_id(comp.id))
			end
			highlight.highlight(comp._hl_name, style)
		elseif type(ref_comp.style) == "function" then
			force_update = true
			highlight.highlight(comp._hl_name, style)
		end
	end

	if comp.left then
		update_side_style(
			comp,
			"left_style",
			"_left_hl_name",
			force_update and style or nil,
			LEFT_SUFFIX,
			ctx,
			static,
			...
		)
	end
	if comp.right then
		update_side_style(
			comp,
			"right_style",
			"_right_hl_name",
			force_update and style or nil,
			RIGHT_SUFFIX,
			ctx,
			static,
			...
		)
	end
end

--- @param comp Component the component to evaluate
--- @param ctx any the context to pass to the component's update function
--- @param static any the static values to pass to the component's update function
--- @param ... any additional arguments to pass to the component's update function
--- @return string value the new value of the component
M.evaluate = function(comp, ctx, static, ...)
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
			left = call_or_get(left, comp, ctx, static)
			if type(left) ~= "string" then
				left = ""
			end
		end
		if right then
			right = call_or_get(right, comp, ctx, static)
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
--- @return DefaultComponent|nil comp the component if it exists, or nil if it does not
M.require_by_id = function(id)
	return M.require(id)
end

--- @param path DefaultID|string the path to the component, e.g. "file.name" or "git.status"
--- @return DefaultComponent|nil comp the component if it exists, or nil if it does not
M.require = function(path)
	local Id = require("witch-line.constant.id").Id
	if not Id[path] then
		return nil
	end

	local paths = vim.split(path, ".", { plain = true })
	local size = #paths
	local module_path = COMP_MODULE_PATH .. paths[1]

	local ok, component = require(module_path)
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

	local accepted = require("witch-line.core.Component.overridable_types")
	for k, v in pairs(override) do
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

--- Gets the minimum screen width required to display the component.
--- @param comp Component the component to get the minimum screen width from
--- @param ctx any the context to pass to the component's update function
--- @param static any the static values to pass to the component's update function
--- @return number|nil min_screen_width the minimum screen width required to display the component, or nil if it is not defined
M.min_screen_width = function(comp, ctx, static)
	local min_screen_width = call_or_get(comp.min_screen_width, comp, ctx, static)
	return type(min_screen_width) == "number" and min_screen_width or nil
end

return M
