local require, type, str_rep, rawset = require, type, string.rep, rawset
local resolve = require("witch-line.utils").resolve
local Highlight = require("witch-line.core.highlight")

local COMP_MODULE_PATH = "witch-line.components."

local M = {}

--- @enum SepStyle
local SepStyle = {
	Inherited = 0, -- use the style of the component
	SepFg = 1,
	SepBg = 2,
	Reverse = 3, -- use the reverse style of the component }
}


--- @class CompId : Id

--- @class Ref : table
--- @field events CompId|CompId[]|nil A table of ids of components that this component references
--- @field user_events CompId|CompId[]|nil A table of ids of components that this component references
--- @field timing CompId|CompId[]|nil A table of ids of components that this component references
--- @field hidden CompId|CompId[]|nil A table of ids of components that this component references for its hide function
--- @field min_screen_width CompId|CompId[]|nil A table of ids of components that this component references for its minimum screen width
--- @field style CompId|nil A id of a component that this component references for its style
--- @field static CompId|nil A id of a component that this component references for its static values
--- @field context CompId|nil A id of a component that this component references for its context

--- @class LiteralComponent : string

--- @class CombinedComponent : Component, LiteralComponent
--- @field [integer] CombinedComponent a table of childs, can be used to create a list of components

--- @class Neighbor
--- @field [1] CompId The id of the neighbor component if you want to use numbered fields
--- @field id CompId The id of the neighbor component if you want to use named fields
--- @field space integer The space between the component and its neighbor
--- @field priority integer The priority of the neighbor component when the status line is too long, higher numbers are more likely to be truncated

--- @alias PaddingFunc fun(self: ManagedComponent, session_id: SessionId): number|PaddingTable
--- @alias PaddingTable {left: integer|nil|PaddingFunc, right:integer|nil|PaddingFunc}
---
--- @alias UpdateFunc fun(self:ManagedComponent,  session_id: SessionId): string|nil , CompStyle|nil|
---
--- @alias CompStyle vim.api.keyset.highlight|string
--- @alias StyleFunc fun(self: ManagedComponent, session_id: SessionId): CompStyle
--- @alias SideStyleFunc fun(self: ManagedComponent, session_id: SessionId): CompStyle|SepStyle
---
--- @alias OnClickFunc fun(self: ManagedComponent, minwid: 0, click_times: number, mouse button: "l"|"r"|"m", modifier_pressed: "s"|"c"|"a"|"m"): nil
--- @alias OnClickTable {callback: OnClickFunc|string, name: string|nil}
---
--- @alias Component.Static table|string
--- @alias Component.Context table|string
---
--- @class Component : table
--- @field id CompId|nil The unique identifier for the component, can be a string or a number
---
--- The version of the component, can be used to force reload the component when it changes
--- - If provided, the component will be reloaded on start if the version changes manually when update component configurations by user. It's help the cache system work faster if speed is more important because the user manage the version manually.
--- - If nil, the component will automatically reload when the component changes by search for the changes by Cache system.
--- @field version integer|string|nil
---
--- The id of the component to inherit from, can be used to extend a component
--- @field inherit CompId|nil
---
--- A timing configuration that determines how often the component is updated.
--- - If true, the component will be updated on every 1 second.
--- - If a number, the component will be updated every n ticks.
--- @field timing boolean|integer|nil
---
---
--- A fllag indicating whether the component should be lazy loaded or not.
--- @field lazy boolean|nil
---
--- The priority of the component when the status line is too long, higher numbers are more likely to be truncated
--- @field flexible number|nil
---
--- A table of events that the component will listen to
--- @field events string|string[]|nil
---
--- A table of user events that the component will listen to
--- @field user_events string|string[]|nil
---
--- Minimum screen width required to show the component.
--- - If integer: component is hidden when screen width is smaller.
--- - If nil: always visible.
--- - If function: called and its return value is used as above.
--- - Example of min_screen_width function: `function(self: ManagedComponent, session_id: SessionId) return 80 end`
--- @field min_screen_width integer|nil|fun(self: ManagedComponent, session_id: SessionId):number|nil
---
--- @field ref Ref|nil A table of references to other components that this component depends on
---
--- @field neighbors Neighbor[]|nil A table of neighbor components that this component is related to ( Not implemented yet )
---
--- A table of styles that will be applied to the left separator of the component
--- - If string: used as a highlight group name.
--- - If table: used as highlight table properties.
--- - If nil: inherits from `style` field..
--- - If SepStyle enum value: special handling based on the enum value.
--- 	- SepFg: uses the foreground color of the main style for the separator.
--- 	- SepBg: uses the background color of the main style for the separator.
--- 	- Reverse: swaps the foreground and background colors of the main style for the separator.
--- 	- Inherited: inherits the main style directly.
--- - If function: called and its return value is used as above.
--- - Example of left_style function: `function(self, session_id) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field left_style CompStyle|nil|SideStyleFunc|SepStyle
---
--- The left separator of the component
--- - If string: used as is.
--- - If nil: no left part.
--- - If function: called and its return value is used as the left part.
--- - Example of left function: `function(self, session_id) return "<" end`
--- @field left string|nil|UpdateFunc
---
--- A table of styles that will be applied to the right part of the component
--- - If string: used as a highlight group name.
--- - If table: used as highlight table properties.
--- - If nil: inherits from `style` field..
--- - If SepStyle enum value: special handling based on the enum value.
--- 	- SepFg: uses the foreground color of the main style for the separator.
--- 	- SepBg: uses the background color of the main style for the separator.
--- 	- Reverse: swaps the foreground and background colors of the main style for the separator.
--- 	- Inherited: inherits the main style directly.
--- - If function: called and its return value is used as above.
--- - Example of right_style function: `function(self, session_id) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field right_style CompStyle|nil|SideStyleFunc|SepStyle
---
--- The right separator of the component
--- - If string: used as is.
--- - If nil: no right part.
--- - If function: called and its return value is used as the right part.
--- - Example of right function: `function(self, session_id) return ">" end`
--- @field right string|nil|UpdateFunc
---
--- The padding of the component
--- - If integer: number of spaces to add to both sides of the component.
--- - If nil: defaults to 1 space on both sides.
--- - If table: a table with `left` and `right` fields specifying the number of spaces for each side.
--- 	- If `left` or `right` is nil, it defaults to 0 for that side.
--- 	- Example: `{left = 2, right = 1}` adds 2 spaces to the left and 1 space to the right.
---  	- Example: `{left = 2}` adds 2 spaces to the left and 0 spaces to the right.
--- 	- Example: `{right = 3}` adds 0 spaces to the left and 3 spaces to the right.
---  	- Example: `{}` adds 0 spaces to both sides.
--- 	- If `left` or `right` is a function, it will be called to get the number of spaces for that side.
---  	- Example: `{left = function() return 2 end, right = 1}` adds 2 spaces to the left and 1 space to the right.
---  	- Example: `{left = 2, right = function() return 3 end}` adds 2 spaces to the left and 3 spaces to the right.
---  	- Example: `{left = function() return 2 end, right = function() return 3 end}` adds 2 spaces to the left and 3 spaces to the right.
---	- If function: called and its return value is used as above.
--- - Example of padding function: `function(self, session_id) return {left = 2, right = 1} end`
--- - Example of padding function: `function(self, session_id) return 2 end` (adds 2 spaces to both sides)
--- @field padding integer|nil|PaddingTable|PaddingFunc
---
--- An initialization function that will be called when the component is first loaded
--- - If nil: no initialization function will be called.
--- - If string: required the string as a module and called it with the component and session_id as arguments.
--- - If function: called with the component and session_id as arguments.
--- @field init nil|string|fun(self: ManagedComponent, session_id: SessionId)
---
--- A table of styles that will be applied to the component
--- - If string: used as a highlight group name.
--- - If table: used as is.
--- - If nil: No style will be applied.
--- - If function: called and its return value is used as above.
--- - Example of style table: `{fg = "#ffffff", bg = "#000000", bold = true}`
--- - Example of style function: `function(self, session_id) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field style CompStyle|nil|StyleFunc
---
--- @field temp any A temporary field that can be used to store temporary values, will not be cached
---
--- A static field that can be accessed by the`use_static` hook
--- - If nil: no static will be passed.
--- - If table: used as is.
--- - If string: required the string as a module and used as is.
--- @field static nil|Component.Static
---
--- A context field that can be accessed by the `use_context` hook
--- - If nil: no context will be passed.
--- - If function: called and its return value is used as above.
--- - If string: required the string as a module and used as is.
--- - Example of context function: `function(self, session_id) return {buffer = vim.api.nvim_get_current_buf()} end`
--- @field context nil|Component.Context|fun(self: ManagedComponent): Component.Context
---
--- A function that will be called before the component is updated
--- @field pre_update nil|fun(self: ManagedComponent, session_id: SessionId)
---
--- The update function that will be called to get the value of the component
--- - If string: used as is.
--- - If nil: the component will not be updated.
--- - If function: called and its return value and style are used as the new value and style of the component
--- - Example of update function: `function(self, session_id) return "Hello World" end`
--- - Example of update function with style: `function(self, session_id) return "Hello World", {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field update nil|string|UpdateFunc
---
--- A function that will be called after the component is updated
--- @field post_update nil|fun(self: ManagedComponent, session_id: SessionId)
---
--- Called to check if the component should be displayed, should return true or false
--- - If nil: the component is always shown.
--- - If function: called and its return value is used to determine if the component should be
--- @field hidden nil|fun(self: ManagedComponent, session_id: SessionId): boolean|nil
---
---
--- A function or the name of a global function to call when the component is clicked
--- - If nil: the component is not clickable.
--- - If string: the name of a global function to call when the component is clicked.
--- - If function: a function to call when the component is clicked.
--- - If table: a table with the following fields:
---  - `callback`: a function or the name of a global function to call when the component is clicked.
---  - `name`: the name of the function to register, if not provided a name will be generated.
---  like:
---  ```lua
---  {
---    name = "MyClickHandler", -- optional
---    callback = function(comp, minwid, click_times, mouse button, modifier_pressed) end
---    -- If callback is a string, don't care about the name field
---    -- or callback = "MyClickHandler" -- the name of a global function
---  }
---  ```
--- @field on_click nil|string|OnClickFunc|OnClickTable A function or the name of a global function to call when the component is clicked
---
--- @private The following fields are used internally by witch-line and should not be set manually
--- @field _loaded boolean|nil If true, the component is loaded
--- @field _indices integer[]|nil The render index of the component in the statusline
--- @field _hl_name string|nil The highlight group name for the component
--- @field _left_hl_name string|nil The highlight group name for the left part of the component
--- @field _right_hl_name string|nil The highlight group name for the right part of the component
--- @field _hidden boolean|nil If true, the component is hidden and should not be displayed
--- @field _abstract boolean|nil If true, the component is abstract and should not be displayed directly (all component are abstract)
--- @field _click_handler string|nil The name of the click handler function for the component

--- @class DefaultComponent : Component The default components provided by witch-line
--- @field id DefaultId the id of default component
--- @field _plug_provided true Mark as created by witch-line

--- @class ManagedComponent : Component, DefaultComponent
--- @field [integer] CompId -- Child components by their IDs
--- @field _abstract true Always true, indicates that the component is abstract and should not be rendered directly
--- @field _loaded true Always true, indicates that the component has been loaded

--- Check if is default component
--- @param comp Component the component to get the id from
M.is_default = function(comp)
	return require("witch-line.constant.id").existed(comp.id)
end

--- Ensures that the component has a valid id, generating one if it does not.
--- @param comp Component|DefaultComponent the component to get the id from
--- @return CompId id the id of the component
--- @return Component|DefaultComponent|nil comp the component itself, or nil if it is a default component
M.setup = function(comp)
  require("witch-line.core.Component.initial_state").save_initial_context(comp)

	local id = comp.id
	if comp._plug_provided then
		---@cast id CompId
		return id
	elseif id then
		id = require("witch-line.constant.id").validate(id)
	else
		id = tostring(comp) .. tostring(math.random(1, 1000000))
		rawset(comp, "id", id) -- Ensure the component has an ID field
	end

	---@cast id CompId
	return id, comp
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
	return getmetatable(comp) ~= nil
end

--- Emits the `pre_update` event for the component, calling the pre_update function if it exists.
--- @param comp Component the component to emit the event for
--- @param session_id SessionId the session id to use for the component, used for lazy loading components
M.emit_pre_update = function(comp, session_id)
  local pre_update = comp.pre_update
	if type(pre_update) == "function" then
		pre_update(comp, session_id)
	end
end

--- Emits the `post_update` event for the component, calling the post_update function if it exists.
--- @param comp Component the component to emit the event for
--- @param session_id SessionId the session id to use for the component, used for lazy
M.emit_post_update = function(comp, session_id)
  local post_update = comp.post_update
	if type(post_update) == "function" then
		post_update(comp, session_id)
	end
end

--- Emits the `init` event for the component, calling the init function if it exists.
--- @param comp Component the component to emit the event for
--- @param session_id SessionId the session id to use for the component, used for lazy loading components
M.emit_init = function(comp, session_id)
  local init = comp.init
  local t = type(init)
  if t == "function" then
    init(comp, session_id)
  elseif t == "string" then
    require(init)(comp, session_id)
  end
end


--- Ensures that a component has a highlight name.
--- If it doesn't, it will be inherited from the reference component or generated.
--- @param comp Component the component to ensure has a highlight name
--- @param ref_comp Component the reference component to inherit from if necessary
M.ensure_hl_name = function(comp, ref_comp)
	if comp._hl_name then
		return
	elseif comp ~= ref_comp then
		if not ref_comp._hl_name then
			rawset(ref_comp, "_hl_name", Highlight.make_hl_name_from_id(ref_comp.id))
		end
		rawset(comp, "_hl_name", ref_comp._hl_name)
	else
		rawset(comp, "_hl_name", Highlight.make_hl_name_from_id(comp.id))
	end
end

--- Determines if the component's style should be updated.
--- @param comp Component the component to checks
--- @param ref_comp Component the reference component to compare against
--- @return boolean should_update true if the style should be updated, false otherwise
M.needs_style_update = function(comp, ref_comp)
	if not comp._hl_name then
		return true
	elseif type(ref_comp.style) == "function" then
		return true
	end
	return false
end

--- Updates the style of the component.
--- @param comp Component the component to update
--- @param style CompStyle the style to apply to the component
--- @param ref_comp Component the reference component to inherit from if necessary
--- @param force boolean|nil if true, forces the style to be updated even if it doesn't need to be
--- @return boolean updated true if the style was updated, false otherwise
M.update_style = function(comp, style, ref_comp, force)
  if not style then
    return false
  elseif not force and not M.needs_style_update(comp,  ref_comp) then
		return false
	end
	M.ensure_hl_name(comp, ref_comp)
	return Highlight.highlight(comp._hl_name, style)
end


--- Returns the field name for the highlight name of the specified side.
--- @param side "left"|"right" the side to get the field name for, either "left" or "right"
--- @return string field_name the field name for the highlight name of the specified side
local function hl_name_field(side)
  return side == "left" and "_left_hl_name" or "_right_hl_name"
end

--- Returns the field name for the style of the specified side.
--- @param side "left"|"right" the side to get the field name for, either "left" or "right"
--- @return string field_name the field name for the style of the specified side
local function style_field(side)
  return side == "left" and "left_style" or "right_style"
end

--- Determines if the separator style needs to be updated.
--- @param comp Component the component to checks
--- @param side "left"|"right" the side to check, either "left" or "right"
--- @param side_style CompStyle|SepStyle the style of the side to check
--- @param main_style_updated boolean true if the main style was updated, false otherwise
--- @return boolean needs_update true if the style needs to be updated, false otherwise
M.needs_side_style_update = function(comp, side, side_style, main_style_updated)
  if not comp[side] then -- no side, no need to update
    return false
  elseif not comp[hl_name_field(side)] then
		return true
	elseif type(comp[style_field(side)]) == "function" then
		return true
	elseif main_style_updated then
		return type(side_style) == "number" and
      (
        side_style == SepStyle.SepFg
        or side_style == SepStyle.SepBg
        or side_style == SepStyle.Reverse
        or side_style == SepStyle.Inherited
      )
	end
	return false
end


--- Ensures that a component has a highlight name for the specified side (left or right).
--- If it doesn't, it will be generated based on the component's id.
--- @param comp Component the component to ensure has a highlight name for the specified side
--- @param side "left"|"right" the side to ensure has a highlight name, either "left" or "right"
M.ensure_side_hl_name = function(comp, side)
  local field = hl_name_field(side)
	if not comp[field] then
		--- If the component already has a main highlight name, use it as the base
		rawset(comp, field, (comp._hl_name or Highlight.make_hl_name_from_id(comp.id)) .. side)
	end
end

--- Updates the style of a side (left or right) of the component.
--- @param comp Component the component to update
--- @param side "left"|"right" the side to update
--- @param main_style CompStyle|nil the main style of the component, used for inheriting styles
--- @param main_style_updated boolean true if the main style was updated, false otherwise
--- @param session_id SessionId the session id to use for the component
--- @return boolean updated true if the style was updated, false otherwise
M.update_side_style = function(comp, side, main_style, main_style_updated, session_id)
	local side_style = resolve(comp[style_field(side)] or SepStyle.SepBg, comp, session_id)
	if not M.needs_side_style_update(comp, side, side_style, main_style_updated) then
		return false
	end

	M.ensure_side_hl_name(comp, side)

	if type(side_style) == "number" and main_style then
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
		elseif side_style == SepStyle.Inherited then
			rawset(comp, hl_name_field(side), comp._hl_name)
      return true
		else
			--- invalid styles
			return false
		end
	end

  return Highlight.highlight(comp[hl_name_field(side)], side_style)
end


--- Evaluates the component's update function and applies padding if necessary, returning the resulting string.
--- @param comp Component the component to resolveuate
--- @param session_id SessionId the session id to use for the component
--- @return string value the new value of the component
--- @return CompStyle|nil style the new style of the component
M.evaluate = function(comp, session_id)
	local result, style = resolve(comp.update, comp, session_id)

	if type(result) ~= "string" then
		result = ""
	elseif result ~= "" then
		local padding = resolve(comp.padding or 1, comp, session_id)
		local p_type = type(padding)
		if p_type == "number" and padding > 0 then
			local pad = str_rep(" ", padding)
			result = pad .. result .. pad
		elseif p_type == "table" then
			local left, right =
				resolve(padding.left, comp, session_id),
				resolve(padding.right, comp, session_id)

			if type(left) == "number" and left > 0 then
				result = str_rep(" ", left) .. result
			end
			if type(right) == "number" and right > 0 then
				result = result .. str_rep(" ", right)
			end
		end
	end

	return result, style
end

--- Evaluates a side style function, ensuring the result is a string.
--- @param comp Component the component to evaluate
--- @param side "left"|"right" the side to evaluate, either "left" or "right"
--- @param session_id SessionId the session id to use for the component
--- @return string result The evaluated side of the component, or an empty string if the result is not a string
--- @return boolean is_func true if the side was a function, false otherwise
M.evaluate_side = function(comp, side, session_id)
  local value = comp[side]
  local is_func = type(value) == "function"
  if is_func then
    value = value(comp, session_id)
  end

  if type(value) ~= "string" then
    value = ""
  end
  return value, is_func
end

--- Requires a default component by its id.
--- @param id CompId the path to the component, e.g. "file.name" or "git.status"
--- @return DefaultComponent|nil comp the component if it exists, or nil if it does not
M.require_by_id = function(id)
  local path = require("witch-line.constant.id").path(id)
  if not path then
    return nil
  end
	return M.require(path)
end

--- Requires a default component by its path.
--- @param path DefaultComponentPath the path to the component, e.g. "file.name" or "git.status"
--- @return DefaultComponent|nil comp the component if it exists, or nil if it does not
M.require = function(path)
  local pos = path:find("\0", 1, true)
  if not pos then
    return require(COMP_MODULE_PATH .. path)
  end

  local module_path, idx_path = path:sub(1, pos - 1), path:sub(pos + 1)
  local component = require(COMP_MODULE_PATH .. module_path)

	local idxs = vim.split(idx_path, ".", { plain = true })
	local size = #idxs

	for i = 1, size do
		component = component[idxs[i]]
		if not component then
			return nil
		end
	end
	return component
end

--- Removes the state of the component before caching it, ensuring that it does not retain any state from previous updates.
--- @param comp Component the component to remove the state from
M.format_state_before_cache = function(comp)
  require("witch-line.core.Component.initial_state").restore_initial_context(comp)
	rawset(comp, "_hidden", nil)
	local temp = comp.temp
	if type(temp) == "table" then
		for key, _ in pairs(temp) do
			rawset(temp, key, nil)
		end
	else
		rawset(comp, "temp", nil)
	end
	setmetatable(comp, nil) -- Remove metatable to avoid inheritance issues
end


--- Recursively overrides the values of a component with the values from another component.
--- If the types of the values are different, the value from the original component is kept.
--- If the values are not tables, the value from the new component is used.
--- If both values are tables, the function is called recursively on the tables.
--- If one of the tables is empty, the other table is used.
--- If both tables are empty, the original table is kept.
--- If both values are lists, the value from the new component is used.
--- @param to any the original component value
--- @param from any the new component value
--- @param skip_type_check boolean|nil if true, skips the type check and always overrides
--- @return any value the overridden component value
local function overrides_component_value(to, from, skip_type_check)
	if to == nil then
		return from
	elseif from == nil then
		return to
	end

	local to_type, from_type = type(to), type(from)

	if not skip_type_check and to_type ~= from_type then
		return to
	elseif from_type ~= "table" then
		return from
		-- both are table from here
	elseif next(to) == nil then
		return from
	elseif vim.islist(to) and vim.islist(from) then
		return from
	elseif next(from) == nil then
		return to
	end

	for k, v in pairs(from) do
		to[k] = overrides_component_value(to[k], v, skip_type_check)
	end
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
		local types_accepted = accepted[k]
		if types_accepted then
			local type_v = type(v)
			if type(types_accepted) == "table" and vim.list_contains(accepted[k], type_v)
				or types_accepted == type_v -- single type
			then
				if type_v == "table" then
					-- rawset(comp, k, vim.tbl_deep_extend("force", comp[k] or {}, v))
					rawset(comp, overrides_component_value(comp[k], v, true))
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
--- @param session_id SessionId the session id to use for the component update
--- @return number|nil min_screen_width the minimum screen width required to display the component, or nil if it is not defined
M.min_screen_width = function(comp, session_id)
	local min_screen_width = resolve(comp.min_screen_width, comp, session_id)
	return type(min_screen_width) == "number" and min_screen_width or nil
end

--- Checks if the component is hidden based on its `hidden` field.
--- @param comp Component the component to checks
--- @param session_id SessionId the session id to use for the component update
--- @return boolean hidden whether the component is hidden
M.hidden = function(comp, session_id)
	local hidden = resolve(comp.hidden, comp, session_id)
	return hidden == true
end

--- Register a function to be called when a clickable component is clicked.
--- @param comp Component The component to register the click event for.
--- @return string fun_name The name of the click handler function, or an empty string if the component is not clickable.
--- @throws if has an invalid field type
M.register_click_handler = function(comp)
  local click_handler = comp._click_handler
  if click_handler then
    return click_handler
  end

  local on_click = comp.on_click

  local t = type(on_click)
  if t == "table" then
    -- {
    --    name = "MyClickHandler", -- optional
    --    callback = function(comp, minwid, click_times, mouse button, modifier_pressed) end
    --    -- If callback is a string, don't care about the name field
    --    -- or callback = "MyClickHandler" -- the name of a global function
    -- }

    local name = on_click.name
    if name and type(name) ~= "string"  or name == "" then
      require("witch-line.utils.notifier").error("on_click.name must be a non-empty string")
      return ""
    end
    click_handler = type(name) == "string" and name or nil
    on_click = on_click.callback
    t = type(on_click)
  end

  if t == "string" and _G[on_click] then
    click_handler = "v:lua." .. on_click
    comp._click_handler = click_handler
    return click_handler
  elseif t == "function" then
    -- Fastest possible func_name derivation
    if not click_handler then
      click_handler = ("WLClickHandler" .. comp.id):gsub("[^%w_]", "")
    end
    if not _G[click_handler] then
      _G[click_handler] = function(...)
        on_click(comp, ...)
      end
    end
    click_handler = "v:lua." .. click_handler
    comp._click_handler = click_handler
    return click_handler
  else
    require("witch-line.utils.notifier").error("on_click must be a function or the name of a global function")
    return ""
  end
end

return M
