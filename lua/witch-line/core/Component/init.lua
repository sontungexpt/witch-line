local require, type, str_rep, rawset = require, type, string.rep, rawset
local resolve = require("witch-line.utils").resolve

local COMP_MODULE_PATH = "witch-line.components."

local Component = {}

--- @enum SepStyle
local SepStyle = {
	Inherited = 0, -- use the style of the component
	SepFg = 1,
	SepBg = 2,
	Reverse = 3, -- use the reverse style of the component }
}
Component.SepStyle = SepStyle

--- @class CompId : string

--- @class Reference : table
--- @field events? CompId|CompId[] A table of ids of components that this component references
--- @field timing? CompId|CompId[] A table of ids of components that this component references
--- @field hidden? CompId|CompId[] A table of ids of components that this component references for its hide function
--- @field min_screen_width? CompId|CompId[] A table of ids of components that this component references for its minimum screen width
---
--- @field static? CompId A id of a component that this component references for its static values
--- @field context? CompId A id of a component that this component references for its context
--- @field style? CompId A id of a component that this component references for its style
--- @field left? CompId A id of a component that this components references for left separator
--- @field left_style? CompId A id of a component that this component references for its left_style
--- @field right? CompId A id of a component that this components references for right separator
--- @field right_style? CompId A id of a component that this component references for its right_style

--- @class LiteralComponent : string

--- @class CombinedComponent : Component, LiteralComponent
--- @field [integer] CombinedComponent a table of childs, can be used to create a list of components

--- @alias PaddingFunc fun(self: ManagedComponent, sid: SessionId): number|PaddingTable
--- @alias PaddingTable {left: integer|nil|PaddingFunc, right:integer|nil|PaddingFunc}
---
--- @alias UpdateFunc fun(self:ManagedComponent,  sid: SessionId): string|nil , CompStyle|nil|
---
--- @alias CompStyle vim.api.keyset.highlight|string
--- @alias StyleFunc fun(self: ManagedComponent, sid: SessionId): CompStyle
--- @alias SideStyleFunc fun(self: ManagedComponent, sid: SessionId): CompStyle|SepStyle
---
--- @alias OnClickFunc fun(self: ManagedComponent, minwid: 0, click_times: number, mouse_button: "l"|"r"|"m", modifier_pressed: "s"|"c"|"a"|"m"): nil
--- @alias OnClickTable {callback: OnClickFunc|string, name: string|nil}
---
---
--- @class Component.SpecialEvent
--- @field [integer] string event name
--- @field once? boolean Optional flag. If true, the event is triggered only once.
---
--- Optional file/buffer pattern(s).
--- Can be:
---   - string: a single pattern
---   - string[]: list of patterns
---   - nil: no pattern filtering
--- Empty strings or "*" are treated as no pattern.
--- @field pattern? string|string[]
--- @field remove_when? fun():boolean The event will be remove when `remove_when` return true
---
--- @class Component : table
--- @field id? CompId The unique identifier for the component, can be a string or a number
---
--- The version of the component, can be used to force reload the component when it changes
--- - If provided, the component will be reloaded on start if the version changes manually when update component configurations by user. It's help the cache system work faster if speed is more important because the user manage the version manually.
--- - If nil, the component will automatically reload when the component changes by search for the changes by Cache system.
--- @field version? integer|string
---
--- The id of the component to inherit from, can be used to extend a component
--- @field inherit? CompId
---
--- A timing configuration that determines how often the component is updated.
--- - If true, the component will be updated on every 1 second.
--- - If a number, the component will be updated every n ticks.
--- @field timing? boolean|integer
---
---
--- A fllag indicating whether the component should be lazy loaded or not.
--- @field lazy? boolean
---
--- The priority of the component when the status line is too long, higher numbers are more likely to be truncated
--- @field flexible? number
---
--- A table of events that the component will listen to
---
--- @field events? string|string[]|Component.SpecialEvent[]
---
--- Minimum screen width required to show the component.
--- - If integer: component is hidden when screen width is smaller.
--- - If nil: always visible.
--- - If function: called and its return value is used as above.
--- - Example of min_screen_width function: `function(self: ManagedComponent, sid: SessionId) return 80 end`
--- @field min_screen_width? integer|fun(self: ManagedComponent, sid: SessionId):number|nil
---
--- @field ref? Reference A table of references to other components that this component depends on
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
--- - Example of left_style function: `function(self, sid) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field left_style? CompStyle|SideStyleFunc|SepStyle
---
--- The left separator of the component
--- - If string: used as is.
--- - If nil: no left part.
--- - If function: called and its return value is used as the left part.
--- - Example of left function: `function(self, sid) return "<" end`
--- @field left? string|UpdateFunc
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
--- - Example of right_style function: `function(self, sid) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field right_style? CompStyle|SideStyleFunc|SepStyle
---
--- The right separator of the component
--- - If string: used as is.
--- - If nil: no right part.
--- - If function: called and its return value is used as the right part.
--- - Example of right function: `function(self, sid) return ">" end`
--- @field right? string|UpdateFunc
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
--- - Example of padding function: `function(self, sid) return {left = 2, right = 1} end`
--- - Example of padding function: `function(self, sid) return 2 end` (adds 2 spaces to both sides)
--- @field padding? integer|PaddingTable|PaddingFunc
---
--- An initialization function that will be called when the component is first loaded
--- - If nil: no initialization function will be called.
--- - If string: required the string as a module and called it with the component and sid as arguments.
--- - If function: called with the component and sid as arguments.
--- @field init? fun(self: ManagedComponent, sid: SessionId)
---
--- A table of styles that will be applied to the component
--- - If string: used as a highlight group name.
--- - If table: used as is.
--- - If nil: No style will be applied.
--- - If function: called and its return value is used as above.
--- - Example of style table: `{fg = "#ffffff", bg = "#000000", bold = true}`
--- - Example of style function: `function(self, sid) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field style? CompStyle|StyleFunc
---
--- @field temp any A temporary field that can be used to store temporary values, will not be cached
---
--- A static field that can be accessed by the`use_static` hook
--- - If nil: no static will be passed.
--- - If table: used as is.
--- @field static? table
---
--- A context field that can be accessed by the `use_context` hook
--- - If nil: no context will be passed.
--- - If function: called and its return value is used as above.
--- - If string: required the string as a module and used as is.
--- - Example of context function: `function(self, sid) return {buffer = vim.api.nvim_get_current_buf()} end`
--- @field context? table|fun(self: ManagedComponent): table
---
--- A function that will be called before the component is updated
--- @field pre_update? fun(self: ManagedComponent, sid: SessionId)
---
--- The update function that will be called to get the value of the component
--- - If string: used as is.
--- - If nil: the component will not be updated.
--- - If function: called and its return value and style are used as the new value and style of the component
--- - Example of update function: `function(self, sid) return "Hello World" end`
--- - Example of update function with style: `function(self, sid) return "Hello World", {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field update? string|UpdateFunc
---
--- A function that will be called after the component is updated
--- @field post_update? fun(self: ManagedComponent, sid: SessionId)
---
--- Called to check if the component should be displayed, should return true or false
--- - If nil: the component is always shown.
--- - If function: called and its return value is used to determine if the component should be
--- @field hidden? fun(self: ManagedComponent, sid: SessionId): boolean|nil
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
--- @field on_click? string|OnClickFunc|OnClickTable A function or the name of a global function to call when the component is clicked
---
--- @private The following fields are used internally by witch-line and should not be set manually
--- @field _loaded? boolean If true, the component is loaded
--- @field _indices? integer[] The render index of the component in the statusline
--- @field _hl_name? string The highlight group name for the component
--- @field _left_hl_name? string The highlight group name for the left part of the component
--- @field _right_hl_name? string The highlight group name for the right part of the component
--- @field _hidden? boolean If true, the component is hidden and should not be displayed
--- @field _abstract? boolean If true, the component is abstract and should not be displayed directly (all component are abstract)
--- @field _click_handler? string The name of the click handler function for the component

--- @class DefaultComponent : Component The default components provided by witch-line
--- @field id DefaultId the id of default component
--- @field _plug_provided true Mark as created by witch-line

--- @class ManagedComponent : Component, DefaultComponent
--- @field id CompId the id of component
--- @field [integer] CompId -- Child components by their IDs
--- @field _abstract true Always true, indicates that the component is abstract and should not be rendered directly
--- @field _loaded true Always true, indicates that the component has been loaded

--- Check if is default component
--- @param comp Component the component to get the id from
Component.is_default = function(comp)
	return require("witch-line.constant.id").existed(comp.id)
end

--- Ensures that the component has a valid id, generating one if it does not.
--- @param comp Component|DefaultComponent the component to get the id from
--- @return CompId id the id of the component
--- @return Component|DefaultComponent|nil comp the component itself, or nil if it is a default component
Component.setup = function(comp)
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
	require("witch-line.core.Component.initial_state").save_initial_context(comp)
	---@cast id CompId
	return id, comp
end

--- Emits the `pre_update` event for the component, calling the pre_update function if it exists.
--- @param comp Component the component to emit the event for
--- @param sid SessionId the session id to use for the component, used for lazy loading components
Component.emit_pre_update = function(comp, sid)
	local pre_update = comp.pre_update
	if type(pre_update) == "function" then
		pre_update(comp, sid)
	end
end

--- Emits the `post_update` event for the component, calling the post_update function if it exists.
--- @param comp Component the component to emit the event for
--- @param sid SessionId the session id to use for the component, used for lazy
Component.emit_post_update = function(comp, sid)
	local post_update = comp.post_update
	if type(post_update) == "function" then
		post_update(comp, sid)
	end
end

--- Emits the `init` event for the component, calling the init function if it exists.
--- @param comp Component the component to emit the event for
--- @param sid SessionId the session id to use for the component, used for lazy loading components
Component.emit_init = function(comp, sid)
	local init = comp.init
	if type(init) == "function" then
		init(comp, sid)
	end
end

--- Returns the field name for the highlight name of the specified side.
--- @param side "left"|"right" the side to get the field name for, either "left" or "right"
--- @return string field_name the field name for the highlight name of the specified side
Component.hl_name_field = function(side)
	return side == "left" and "_left_hl_name" or "_right_hl_name"
end

--- Returns the field name for the style of the specified side.
--- @param side "left"|"right" the side to get the field name for, either "left" or "right"
--- @return CompStyle|nil|SideStyleFunc|SepStyle field_name the field name for the style of the specified side
Component.side_style = function(comp, side)
	return comp[side == "left" and "left_style" or "right_style"] or SepStyle.SepBg
end

--- Evaluates the component's update function and applies padding if necessary, returning the resulting string.
--- @param comp Component the component to resolveuate
--- @param sid SessionId the session id to use for the component
--- @return string value the new value of the component
--- @return CompStyle|nil style the new style of the component
Component.evaluate = function(comp, sid)
	local result, style = resolve(comp.update, comp, sid)

	if type(result) ~= "string" then
		result = ""
	elseif result ~= "" then
		local padding = resolve(comp.padding or 1, comp, sid)
		local p_type = type(padding)
		if p_type == "number" and padding > 0 then
			local pad = str_rep(" ", padding)
			result = pad .. result .. pad
		elseif p_type == "table" then
			local left, right = resolve(padding.left, comp, sid), resolve(padding.right, comp, sid)

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

--- Requires a default component by its id.
--- @param id CompId the path to the component, e.g. "file.name" or "git.status"
--- @return DefaultComponent|nil comp the component if it exists, or nil if it does not
Component.require_by_id = function(id)
	local path = require("witch-line.constant.id").path(id)
	if not path then
		return nil
	end
	return Component.require(path)
end

--- Requires a default component by its path.
--- @param path DefaultComponentPath the path to the component, e.g. "file.name" or "git.status"
--- @return DefaultComponent|nil comp the component if it exists, or nil if it does not
Component.require = function(path)
	local zero = path:find("\0", 2, true)
	if not zero then
		return require(COMP_MODULE_PATH .. path)
	end

	local module_path, idx_path = path:sub(1, zero - 1), path:sub(zero + 1)
	local component = require(COMP_MODULE_PATH .. module_path)

	for key in idx_path:gmatch("[^%.]+") do
		component = component[key]
		if not component then
			return nil
		end
	end
	return component
end

--- Removes the state of the component before caching it, ensuring that it does not retain any state from previous updates.
--- @param comp Component the component to remove the state from
Component.format_state_before_cache = function(comp)
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
	elseif next(from) == nil then
		return to
	elseif vim.islist(to) and vim.islist(from) then
		return from
	end

	for k, v in pairs(from) do
		to[k] = overrides_component_value(to[k], v, skip_type_check)
	end
	return to
end
--- Creates a custom statistic component, which can be used to display custom statistics in the status line.
--- @param comp Component the component to create the statistic for
--- @param override table|nil a table of overrides for the component, can be used to set custom fields or values
--- @return Component stat_comp the statistic component with the necessary fields set
Component.overrides = function(comp, override)
	if type(override) ~= "table" then
		return comp
	end

	local accepted = require("witch-line.core.Component.overridable_types")
	for k, v in pairs(override) do
		local types_accepted = accepted[k]
		if types_accepted then
			local type_v = type(v)
			if
				type(types_accepted) == "table" and vim.list_contains(accepted[k], type_v)
				or types_accepted == type_v -- single type
			then
				if type_v == "table" then
					rawset(comp, k, overrides_component_value(comp[k], v, true))
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
--- @param sid SessionId the session id to use for the component update
--- @return number|nil min_screen_width the minimum screen width required to display the component, or nil if it is not defined
Component.min_screen_width = function(comp, sid)
	local min_screen_width = resolve(comp.min_screen_width, comp, sid)
	return type(min_screen_width) == "number" and min_screen_width or nil
end

--- Checks if the component is hidden based on its `hidden` field.
--- @param comp Component the component to checks
--- @param sid SessionId the session id to use for the component update
--- @return boolean hidden whether the component is hidden
Component.hidden = function(comp, sid)
	local hidden = resolve(comp.hidden, comp, sid)
	return hidden == true
end

--- Register a function to be called when a clickable component is clicked.
--- @param comp Component The component to register the click event for.
--- @return string fun_name The name of the click handler function, or an empty string if the component is not clickable.
--- @throws if has an invalid field type
Component.register_click_handler = function(comp)
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
		if name and type(name) ~= "string" or name == "" then
			require("witch-line.utils.notifier").error("on_click.name must be a non-empty string")
			return ""
		end
		click_handler = type(name) == "string" and name or nil
		on_click = on_click.callback
		t = type(on_click)
	end

	if t == "string" and _G[on_click] then
		click_handler = on_click
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
	else
		require("witch-line.utils.notifier").error("on_click must be a function or the name of a global function")
		return ""
	end

	comp._click_handler = click_handler
	return click_handler
end

--- Determine whether a function-type value should receive the `sid` argument
--- when being evaluated for a given key.
---
--- Some keys (like "context") should not receive a session ID, since
--- their logic is independent of the session state.
---
--- @param key string  The key name to check
--- @return boolean    True if the `sid` argument should be passed to the function
Component.should_pass_sid = function(key)
	return key ~= "context"
end

return Component
