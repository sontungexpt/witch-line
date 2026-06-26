local require, type, str_rep, rawset, rawget, setmetatable =
    require, type, string.rep, rawset, rawget, setmetatable

local id_module = require("witch-line.constant.id")

local COMP_MODULE_PATH = "witch-line.components."

local Component = {}

--- @enum SepStyle
local SepStyle = {
    Inherited = 0,
    SepFg = 1,
    SepBg = 2,
    Reverse = 3,
}
Component.SepStyle = SepStyle

--- @class ThemeAwareStyle : vim.api.keyset.highlight
--- @field auto_theme? boolean  If true, the style automatically adapts to the current theme

--- @class CompId : string

--- @class Reference : table
--- @field events? CompId|CompId[] A table of ids of components that this component references
--- @field timing? CompId|CompId[] A table of ids of components that this component references
--- @field hidden? CompId|CompId[] A table of ids of components that this component references for its hide function
--- @field min_screen_width? CompId|CompId[] A table of ids of components that this component references for its minimum screen width
---
--- @field style? CompId A id of a component that this component references for its style
--- @field left? CompId A id of a component that this components references for left separator
--- @field left_style? CompId A id of a component that this component references for its left_style
--- @field right? CompId A id of a component that this components references for right separator
--- @field right_style? CompId A id of a component that this component references for its right_style

--- @class LiteralComponent : string

--- @class CombinedComponent : Component, LiteralComponent
--- @field [integer] CombinedComponent a table of childs, can be used to create a list of components


--- @alias PaddingFunc fun(self: ManagedComponent, session: Session): number|PaddingTable
--- @alias PaddingTable {left: integer|nil|PaddingFunc, right:integer|nil|PaddingFunc}
---
--- @alias UpdateFunc fun(self: ManagedComponent, session: Session): string|nil, CompStyle|nil
---
--- @alias CompStyle ThemeAwareStyle|string
--- @alias StyleFunc fun(self: ManagedComponent, session: Session): CompStyle
--- @alias SideStyleFunc fun(self: ManagedComponent, session: Session): CompStyle|SepStyle


--- @alias OnClickMouseButton "l"|"r"|"m"
--- @alias OnClickModifier "s"|"c"|"a"|"m"
--- @alias OnClickFunc fun(self: ManagedComponent, minwid: 0, click_times: number, mouse_button: OnClickMouseButton, modifier_pressed: OnClickModifier)
--- @alias OnClickTable {callback: OnClickFunc|string, name: string|nil}

--- @class SpecialEvent
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
--- @class Component
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
--- A flag indicating whether the component should be lazy loaded or not.
--- @field lazy? boolean
---
--- A table of static values that can be overridden by users.
--- Useful for exposing configurable constants (e.g. `{chars = {"_", "▁", "▂"}}`, `{format = "default"}`).
--- Access via `self.static` within component lifecycle functions.
--- Overridable via the component config — values are deep-merged with the built-in defaults.
--- @field static? table
---
--- The priority of the component when the status line is too long, higher numbers are more likely to be truncated
--- @field flexible? number
---
--- A function to determine whether the component should be automatically adjusted to suit the theme
--- @field auto_theme? boolean|fun(self: ManagedComponent, session: Session): boolean
---
--- A flag indicating whether the component should show individual value for each window.
--- @field win_individual? boolean
---
--- A table of events that the component will listen to
---
--- @field events? string|string[]|SpecialEvent[]
---
--- Minimum screen width required to show the component.
--- - If integer: component is hidden when screen width is smaller.
--- - If nil: always visible.
--- - If function: called and its return value is used as above.
--- - Example of min_screen_width function: `function(self: ManagedComponent, session: Session) return 80 end`
--- @field min_screen_width? integer|fun(self: ManagedComponent, session: Session): number|nil
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
--- - Example of left_style function: `function(self, ctx) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field left_style? CompStyle|SideStyleFunc|SepStyle
---
--- The left separator of the component
--- - If string: used as is.
--- - If nil: no left part.
--- - If function: called and its return value is used as the left part.
--- - Example of left function: `function(self, ctx) return "<" end`
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
--- - Example of right_style function: `function(self, ctx) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field right_style? CompStyle|SideStyleFunc|SepStyle
---
--- The right separator of the component
--- - If string: used as is.
--- - If nil: no right part.
--- - If function: called and its return value is used as the right part.
--- - Example of right function: `function(self, ctx) return ">" end`
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
--- - Example of padding function: `function(self, session) return {left = 2, right = 1} end`
--- - Example of padding function: `function(self, session) return 2 end` (adds 2 spaces to both sides)
--- @field padding? integer|PaddingTable|PaddingFunc
---
--- An initialization function that will be called when the component is first loaded.
--- @field init? fun(self: ManagedComponent, session: Session)
---
--- A table of styles that will be applied to the component
--- - If string: used as a highlight group name.
--- - If table: used as is.
--- - If nil: No style will be applied.
--- - If function: called and its return value is used as above.
--- - Example of style table: `{fg = "#ffffff", bg = "#000000", bold = true}`
--- - Example of style function: `function(self, session) return {fg = "#ffffff", bg = "#000000", bold = true} end`
--- @field style? CompStyle|StyleFunc
---
--- A function that will be called before the component is updated
--- @field pre_update? fun(self: ManagedComponent, session: Session)
---
--- The update function that will be called to get the value of the component
--- - If string: used as is.
--- - If nil: the component will not be updated.
--- - If function: called and its return value and style are used as the new value and style of the component
--- - Example of update function: `function(self, session) return "Hello World" end`
--- - Example of update function with style: `function(self, session) return "Hello World", {fg = "#ffffff", bg = "#000000", bold = true} end`
--- - Example sharing state between components via `session.state`: see git/init.lua
--- @field update? string|UpdateFunc
---
--- A function that will be called after the component is updated
--- @field post_update? fun(self: ManagedComponent, session: Session)
---
--- Called to check if the component should be displayed, should return true or false
--- - If nil: the component is always shown.
--- - If function: called and its return value is used to determine if the component should be visible
--- @field hidden? fun(self: ManagedComponent, session: Session): boolean|nil
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
--- @field _renderable? boolean If true, the component is renderable
--- @field _hidden? boolean If true, the component is hidden and should not be displayed
--- @field _use_returned_style? boolean Whether the component should use the style returned by its `update()` method. Disabled automatically when the user overrides the `style` field.
---
--- @field _hl_name? string The highlight group name for the component
--- @field _left_hl_name? string The highlight group name for the left part of the component
--- @field _right_hl_name? string The highlight group name for the right part of the component
--- @field _click_handler? string The name of the click handler function for the component

--- @class DefaultComponent : Component The default components provided by witch-line
--- @field id DefaultId the id of default component
--- @field _plug_provided true Mark as created by witch-line

--- @class ManagedComponent : Component, DefaultComponent
--- @field id CompId the id of component
--- @field [integer] CompId -- Child components by their IDs
--- @field _loaded true Always true, indicates that the component is abstract and should not be rendered directly

--- Resolve a field value: call functions with session memo, pass through others.
--- @param comp ManagedComponent  Owner component, passed to function calls.
--- @param key string  The field key to resolve.
--- @param session Session  Session context; nil means no memoization.
--- @return any  Resolved value (function return or literal).
local function resolve_value(comp, key, session)
    local value = rawget(comp, key)
    if type(value) == "function" then
        return session.memo(value, comp, session)
    end
    return value
end
Component.resolve_value = resolve_value


--- Check whether a component is a built-in default component.
--- @param comp ManagedComponent
--- @return boolean
Component.is_default = function(comp)
    return id_module.existed(comp.id)
end

--- Assign and validate a unique id.  Built-ins (`_plug_provided`) skip generation.
--- @param comp Component  May have `id` pre-set; otherwise one is generated.
--- @return CompId The component's (validated or generated) identifier.
--- @return Component The component table (same as `comp`).
Component.setup = function(comp)
    local id = comp.id

    --- @cast comp DefaultComponent
    if comp._plug_provided then
        --- @cast id DefaultId
        return id, comp
    end

    if id then
        id = id_module.validate(id)
    else
        id = tostring(comp) .. tostring(math.random(1, 1000000))
        rawset(comp, "id", id)
    end

    --- @cast comp Component
    --- @cast id CompId
    return id, comp
end

--- Call a lifecycle field if it is a function.
--- @param field string  Component field name (e.g. `"init"`, `"pre_update"`).
--- @param comp ManagedComponent  Passed as `self` to the callback.
local function call_lifecycle(field, comp)
    local value = comp[field]
    if type(value) == "function" then
        value(comp)
    end
end

--- Emit the pre_update lifecycle hook.
--- @param comp ManagedComponent
Component.emit_pre_update = function(comp)
    call_lifecycle("pre_update", comp)
end

--- Emit the post_update lifecycle hook.
--- @param comp ManagedComponent
Component.emit_post_update = function(comp)
    call_lifecycle("post_update", comp)
end

--- Emit the init lifecycle hook.
--- @param comp ManagedComponent
Component.emit_init = function(comp)
    call_lifecycle("init", comp)
end

--- Return the internal hl_name storage field for a given side.
--- @param "left"|"right" side
--- @return "_left_hl_name"|"_right_hl_name"
Component.hl_name_field = function(side)
    return side == "left" and "_left_hl_name" or "_right_hl_name"
end

--- Resolve the separator style for a side of a component.
--- Defaults to SepStyle.SepBg.
--- @param comp ManagedComponent
--- @param "left"|"right" side
--- @return SepStyle|CompStyle
Component.side_style = function(comp, side)
    return comp[side == "left" and "left_style" or "right_style"] or SepStyle.SepBg
end

--- Run `update`, apply padding, return rendered string and optional style.
--- Non-string results become `""`.  Padding: number → both sides, table → left/right.
--- @param comp ManagedComponent  Evaluated component; reads `update`, `padding`.
--- @param session Session  Session context for memoized function calls.
--- @return string  Rendered text (empty string for non-string/nil results).
--- @return CompStyle|nil  Style override from `update`, or nil.
Component.evaluate = function(comp, session)
    local result, style = resolve_value(comp, "update", session)

    if type(result) ~= "string" then
        result = ""
    elseif result ~= "" then
        local padding = resolve_value(comp, "padding" or 1, session)
        local pt = type(padding)
        if pt == "number" and padding > 0 then
            local pad = str_rep(" ", padding)
            result = pad .. result .. pad
        elseif pt == "table" then
            local left = resolve_value(comp, "padding.left" or 0, session)
            local right = resolve_value(comp, "padding.right" or 0, session)

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

--- Load a component by its module path id (derived from a DefaultId).
--- Falls back to Component.require internally.
--- @param id DefaultId
--- @return Component|nil
Component.require_by_id = function(id)
    local path = id_module.path(id)
    return path and Component.require(path) or nil
end

--- Load a component module by path segments.  First segment is
--- prefixed with `"witch-line.components."`.
--- @param path string[]  Segments, e.g. `{"statusline", "mode"}`.
--- @return table|nil  The resolved module table, or nil if not found.
Component.require = function(path)
    local component = require(COMP_MODULE_PATH .. path[1])
    for i = 2, #path do
        component = component[path[i]]
        if not component then
            return nil
        end
    end
    return component
end

--- Resolve the minimum screen width constraint for a component.
--- @param comp ManagedComponent
--- @param session Session
--- @return integer|nil
Component.min_screen_width = function(comp, session)
    local m = resolve_value(comp, "min_screen_width", session)
    return type(m) == "number" and m or nil
end

--- Resolve auto_theme for a component; falls back to `_plug_provided`.
--- @param comp ManagedComponent
--- @param session Session
--- @return boolean
Component.auto_theme = function(comp, session)
    local auto = resolve_value(comp, "auto_theme", session)
    if auto ~= nil then
        return auto
    end
    return comp._plug_provided or false
end

--- Determine whether a component should be hidden in the current context.
--- @param comp ManagedComponent
--- @param session Session
--- @return boolean
Component.hidden = function(comp, session)
    return resolve_value(comp, "hidden", session) == true
end



return Component
