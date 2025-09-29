local type, str_rep, rawset = type, string.rep, rawset
local Highlight = require("witch-line.core.highlight")
local eval = require("witch-line.utils").eval

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

--- @class CombinedComponent : Component, LiteralComponent
--- @field [integer] CombinedComponent a table of childs, can be used to create a list of components

--- @alias PaddingTable {left: integer|nil|PaddingFunc, right:integer|nil|PaddingFunc}
--- @alias PaddingFunc fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId): number|PaddingTable
--- @alias UpdateFunc fun(self:ManagedComponent, ctx: any, static: any, session_id: SessionId): string|nil
--- @alias StyleFunc fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId): vim.api.keyset.highlight
--- @alias SideStyleFunc fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId): table|SepStyle
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
--- @field left_style table|nil|SideStyleFunc A table of styles that will be applied to the left part of the component
--- @field left string|nil|UpdateFunc The left part of the component, can be a string or another component
--- @field right_style table|nil|SideStyleFunc a table of styles that will be applied to the right part of the component. It can be a table of styles  or SepStyle enum or a function that returns a table of styles or a SepStyle enum value.
--- @field right string|nil|UpdateFunc the right part of the component, can be a string or another component
--- @field padding integer|nil|PaddingTable|PaddingFunc the padding of the component, can be used to add space around the component
--- @field init nil|fun(raw_self: ManagedComponent) called when the component is initialized, can be used to set up the context
--- @field style vim.api.keyset.highlight|nil|StyleFunc a table of styles that will be applied to the component
--- @field static any a table of static values that will be used in the component
--- @field context nil|fun(self: ManagedComponent, static:any, session_id: SessionId): any a table that will be passed to the component's update function
--- @field pre_update nil|fun(self: ManagedComponent, ctx: any, static: any, session_id: SessionId) called before the component is updated, can be used to set up the context
--- @field update nil|string|UpdateFunc called to update the component, should return a string that will be displayed
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
--- @field _style_changing boolean|nil If true, the component's style is changing and should be updated

---@class DefaultComponent : Component, CombinedComponent The default components provided by witch-line
---@field id DefaultId the id of default component

--- @class ManagedComponent : Component, DefaultComponent, CombinedComponent
--- @field [integer] CompId -- Child components by their IDs
--- @field _abstract true Always true, indicates that the component is abstract and should not be rendered directly
--- @field _loaded true Always true, indicates that the component has been loaded



--- Check if is default component
--- @param comp Component the component to get the id from
M.is_default = function(comp)
	local Id = require("witch-line.constant.id").Id
	return Id[comp.id] ~= nil
end

--- Ensures that the component has a valid id, generating one if it does not.
--- @param comp Component the component to get the id from
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

--- Emits the `pre_update` event for the component, calling the pre_update function if it exists.
--- @param comp Component the component to emit the event for
--- @param session_id SessionId the session id to use for the component, used for lazy loading components
--- @param ctx any The `context` field value to pass to the component's update function
--- @param static any The `static` field value to pass to the component's update function
M.emit_pre_update = function(comp, session_id, ctx, static)
	if type(comp.pre_update) == "function" then
		comp.pre_update(comp, ctx, static, session_id)
	end
end

--- Emits the `post_update` event for the component, calling the post_update function if it exists.
--- @param comp Component the component to emit the event for
--- @param session_id SessionId the session id to use for the component, used for lazy
--- @param ctx any The `context` field value to pass to the component's update function
--- @param static any The `static` field value to pass to the component's update function
M.emit_post_update = function(comp, session_id, ctx, static)
	if type(comp.post_update) == "function" then
		comp.post_update(comp, ctx, static, session_id)
	end
end


--- Ensures that a component has a highlight name.
--- If it doesn't, it will be inherited from the reference component or generated.
--- @param comp Component
--- @param ref_comp Component
M.ensure_hl_name = function(comp, ref_comp)
	if comp._hl_name then
		return
	end

	if comp ~= ref_comp then
		if ref_comp._hl_name then
			rawset(comp, "_hl_name", ref_comp._hl_name)
		else
			rawset(ref_comp, "_hl_name", Highlight.make_hl_name_from_id(ref_comp.id))
			rawset(comp, "_hl_name", ref_comp._hl_name)
		end
	else
		rawset(comp, "_hl_name", Highlight.make_hl_name_from_id(comp.id))
	end
end

--- Determines if the component's style should be updated.
--- @param comp Component the component to checks
--- @param style table|nil the current style of the component
--- @param ref_comp Component the reference component to compare against
--- @return boolean should_update true if the style should be updated, false otherwise
M.needs_style_update = function(comp, style, ref_comp)
	if type(style) ~= "table" then
		return false
	elseif not comp._hl_name == nil then
		return true
	elseif type(ref_comp.style) == "function" then
		return true
	end
	return false
end

--- Updates the style of the component.
--- @param comp Component the component to update
--- @param style table the new style to apply to the component
M.update_style = function(comp, style)
	Highlight.highlight(comp._hl_name, style)
end

--- Determines if the separator style needs to be updated.
--- @param comp Component the component to checks
--- @param side "left"|"right" the side to check, either "left" or "right"
M.needs_side_style_update = function(comp, side)
	local side_hl_name = side .. "_hl_name"
	if not comp[side_hl_name] then
		return true
	elseif type(comp[side .. "_style"]) == "function" then
		return true
	end
	return false
end

--- Ensures that a component has a highlight name for the specified side (left or right).
--- If it doesn't, it will be generated based on the component's id.
--- @param comp Component
--- @param side "left"|"right"
M.ensure_side_hl_name = function(comp, side)
	local field = side .. "_hl_name"
	if not comp[field] then
		local hl_name = comp._hl_name or Highlight.make_hl_name_from_id(comp.id)
		--- If the component already has a main highlight name, use it as the base
		rawset(comp, field, hl_name .. side)
	end
end

--- Updates the style of a side (left or right) of the component.
--- @param comp Component the component to update
--- @param side "left"|"right" the side to update
--- @param session_id SessionId the session id to use for the component
--- @param ctx any The `context` field value to pass to the component's update function	
--- @param static any The `static` field value to pass to the component's update function
M.update_side_style = function(comp, side, main_style, session_id, ctx, static)
	local hl_name_field = side .. "_hl_name"
	local side_hl_name = comp[hl_name_field]

	local side_style = comp[side .. "_style"]

	if type(side_style) == "function" then
		side_style = side_style(comp, ctx, static, session_id)
	end

	local type_side_style = type(side_style)
	if type_side_style == "table" then
		Highlight.highlight(side_hl_name, side_style)
	elseif type_side_style == "nil" then
		--- inherits from main style
		rawset(comp, hl_name_field, comp._hl_name)
		return
	elseif type_side_style == "number" and main_style then
		if side_style == SepStyle.SepFg then
			side_style = {
				fg = main_style.fg,
				bg = "NONE",
			}
		elseif side_style == SepStyle.SepBg then
			side_style = {
				fg = main_style.bg,
				bg = "NONE",
			}
		elseif side_style == SepStyle.Reverse then
			side_style = {
				fg = main_style.bg,
				bg = main_style.fg,
			}
		elseif side_style == SepStyle.Full then
			rawset(comp, hl_name_field, comp._hl_name)
		else
			--- invalid styles
			return
		end

		if type(side_style) == "table" then
			Highlight.highlight(side_hl_name, side_style)
		end
	end
end



--- Evaluates the component's update function and applies padding if necessary, returning the resulting string.
--- @param comp Component the component to evaluate
--- @param ctx any The `context` field value to pass to the component's update function
--- @param static any The `static` field value to pass to the component's update function
--- @param session_id SessionId the session id to use for the component
--- @return string value the new value of the component
M.evaluate = function(comp, session_id, ctx, static)
	local result = eval(comp.update, comp, ctx, static, session_id)

	if type(result) ~= "string" then
		result = ""
	elseif result ~= "" then
		local padding = eval(comp.padding or 1, comp, ctx, static, session_id)
		local p_type = type(padding)
		if p_type == "number" and padding > 0 then
			local pad = str_rep(" ", padding)
			result = pad .. result .. pad
		elseif p_type == "table" then
			local left, right =
				eval(padding.left, comp, ctx, static, session_id),
				eval(padding.right, comp, ctx, static, session_id)

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
			left = eval(left, comp, ctx, static)
			if type(left) ~= "string" then
				left = ""
			end
		end
		if right then
			right = eval(right, comp, ctx, static)
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

--- @param path DefaultId|string the path to the component, e.g. "file.name" or "git.status"
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
	local min_screen_width = eval(comp.min_screen_width, comp, ctx, static)
	return type(min_screen_width) == "number" and min_screen_width or nil
end

return M
